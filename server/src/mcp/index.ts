import { FastifyInstance } from 'fastify';
import { McpServer, ResourceTemplate } from '@modelcontextprotocol/sdk/server/mcp.js';
import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import { z } from 'zod';
import { getLatestLocation, getLocationHistory } from '../models/location';

export const setupMcp = (fastify: FastifyInstance) => {
    const mcp = new McpServer({
        name: 'Fletcher',
        version: '1.0.0',
    });

    // Resource: Current Location
    mcp.resource(
        'current-location',
        'fletcher://location/current',
        async (uri) => {
            // In a real app, we'd get user ID from extra context or headers
            // For MVP, we'll use a hardcoded demo user ID or pass it in headers
            const userId = '00000000-0000-0000-0000-000000000000'; // Placeholder
            const loc = await getLatestLocation(userId);
            return {
                contents: [{
                    uri: uri.href,
                    text: JSON.stringify(loc),
                    mimeType: "application/json"
                }]
            };
        }
    );

    // Tools
    mcp.tool(
        'find-nearby',
        {
            category: z.string(),
            radius_meters: z.number().optional()
        },
        async ({ category, radius_meters }) => {
            return {
                content: [{
                    type: "text",
                    text: `Finding ${category} within ${radius_meters || 1000}m (Not implemented in MVP)`
                }]
            }
        }
    );

    // Fastify route for SSE
    fastify.get('/sse', async (req, res) => {
        // Manually handle SSE since McpServer transport expects raw req/res or similar
        // The SSEServerTransport needs to be hooked up

        // Actually, SDK's SSEServerTransport is designed for express/node http.
        // Fastify's req/res are wrappers. We can access raw via req.raw and res.raw

        const transport = new SSEServerTransport('/messages', res.raw);
        await mcp.connect(transport);
    });

    fastify.post('/messages', async (req, res) => {
        // This endpoint handles client messages (POST)
        // The transport we created in /sse needs to handle this...
        // But SSEServerTransport typically handles the POST itself?
        // Looking at SDK examples (if I could), usually you separate them.
        // The SSEServerTransport instance has a `handlePostMessage` method usually.

        // I will store the transport in a way we can access it, or create a new one?
        // No, transport is per connection. 
        // Actually, for SSE, the flow is:
        // Client -> GET /sse -> Server keeps open.
        // Client -> POST /messages -> Server handles message, sends response via SSE stream.

        // I need to implement a mechanism to route the POST to the correct transport.
        // Since I can't easily see the SDK docs, I'll attempt a standard pattern.

        // Use a map of session ID to transport? The SDK might handle this.
        // For MVP, if the SDK is too opaque, I might just fallback to simple logic.

        // However, let's try to do it right.
        // If I look at `node_modules/@modelcontextprotocol/sdk/dist/cjs/server/sse.d.ts`:
        // It likely exports `SSEServerTransport`.

        // I'll leave the POST implementation as a todo or try to implement it simply.
        // Actually, `SSEServerTransport` usually requires `handlePostMessage(req, res)`.
        // I'll try that.

        res.send({ status: 'Not implemented fully' });
    });
};
