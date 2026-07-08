import { FastifyInstance } from 'fastify';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { z } from 'zod';
import { getLatestLocation, getLocationHistory, getRecentLocations, getLocationHistoryWithRadius, getFrequentLocations, getRecentTrajectory, getTotalLocationCount, getLocationAtTime, getDistanceSummary, getPlaceVisits, getDaySummary, getSignificantPlaces, getDataCoverage } from '../models/location';
import { validateMCPToken } from '../models/auth';
import { getPrivacySettings } from '../models/user';
import { logMCPRequest } from '../models/access_log';

// Store sessions with their tokens for validation
const sessions = new Map<string, { transport: SSEServerTransport, token: string }>();

import { DateTime, IANAZone } from 'luxon';

// ... (existing imports)

// Precision Logic
function applyPrecision(lat: number, lon: number, level: string): [number, number] {
    if (level === 'high') return [lat, lon];
    if (level === 'medium') return [Number(lat.toFixed(3)), Number(lon.toFixed(3))]; // ~100m
    if (level === 'low') return [Number(lat.toFixed(2)), Number(lon.toFixed(2))]; // ~1km
    return [lat, lon];
}

// Minimum radius for caller-supplied radius searches, matching the coordinate
// rounding of each precision level. Without this, a low/medium-precision token
// could probe a grid of coordinates with a tiny radius and use the match
// counts to reconstruct exact positions the coordinate tools would only return
// rounded — a precision bypass.
function precisionFloorMeters(level: string): number {
    if (level === 'low') return 1500;    // ~1km rounding cell
    if (level === 'medium') return 150;  // ~100m rounding cell
    return 0;                            // high: no floor
}

// Great-circle distance in meters between two lat/lon points (used for
// client-side trip segmentation).
function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000;
    const toRad = (d: number) => d * Math.PI / 180;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    return 2 * R * Math.asin(Math.min(1, Math.sqrt(a)));
}

async function logAccess(userId: string, assistantType: string, endpoint: string, count: number, params?: any, startTime?: number) {
    const responseTimeMs = startTime ? Date.now() - startTime : undefined;
    await logMCPRequest(userId, assistantType, endpoint, count, params, responseTimeMs);
}

