import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { createMCPToken, listMCPTokens, revokeMCPToken } from '../models/auth';

const getBaseUrl = () => {
    if (process.env.BASE_URL) return process.env.BASE_URL;
    const port = process.env.PORT || 3000;
    return process.env.NODE_ENV === 'production'
        ? 'https://mcp.fletcher.app'
        : `http://localhost:${port}`;
};

export default async function mcpApiRoutes(fastify: FastifyInstance) {
    // Auth Middleware: Check API Key (reuse logic from mobile routes?)
    // Actually, mobile routes middleware only applies to /api/locations etc.
    // We need to secure these MCP management endpoints with the User's API Key too.

    // We can rely on the same hook in mobile.ts IF we register this under /api/mcp
    // checking mobile.ts hook:
    // if (routerPath === '/api/register' || routerPath?.startsWith('/auth') || routerPath?.startsWith('/mcp')) return;

    // Wait! The TDD says: "All MCP endpoints require OAuth token: Authorization: Bearer mcp_..." 
    // BUT these are MANAGEMENT endpoints called by the MOBILE APP.
    // So `POST /api/mcp/generate-token` should be secured by `fletch_sk_...`.
    // My previous mobile.ts hook EXEMPTED `/mcp`. That was for the MCP SERVER (SSE).
    // If I put these routes under `/api`, the mobile hook checks them.
    // BUT the mobile hook in `mobile.ts` explicitly checks `routerPath.startsWith('/mcp')` to skip?
    // No, `request.url` starts with `/mcp`?
    // If I mount this at `/api/mcp`, the URL is `/api/mcp/...`.
    // In `mobile.ts`: `if (url === '/api/register' || url.startsWith('/auth') || url.startsWith('/mcp'))`
    // If I mount at `/api`, then `url` starts with `/api/mcp`. Does `startsWith('/mcp')` match? No.
    // So the mobile hook WILL apply to `/api/mcp` routes, which is what we want (User API Key Auth).

    // HOWEVER, `mobile.ts` hook attaches `userId`.
    // If I register this plugin separately, does it share the hook?
    // Fastify hooks are encapsulated if registered in a scope.
    // If `mobile.ts` defines the hook inside its function body, it ONLY applies to routes inside `mobile.ts`.
    // It is NOT global.
    // So I need to implement auth here too, OR refactor auth middleware.
    // For MVP transparency, I'll just duplicate the simple check or import a middleware function.
    // Let's copy-paste the check for now to be safe and independent.

    fastify.addHook('onRequest', async (request, reply) => {
        const authHeader = request.headers['authorization'];
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Missing API Key' } });
        }

        // We need validateAPIKey
        const { validateAPIKey } = await import('../models/user');
        const apiKey = authHeader.replace('Bearer ', '');
        const userId = await validateAPIKey(apiKey);

        if (!userId) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Invalid API Key' } });
        }

        (request as any).userId = userId;
    });

    // 1. Generate Token
    fastify.post('/generate-token', async (request, reply) => {
        const BodySchema = z.object({
            assistant_type: z.literal('claude'),
            token_name: z.string().max(50).optional()
        });

        try {
            const { assistant_type, token_name } = BodySchema.parse(request.body);
            const userId = (request as any).userId;

            const { token, expiresAt } = await createMCPToken(userId, assistant_type, token_name);

            // TDD Spec Response
            return reply.code(201).send({
                token: token,
                sse_url: `${getBaseUrl()}/sse`,
                expires_at: expiresAt,
                instructions: "Add this MCP server to Claude:\n1. Open Claude Settings → Integrations\n2. Click 'Add MCP Server'\n3. Enter the URL and token above"
            });
        } catch (err) {
            fastify.log.error(err);
            return reply.code(400).send({ error: 'Invalid Request' });
        }
    });

    // 2. List Tokens
    fastify.get('/tokens', async (request, reply) => {
        const userId = (request as any).userId;
        const tokens = await listMCPTokens(userId);
        return { tokens };
    });

    // 3. Revoke Token
    fastify.delete('/tokens/:id', async (request, reply) => {
        const userId = (request as any).userId;
        const { id } = request.params as { id: string };

        const success = await revokeMCPToken(userId, id);
        if (success) {
            return { status: 'ok', revoked_at: new Date() };
        } else {
            return reply.code(404).send({ error: 'Token not found' });
        }
    });
}
