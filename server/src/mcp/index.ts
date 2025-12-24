import { FastifyInstance } from 'fastify';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { z } from 'zod';
import { getLatestLocation, getLocationHistory, getRecentLocations } from '../models/location';
import { validateMCPToken } from '../models/auth';
import { getPrivacySettings } from '../models/user';
import { query } from '../db';

const sessions = new Map<string, SSEServerTransport>();

// Precision Logic
function applyPrecision(lat: number, lon: number, level: string): [number, number] {
    if (level === 'high') return [lat, lon];
    if (level === 'medium') return [Number(lat.toFixed(3)), Number(lon.toFixed(3))]; // ~100m
    if (level === 'low') return [Number(lat.toFixed(2)), Number(lon.toFixed(2))]; // ~1km
    return [lat, lon];
}

async function logAccess(userId: string, endpoint: string, count: number, params?: any) {
    await query(
        `INSERT INTO access_logs (user_id, assistant_type, endpoint, location_count, query_params)
         VALUES ($1, 'claude', $2, $3, $4)`,
        [userId, endpoint, count, params ? JSON.stringify(params) : null]
    );
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

        const userId = await validateMCPToken(token);

        if (!userId) return res.code(403).send({ error: 'Invalid token' });

        // Retrieve privacy settings for this session context
        const privacy = await getPrivacySettings(userId);
        const precision = privacy?.privacy_settings?.precision_level || 'medium';
        const historyDays = privacy?.privacy_settings?.history_access_days || 7;

        // 2. Create Server
        const mcp = new McpServer({
            name: 'Fletcher',
            version: '2.0.0',
        });

        // Resource: Current Location
        mcp.resource('current-location', 'fletcher://location/current', async (uri) => {
            const loc = await getLatestLocation(userId);
            if (!loc) return { contents: [] };

            const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);

            await logAccess(userId, 'current-location', 1);

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
            const end = new Date();
            // Default resource is 24h, but restricted by user setting if < 1 day (e.g. 0)
            const days = Math.min(1, historyDays);
            const start = new Date(end.getTime() - days * 24 * 60 * 60 * 1000);

            const history = await getLocationHistory(userId, start, end);

            // Apply precision to all
            const features = history.map((loc: any) => {
                const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                return {
                    type: "Feature",
                    geometry: { type: "Point", coordinates: [lon, lat] },
                    properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                };
            });

            await logAccess(userId, 'location-history', features.length);

            return {
                contents: [{
                    uri: uri.href,
                    text: JSON.stringify({ type: "FeatureCollection", features }),
                    mimeType: "application/geo+json"
                }]
            };
        });

        // Tool: Get History with Range or Recent
        mcp.tool('get_location_history',
            {
                start_date: z.string().optional().describe("ISO date string. If provided, end_date is also required."),
                end_date: z.string().optional()
            },
            async ({ start_date, end_date }) => {
                let features: any[] = [];
                let logDetails: any = {};

                if (start_date && end_date) {
                    let start = new Date(start_date);
                    let end = new Date(end_date);

                    // Enforce policies
                    const now = new Date();
                    if (end > now) end = now;

                    // Limit range to historyDays
                    const maxStart = new Date(now.getTime() - historyDays * 24 * 60 * 60 * 1000);
                    if (start < maxStart) start = maxStart;

                    if (start > end) {
                        return { content: [{ type: "text", text: "Invalid range or restricted by privacy settings." }] };
                    }

                    const history = await getLocationHistory(userId, start, end);
                    features = history.map((loc: any) => {
                        const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                        return {
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                        };
                    });
                    logDetails = { type: 'range', start_date, end_date };
                } else {
                    // Fallback: Get recent 10 points
                    const history = await getRecentLocations(userId, 10);
                    features = history.map((loc: any) => {
                        const [lat, lon] = applyPrecision(loc.latitude, loc.longitude, precision);
                        return {
                            type: "Feature",
                            geometry: { type: "Point", coordinates: [lon, lat] },
                            properties: { accuracy: loc.accuracy, timestamp: loc.timestamp }
                        };
                    });
                    logDetails = { type: 'recent', count: 10 };
                }

                await logAccess(userId, 'get_location_history', features.length, logDetails);

                return {
                    content: [{
                        type: "text",
                        text: JSON.stringify({ type: "FeatureCollection", features })
                    }]
                }
            }
        );

        // 3. Transport
        const transport = new SSEServerTransport('/messages', res.raw);
        await mcp.connect(transport);

        const sessionId = (transport as any).sessionId;
        if (sessionId) sessions.set(sessionId, transport);

        req.raw.on('close', () => {
            if (sessionId) sessions.delete(sessionId);
        });
    });

    fastify.post('/messages', async (req, res) => {
        const sessionId = (req.query as any).sessionId;
        console.log(`[MCP] POST /messages sessionId=${sessionId}`);
        if (!sessionId) return res.code(400).send('Missing sessionId');

        const transport = sessions.get(sessionId);
        if (!transport) {
            console.log(`[MCP] Session not found: ${sessionId}`);
            return res.code(404).send('Session not found');
        }

        await transport.handlePostMessage(req.raw, res.raw);
        console.log(`[MCP] Handled Post Message for ${sessionId}`);
    });
};