// Plugin Definition
export const mcpServerPlugin = async (fastify: FastifyInstance) => {

    // Override default JSON parser to preserve the stream for the SDK
    fastify.addContentTypeParser('application/json', (req, payload, done) => {
        done(null, payload);
    });

    fastify.get('/sse', async (req, res) => {
        // ... (Auth Logic same as before)
        // 1. Auth
        let token: string | undefined;

        const authHeader = req.headers['authorization'];
        if (authHeader) {
            token = authHeader.replace('Bearer ', '');
        } else {
            token = (req.query as any).token;
        }

        if (!token) return res.code(401).send({ error: 'Missing Authorization header or token query parameter' });

        const tokenData = await validateMCPToken(token);

        if (!tokenData) return res.code(403).send({ error: 'Invalid token' });

        const { userId, assistantType } = tokenData;

        // Enforce access at connect time: a disabled account shares nothing.
        const initialSettings = await getPrivacySettings(userId);
        if (initialSettings?.enabled === false) {
            return res.code(403).send({ error: 'Location sharing is disabled for this account' });
        }

        // 2. Create Server
        const mcp = new McpServer({
            name: 'Fletcher',
            version: '2.1.0',
        });

        // Hijack Fastify's response handling to allow raw SSE stream
        // This prevents Fastify from trying to send a response after this handler returns
        // res is 'reply', req is 'request' in Fastify. Wait, arguments are (req, res).
        // Standard fastify handler: (request, reply)
        // My code: (req, res). So 'res' is the Reply object.
        res.hijack();

        console.log(`[MCP] Client connected. Token validated for user: ${userId}`);

        // Helper to validate token on each request
        const validateTokenForRequest = async () => {
            const tokenData = await validateMCPToken(token!);
            if (!tokenData) {
                console.log(`[MCP] Token validation failed during request - likely revoked`);
                throw new Error('Token has been revoked or is invalid');
            }
            return tokenData;
        };

        // Fetch privacy settings on every request so tightened precision, a
        // shortened history window, or a flipped "enabled" switch take effect
        // mid-session instead of being frozen at connect time.
        const getLiveSettings = async (): Promise<{ precision: string; historyDays: number }> => {
            const p = await getPrivacySettings(userId);
            if (p?.enabled === false) {
                throw new Error('Location sharing is disabled for this account');
            }
            return {
                precision: (p?.precision_level as string) || 'medium',
                historyDays: (p?.history_access_days as number) ?? 7,
            };
        };

        // Helper for timezone formatting
        const formatWithTimezone = (dateStr: string, timezone: string) => {
            // Assume dateStr is UTC ISO from DB (e.g., 2026-01-04T18:23:56.000Z) or Date object
            // If it's a string, construct from ISO. If it's a Date, construct from JS Date
            let dt: DateTime;
            if (typeof dateStr === 'string') {
                dt = DateTime.fromISO(dateStr, { zone: 'utc' });
            } else {
                dt = DateTime.fromJSDate(dateStr, { zone: 'utc' });
            }

            // Convert to target timezone
            const zoned = dt.setZone(timezone);

            return {
                timestamp: zoned.toISO(), // 2026-01-04T10:23:56-08:00
                timestamp_utc: dt.toUTC().toISO(),
                offset: zoned.toFormat('ZZ') // -08:00
            };
        };

        // Resource: Current Location
        mcp.resource('current-location', 'fletcher://location/current', async (uri) => {
            // Validate token is still valid
            await validateTokenForRequest();
            const { precision } = await getLiveSettings();

            const startTime = Date.now();
            const loc = await getLatestLocation(userId);
            if (!loc) return { contents: [] };

            const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);

            await logAccess(userId, assistantType, 'current-location', 1, undefined, startTime);

            // Default timezone for resources? Let's stick to UTC for raw resources to act as source of truth, 
            // OR use a user preference if we had it easily accessible. 
            // For consistency with new tools, we'll keep resources "raw" (UTC) or maybe standard ISO.
            // But requirements focus on "tools". Let's stick to standard behavior for resources for now (UTC), 
            // as they are typically consumed programmatically. 
            // If we want to change resources too:
            // "Add timezone parameter to all location tools" - implies Tools, not Resources.

            return {
                contents: [{
                    uri: uri.href,
                    text: JSON.stringify({
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            accuracy: loc.accuracy,
                            timestamp: loc.timestamp, // UTC usually
                            precision_level: precision
                        }
                    }),
                    mimeType: "application/geo+json"
                }]
            };
        });

        // Resource: History (Last 24h, limited by settings)
        mcp.resource('location-history', 'fletcher://location/history', async (uri) => {
            // Validate token is still valid
            await validateTokenForRequest();
            const { precision, historyDays } = await getLiveSettings();

            const startTime = Date.now();
            const end = new Date();
            // Default resource is 24h, but restricted by user setting if < 1 day (e.g. 0)
            const days = Math.min(1, historyDays);
            const start = new Date(end.getTime() - days * 24 * 60 * 60 * 1000);

            const history = await getLocationHistory(userId, { start, end });

            // Apply precision to all
            const features = history.map((loc: any) => {
                const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                return {
                    type: "Feature",
                    geometry: { type: "Point", coordinates: [lon, lat] },
                    properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                };
            });

            await logAccess(userId, assistantType, 'location-history', features.length, undefined, startTime);

            return {
                contents: [{
                    uri: uri.href,
                    text: JSON.stringify({ type: "FeatureCollection", features }),
                    mimeType: "application/geo+json"
                }]
            };
        });

        mcp.tool('get_location_history',
            {
                start_date: z.string().optional().describe("ISO date string (e.g., 2026-01-04). Interpreted in the specified timezone."),
                end_date: z.string().optional().describe("ISO date string. Interpreted in the specified timezone."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier (e.g., America/Los_Angeles, Europe/London). Defaults to America/Los_Angeles."),
                limit: z.number().optional().default(100).describe("Max number of results (default 100, max 1000)"),
                offset: z.number().optional().default(0).describe("Pagination offset"),
                center_lat: z.number().optional().describe("Latitude for radius filtering"),
                center_lon: z.number().optional().describe("Longitude for radius filtering"),
                radius_meters: z.number().optional().describe("Radius in meters for filtering")
            },
            async ({ start_date, end_date, timezone = 'America/Los_Angeles', limit = 100, offset = 0, center_lat, center_lon, radius_meters }) => {
                // Validate token is still valid
                await validateTokenForRequest();
                const { precision, historyDays } = await getLiveSettings();

                const startTime = Date.now();
                let features: any[] = [];
                let logDetails: any = {};
                let totalCount = 0;

                // Validate timezone before it reaches Luxon/Postgres.
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}. Use an IANA name like America/Los_Angeles.` }] };
                }

                // Clamp pagination into sane bounds.
                if (limit > 1000) limit = 1000;
                if (limit < 1) limit = 1;
                if (offset < 0) offset = 0;

                let start: Date | undefined;
                let end: Date | undefined;

                // Convert inputs to UTC based on timezone. A bare date ("2026-01-04")
                // means the whole day, so the end bound snaps to end-of-day.
                const dateOnly = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s.trim());
                if (start_date) {
                    const p = DateTime.fromISO(start_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid start_date: ${start_date}` }] };
                    start = p.toJSDate();
                }
                if (end_date) {
                    const p = DateTime.fromISO(end_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid end_date: ${end_date}` }] };
                    end = (dateOnly(end_date) ? p.endOf('day') : p).toJSDate();
                }

                // Enforce the user's history_access_days window: assistants may not
                // read further back than now - historyDays.
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();
                if (!start || start < cutoff) start = cutoff;

                // Radius filtering or Standard History
                let history: any[] = [];
                if (center_lat !== undefined && center_lon !== undefined && radius_meters !== undefined) {
                    // Enforce the precision floor so a coarse-precision token can't
                    // probe finer than it's allowed to resolve via a tiny radius.
                    radius_meters = Math.max(radius_meters, precisionFloorMeters(precision));
                    history = await getLocationHistoryWithRadius(userId, center_lat, center_lon, radius_meters, { start, end, limit, offset });

                    // Count is harder for radius without separate query, simplistic approach:
                    // We won't fetch total count for radius query to avoid performance hit unless requested.
                    // Returning -1 or undefined for total_count if not calculated.
                    // For now, let's just use returned length for returned_count.
                    totalCount = -1;
                    logDetails = { type: 'radius', center: [center_lat, center_lon], radius: radius_meters, timezone };

                } else {
                    // Standard History
                    history = await getLocationHistory(userId, { start, end, limit, offset });

                    // Get total count for pagination metadata
                    // Only fetch total count if offset is 0 to save resources, or if client needs it.
                    // The requirement says "referencing metadata: total_count".
                    if (start || end) {
                        totalCount = await getTotalLocationCount(userId, { start, end });
                    } else {
                        // Fallback or full count?
                        totalCount = await getTotalLocationCount(userId);
                    }
                    logDetails = { type: 'history', start, end, limit, offset, timezone };
                }

                features = history.map((loc: any) => {
                    const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                    const timeData = formatWithTimezone(loc.timestamp, timezone);
                    return {
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            accuracy: loc.accuracy,
                            timestamp: timeData.timestamp,
                            timestamp_utc: timeData.timestamp_utc
                        }
                    };
                });

                await logAccess(userId, assistantType, 'get_location_history', features.length, logDetails, startTime);

                // Get offset from timezone for metadata (approximated from now or first record?)
                // Just use current offset for that timezone
                const currentOffset = DateTime.now().setZone(timezone).toFormat('ZZ');

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "FeatureCollection",
                            features,
                            metadata: {
                                total_count: totalCount >= 0 ? totalCount : undefined,
                                returned_count: features.length,
                                has_more: totalCount > offset + features.length,
                                limit,
                                offset,
                                timezone,
                                timezone_offset: currentOffset
                            }
                        })
                    }]
                }
            }
        );

        // Tool: Get Latest Location
        mcp.tool('get_latest_location',
            {
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ timezone = 'America/Los_Angeles' }) => {
                // Validate token is still valid
                await validateTokenForRequest();
                const { precision } = await getLiveSettings();

                const startTime = Date.now();
                const loc = await getLatestLocation(userId);
                if (!loc) return { content: [{ type: "text", text: "No location found." }] };

                const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                const timeData = formatWithTimezone(loc.timestamp, timezone);

                await logAccess(userId, assistantType, 'get_latest_location', 1, { timezone }, startTime);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: {
                                accuracy: loc.accuracy,
                                timestamp: timeData.timestamp,
                                timestamp_utc: timeData.timestamp_utc,
                                precision_level: precision
                            },
                            metadata: {
                                timezone,
                                timezone_offset: timeData.offset
                            }
                        })
                    }]
                };
            });

        // Tool: Get Recent Trajectory
        mcp.tool('get_recent_trajectory',
            {
                limit: z.number().optional().default(10).describe("Number of points to return"),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ limit = 10, timezone = 'America/Los_Angeles' }) => {
                // Validate token is still valid
                await validateTokenForRequest();
                const { precision } = await getLiveSettings();
                if (limit > 1000) limit = 1000;
                if (limit < 1) limit = 1;

                const startTime = Date.now();
                const history = await getRecentTrajectory(userId, limit);
                const features = history.map((loc: any) => {
                    const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                    const timeData = formatWithTimezone(loc.timestamp, timezone);
                    return {
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            accuracy: loc.accuracy,
                            timestamp: timeData.timestamp,
                            timestamp_utc: timeData.timestamp_utc
                        }
                    };
                });

                await logAccess(userId, assistantType, 'get_recent_trajectory', features.length, { limit, timezone }, startTime);

                const currentOffset = DateTime.now().setZone(timezone).toFormat('ZZ');

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "FeatureCollection",
                            features,
                            metadata: {
                                timezone,
                                timezone_offset: currentOffset
                            }
                        })
                    }]
                };
            }
        );

        // Tool: Get Frequent Locations
        mcp.tool('get_frequent_locations',
            {
                limit: z.number().optional().default(5).describe("Number of top locations to return"),
                days: z.number().optional().default(30).describe("Lookback period in days"),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ limit = 5, days = 30, timezone = 'America/Los_Angeles' }) => {
                // Validate token is still valid
                await validateTokenForRequest();
                const { precision, historyDays } = await getLiveSettings();
                // The lookback cannot exceed the user's history access window.
                if (days > historyDays) days = historyDays;
                if (limit < 1) limit = 1;

                const startTime = Date.now();
                const clusters = await getFrequentLocations(userId, limit, days);
                // Format as FeatureCollection of points
                const features = clusters.map((c: any) => {
                    // Start/End are clustered coordinates. Precision applies?
                    // Yes, user privacy applies to these too.
                    const [lat, lon] = applyPrecision(c.latitude, c.longitude, precision);
                    const firstSeenData = formatWithTimezone(c.first_seen, timezone);
                    const lastSeenData = formatWithTimezone(c.last_seen, timezone);

                    return {
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            visit_count: c.visit_count,
                            first_seen: firstSeenData.timestamp,
                            first_seen_utc: firstSeenData.timestamp_utc,
                            last_seen: lastSeenData.timestamp,
                            last_seen_utc: lastSeenData.timestamp_utc,
                            total_time_spent: c.total_time_spent
                        }
                    };
                });

                await logAccess(userId, assistantType, 'get_frequent_locations', features.length, { limit, days, timezone }, startTime);

                const currentOffset = DateTime.now().setZone(timezone).toFormat('ZZ');

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "FeatureCollection",
                            features,
                            metadata: {
                                timezone,
                                timezone_offset: currentOffset
                            }
                        })
                    }]
                };
            }
        );

        // Tool: Where was I at a given time?
        mcp.tool('get_location_at_time',
            {
                datetime: z.string().describe("Target date-time (ISO 8601, e.g. 2026-01-04T15:00). Interpreted in the specified timezone."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ datetime, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { precision, historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                const parsed = DateTime.fromISO(datetime, { zone: timezone });
                if (!parsed.isValid) {
                    return { content: [{ type: "text", text: `Invalid datetime: ${datetime}.` }] };
                }
                const target = parsed.toJSDate();
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();

                const startTime = Date.now();
                const loc = await getLocationAtTime(userId, target, { start: cutoff });
                await logAccess(userId, assistantType, 'get_location_at_time', loc ? 1 : 0, { datetime, timezone }, startTime);
                if (!loc) return { content: [{ type: "text", text: "No location found within the accessible history window." }] };

                const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                const timeData = formatWithTimezone(loc.timestamp, timezone);
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: {
                                accuracy: loc.accuracy,
                                timestamp: timeData.timestamp,
                                timestamp_utc: timeData.timestamp_utc,
                                minutes_from_requested: Math.round(Number(loc.diff_seconds) / 60),
                                precision_level: precision
                            },
                            metadata: { timezone, timezone_offset: timeData.offset }
                        })
                    }]
                };
            }
        );

        // Tool: How far did I travel over a period?
        mcp.tool('get_distance_summary',
            {
                start_date: z.string().optional().describe("Start date (ISO 8601). Defaults to the start of the accessible window."),
                end_date: z.string().optional().describe("End date (ISO 8601). A bare date counts the whole day."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ start_date, end_date, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                const dateOnly = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s.trim());
                let start: Date | undefined;
                let end: Date | undefined;
                if (start_date) {
                    const p = DateTime.fromISO(start_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid start_date: ${start_date}.` }] };
                    start = p.toJSDate();
                }
                if (end_date) {
                    const p = DateTime.fromISO(end_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid end_date: ${end_date}.` }] };
                    end = (dateOnly(end_date) ? p.endOf('day') : p).toJSDate();
                }
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();
                if (!start || start < cutoff) start = cutoff;

                const startTime = Date.now();
                const summary = await getDistanceSummary(userId, { start, end });
                await logAccess(userId, assistantType, 'get_distance_summary', summary.points, { start, end, timezone }, startTime);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            distance_meters: Math.round(summary.meters),
                            distance_km: Math.round(summary.meters / 100) / 10,
                            distance_miles: Math.round(summary.meters / 160.934) / 10,
                            points: summary.points,
                            metadata: { start: start?.toISOString(), end: end?.toISOString(), timezone }
                        })
                    }]
                };
            }
        );

        // Tool: How often was I near a place?
        mcp.tool('get_place_visits',
            {
                center_lat: z.number().describe("Latitude of the place to check."),
                center_lon: z.number().describe("Longitude of the place to check."),
                radius_meters: z.number().optional().default(150).describe("Match radius in meters (default 150)."),
                days: z.number().optional().default(30).describe("Lookback period in days."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ center_lat, center_lon, radius_meters = 150, days = 30, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { historyDays, precision } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                if (days > historyDays) days = historyDays;
                // Enforce the precision floor so a coarse-precision token can't
                // probe finer than it's allowed to resolve.
                radius_meters = Math.max(radius_meters, precisionFloorMeters(precision));
                const start = DateTime.now().minus({ days }).toJSDate();

                const startTime = Date.now();
                const visits = await getPlaceVisits(userId, center_lat, center_lon, radius_meters, { start });
                await logAccess(userId, assistantType, 'get_place_visits', visits.visit_count, { center: [center_lat, center_lon], radius_meters, days, timezone }, startTime);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            visit_count: visits.visit_count,
                            first_seen: visits.first_seen ? formatWithTimezone(visits.first_seen, timezone).timestamp : null,
                            last_seen: visits.last_seen ? formatWithTimezone(visits.last_seen, timezone).timestamp : null,
                            metadata: { center: [center_lat, center_lon], radius_meters, days, timezone }
                        })
                    }]
                };
            }
        );

        // Tool: Summarize a day (or period)
        mcp.tool('get_day_summary',
            {
                date: z.string().optional().describe("Day to summarize (YYYY-MM-DD). Defaults to today. Ignored if start_date/end_date given."),
                start_date: z.string().optional().describe("Range start (ISO 8601). Use with end_date for a multi-day summary."),
                end_date: z.string().optional().describe("Range end (ISO 8601)."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ date, start_date, end_date, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                let start: Date, end: Date;
                if (start_date || end_date) {
                    const s = DateTime.fromISO(start_date || date || '', { zone: timezone });
                    const e = DateTime.fromISO(end_date || start_date || date || '', { zone: timezone });
                    if (!s.isValid || !e.isValid) return { content: [{ type: "text", text: "Invalid date range." }] };
                    start = s.startOf('day').toJSDate();
                    end = e.endOf('day').toJSDate();
                } else {
                    const d = date ? DateTime.fromISO(date, { zone: timezone }) : DateTime.now().setZone(timezone);
                    if (!d.isValid) return { content: [{ type: "text", text: `Invalid date: ${date}.` }] };
                    start = d.startOf('day').toJSDate();
                    end = d.endOf('day').toJSDate();
                }
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();
                if (start < cutoff) start = cutoff;

                const startTime = Date.now();
                const s = await getDaySummary(userId, { start, end });
                await logAccess(userId, assistantType, 'get_day_summary', s.points, { start, end, timezone }, startTime);

                const active = (s.first_seen && s.last_seen)
                    ? Math.round((new Date(s.last_seen).getTime() - new Date(s.first_seen).getTime()) / 60000)
                    : 0;
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            range: { start: start.toISOString(), end: end.toISOString(), timezone },
                            points: s.points,
                            distance_km: Math.round(s.meters / 100) / 10,
                            distinct_places: s.distinct_places,
                            first_movement: s.first_seen ? formatWithTimezone(s.first_seen, timezone).timestamp : null,
                            last_movement: s.last_seen ? formatWithTimezone(s.last_seen, timezone).timestamp : null,
                            active_minutes: active
                        })
                    }]
                };
            }
        );

        // Tool: Infer home and work
        mcp.tool('get_significant_places',
            {
                days: z.number().optional().default(30).describe("Lookback period in days."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ days = 30, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { precision, historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                if (days > historyDays) days = historyDays;
                const start = DateTime.now().minus({ days }).toJSDate();

                const startTime = Date.now();
                const { home, work } = await getSignificantPlaces(userId, timezone, { start });
                await logAccess(userId, assistantType, 'get_significant_places', (home ? 1 : 0) + (work ? 1 : 0), { days, timezone }, startTime);

                const fmt = (p: any, label: string) => {
                    if (!p) return null;
                    const [lat, lon] = applyPrecision(p.latitude, p.longitude, precision);
                    return { type: "Feature", geometry: { type: "Point", coordinates: [lon, lat] }, properties: { label, sample_count: p.sample_count } };
                };
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            home: fmt(home, 'home'),
                            work: fmt(work, 'work'),
                            note: "Inferred from nighttime (home) and weekday-daytime (work) clusters. May coincide for remote workers.",
                            metadata: { days, timezone }
                        })
                    }]
                };
            }
        );

        // Tool: Segment the track into trips
        mcp.tool('get_trips',
            {
                start_date: z.string().optional().describe("Range start (ISO 8601). Defaults to the start of the accessible window."),
                end_date: z.string().optional().describe("Range end (ISO 8601). A bare date counts the whole day."),
                min_gap_minutes: z.number().optional().default(20).describe("A stationary gap longer than this splits trips (default 20)."),
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ start_date, end_date, min_gap_minutes = 20, timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { precision, historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                const dateOnly = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s.trim());
                let start: Date | undefined;
                let end: Date | undefined;
                if (start_date) {
                    const p = DateTime.fromISO(start_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid start_date: ${start_date}.` }] };
                    start = p.toJSDate();
                }
                if (end_date) {
                    const p = DateTime.fromISO(end_date, { zone: timezone });
                    if (!p.isValid) return { content: [{ type: "text", text: `Invalid end_date: ${end_date}.` }] };
                    end = (dateOnly(end_date) ? p.endOf('day') : p).toJSDate();
                }
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();
                if (!start || start < cutoff) start = cutoff;
                if (min_gap_minutes < 1) min_gap_minutes = 1;

                const startTime = Date.now();
                const points = await getLocationHistory(userId, { start, end, limit: 5000 });

                // Segment into trips at stationary gaps; Fletcher records on
                // movement, so a long gap between points means the user stayed put.
                const gapMs = min_gap_minutes * 60 * 1000;
                const trips: any[] = [];
                let seg: any[] = [];
                const flush = () => {
                    if (seg.length < 2) { seg = []; return; }
                    let meters = 0;
                    for (let i = 1; i < seg.length; i++) {
                        meters += haversineMeters(seg[i - 1].latitude, seg[i - 1].longitude, seg[i].latitude, seg[i].longitude);
                    }
                    if (meters < 100) { seg = []; return; } // drop trivial jitter
                    const first = seg[0], last = seg[seg.length - 1];
                    const [slat, slon] = applyPrecision(first.latitude, first.longitude, precision);
                    const [elat, elon] = applyPrecision(last.latitude, last.longitude, precision);
                    trips.push({
                        start_time: formatWithTimezone(first.timestamp, timezone).timestamp,
                        end_time: formatWithTimezone(last.timestamp, timezone).timestamp,
                        duration_minutes: Math.round((new Date(last.timestamp).getTime() - new Date(first.timestamp).getTime()) / 60000),
                        distance_km: Math.round(meters / 100) / 10,
                        start: [slon, slat],
                        end: [elon, elat],
                        points: seg.length
                    });
                    seg = [];
                };
                for (const p of points) {
                    if (seg.length && (new Date(p.timestamp).getTime() - new Date(seg[seg.length - 1].timestamp).getTime()) > gapMs) {
                        flush();
                    }
                    seg.push(p);
                }
                flush();

                await logAccess(userId, assistantType, 'get_trips', trips.length, { start, end, timezone }, startTime);
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            trips,
                            trip_count: trips.length,
                            metadata: { start: start.toISOString(), end: end?.toISOString(), min_gap_minutes, timezone }
                        })
                    }]
                };
            }
        );

        // Tool: What data is available?
        mcp.tool('get_data_coverage',
            {
                timezone: z.string().optional().default('America/Los_Angeles').describe("IANA timezone identifier. Defaults to America/Los_Angeles.")
            },
            async ({ timezone = 'America/Los_Angeles' }) => {
                await validateTokenForRequest();
                const { historyDays } = await getLiveSettings();
                if (!IANAZone.isValidZone(timezone)) {
                    return { content: [{ type: "text", text: `Invalid timezone: ${timezone}.` }] };
                }
                // Clamp to the accessible window so coverage never reports data
                // outside the history the assistant is allowed to read.
                const cutoff = DateTime.now().minus({ days: historyDays }).toJSDate();
                const startTime = Date.now();
                const cov = await getDataCoverage(userId, timezone, { start: cutoff });
                await logAccess(userId, assistantType, 'get_data_coverage', cov.total_points, { timezone }, startTime);
                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            total_points: cov.total_points,
                            earliest: cov.earliest ? formatWithTimezone(cov.earliest, timezone).timestamp : null,
                            latest: cov.latest ? formatWithTimezone(cov.latest, timezone).timestamp : null,
                            days_with_data: cov.days_with_data,
                            history_access_days: historyDays,
                            note: `An assistant can only read the most recent ${historyDays} days at the precision set by the user.`
                        })
                    }]
                };
            }
        );

        // 3. Transport
        const transport = new SSEServerTransport('/messages', res.raw);
        await mcp.connect(transport);

        const sessionId = (transport as any).sessionId;
        if (sessionId) {
            sessions.set(sessionId, { transport, token: token! });
        }

        req.raw.on('close', () => {
            if (sessionId) sessions.delete(sessionId);
        });
    });

    fastify.post('/messages', async (req, res) => {
        const sessionId = (req.query as any).sessionId;
        console.log(`[MCP] POST /messages sessionId=${sessionId}`);
        if (!sessionId) return res.code(400).send('Missing sessionId');

        const session = sessions.get(sessionId);
        if (!session) {
            console.log(`[MCP] Session not found: ${sessionId}`);
            return res.code(404).send('Session not found');
        }

        // Validate token is still valid before processing message
        const tokenData = await validateMCPToken(session.token);
        if (!tokenData) {
            console.log(`[MCP] Token revoked for session ${sessionId}, closing connection`);
            sessions.delete(sessionId);
            return res.code(403).send('Token has been revoked');
        }

        await session.transport.handlePostMessage(req.raw, res.raw);
        console.log(`[MCP] Handled Post Message for ${sessionId}`);
    });
};
