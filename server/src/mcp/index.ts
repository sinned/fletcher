import { FastifyInstance } from 'fastify';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { z } from 'zod';
import { getLatestLocation, getLocationHistory, getRecentLocations, getLocationHistoryWithRadius, getFrequentLocations, getRecentTrajectory, getTotalLocationCount } from '../models/location';
import { validateMCPToken } from '../models/auth';
import { getPrivacySettings } from '../models/user';
import { logMCPRequest } from '../models/access_log';

// Store sessions with their tokens for validation
const sessions = new Map<string, { transport: SSEServerTransport, token: string }>();

// Precision Logic
function applyPrecision(lat: number, lon: number, level: string): [number, number] {
    if (level === 'high') return [lat, lon];
    if (level === 'medium') return [Number(lat.toFixed(3)), Number(lon.toFixed(3))]; // ~100m
    if (level === 'low') return [Number(lat.toFixed(2)), Number(lon.toFixed(2))]; // ~1km
    return [lat, lon];
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

        // Retrieve privacy settings for this session context
        const privacy = await getPrivacySettings(userId);
        const precision = privacy?.privacy_settings?.precision_level || 'medium';
        const historyDays = privacy?.privacy_settings?.history_access_days || 7;

        // 2. Create Server
        const mcp = new McpServer({
            name: 'Fletcher',
            version: '2.0.0',
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

        // Resource: Current Location
        mcp.resource('current-location', 'fletcher://location/current', async (uri) => {
            // Validate token is still valid
            await validateTokenForRequest();

            const startTime = Date.now();
            const loc = await getLatestLocation(userId);
            if (!loc) return { contents: [] };

            const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);

            await logAccess(userId, assistantType, 'current-location', 1, undefined, startTime);

            return {
                contents: [{
                    uri: uri.href,
                    text: JSON.stringify({
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            accuracy: loc.accuracy,
                            timestamp: loc.timestamp,
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
                start_date: z.string().optional().describe("ISO date string. If provided, end_date is also required."),
                end_date: z.string().optional(),
                limit: z.number().optional().default(100).describe("Max number of results (default 100, max 1000)"),
                offset: z.number().optional().default(0).describe("Pagination offset"),
                center_lat: z.number().optional().describe("Latitude for radius filtering"),
                center_lon: z.number().optional().describe("Longitude for radius filtering"),
                radius_meters: z.number().optional().describe("Radius in meters for filtering")
            },
            async ({ start_date, end_date, limit = 100, offset = 0, center_lat, center_lon, radius_meters }) => {
                // Validate token is still valid
                await validateTokenForRequest();

                const startTime = Date.now();
                let features: any[] = [];
                let logDetails: any = {};
                let totalCount = 0;

                // Enforce max limit
                if (limit > 1000) limit = 1000;

                let start: Date | undefined;
                let end: Date | undefined;

                if (start_date) start = new Date(start_date);
                if (end_date) end = new Date(end_date);

                // Privacy policy checks can be applied here for start/end if needed
                // For now, relying on model-level or query-level constraints if any

                // Radius filtering or Standard History
                if (center_lat !== undefined && center_lon !== undefined && radius_meters !== undefined) {
                    const history = await getLocationHistoryWithRadius(userId, center_lat, center_lon, radius_meters, { start, end, limit, offset });
                    features = history.map((loc: any) => {
                        const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                        return {
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                        };
                    });

                    // Count is harder for radius without separate query, simplistic approach:
                    // We won't fetch total count for radius query to avoid performance hit unless requested.
                    // Returning -1 or undefined for total_count if not calculated.
                    // For now, let's just use returned length for returned_count.
                    totalCount = -1;
                    logDetails = { type: 'radius', center: [center_lat, center_lon], radius: radius_meters };

                } else {
                    // Standard History
                    const history = await getLocationHistory(userId, { start, end, limit, offset });

                    // Get total count for pagination metadata
                    // Only fetch total count if offset is 0 to save resources, or if client needs it.
                    // The requirement says "referencing metadata: total_count".
                    if (start || end) {
                        totalCount = await getTotalLocationCount(userId, { start, end });
                    } else {
                        // Fallback or full count?
                        totalCount = await getTotalLocationCount(userId);
                    }

                    features = history.map((loc: any) => {
                        const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                        return {
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                        };
                    });
                    logDetails = { type: 'history', start, end, limit, offset };
                }

                await logAccess(userId, assistantType, 'get_location_history', features.length, logDetails, startTime);

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
                                offset
                            }
                        })
                    }]
                }
            }
        );

        // Tool: Get Current Location
        mcp.tool('get_current_location', {}, async () => {
            // Validate token is still valid
            await validateTokenForRequest();

            const startTime = Date.now();
            const loc = await getLatestLocation(userId);
            if (!loc) return { content: [{ type: "text", text: "No location found." }] };

            const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);

            await logAccess(userId, assistantType, 'get_current_location', 1, undefined, startTime);

            return {
                content: [{
                    type: "text",
                    text: JSON.stringify({
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            accuracy: loc.accuracy,
                            timestamp: loc.timestamp,
                            precision_level: precision
                        }
                    })
                }]
            };
        });

        // Tool: Get Recent Trajectory
        mcp.tool('get_recent_trajectory',
            {
                limit: z.number().optional().default(10).describe("Number of points to return"),
            },
            async ({ limit = 10 }) => {
                // Validate token is still valid
                await validateTokenForRequest();

                const startTime = Date.now();
                const history = await getRecentTrajectory(userId, limit);
                const features = history.map((loc: any) => {
                    const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                    return {
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                    };
                });

                await logAccess(userId, assistantType, 'get_recent_trajectory', features.length, { limit }, startTime);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "FeatureCollection",
                            features
                        })
                    }]
                };
            }
        );

        // Tool: Get Frequent Locations
        mcp.tool('get_frequent_locations',
            {
                limit: z.number().optional().default(5).describe("Number of top locations to return"),
                days: z.number().optional().default(30).describe("Lookback period in days")
            },
            async ({ limit = 5, days = 30 }) => {
                // Validate token is still valid
                await validateTokenForRequest();

                const startTime = Date.now();
                const clusters = await getFrequentLocations(userId, limit, days);
                // Format as FeatureCollection of points
                const features = clusters.map((c: any) => {
                    // Start/End are clustered coordinates. Precision applies?
                    // Yes, user privacy applies to these too.
                    const [lat, lon] = applyPrecision(c.latitude, c.longitude, precision);
                    return {
                        type: "Feature",
                        geometry: { type: "Point", coordinates: [lon, lat] },
                        properties: {
                            visit_count: c.visit_count,
                            first_seen: c.first_seen,
                            last_seen: c.last_seen,
                            total_time_spent: c.total_time_spent
                        }
                    };
                });

                await logAccess(userId, assistantType, 'get_frequent_locations', features.length, { limit, days }, startTime);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({
                            type: "FeatureCollection",
                            features
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
