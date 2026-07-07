import fastify from 'fastify';
import dotenv from 'dotenv';
import { z } from 'zod';
import { initDb, query } from './db';
import { startCleanupJob } from './cron';
import { readFileSync } from 'fs';
import { join } from 'path';
import cors from '@fastify/cors';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const requestId = require('fastify-request-id');
import crypto from 'crypto';


dotenv.config();

// Redact an MCP token passed as a query param so it never lands in request logs.
const redactUrl = (url: string) => url.replace(/([?&]token=)[^&]*/gi, '$1[REDACTED]');

const server = fastify({
    logger: {
        level: process.env.LOG_LEVEL || 'info',
        serializers: {
            req(request) {
                return {
                    method: request.method,
                    url: redactUrl(request.url),
                    remoteAddress: request.ip,
                    requestId: request.id
                };
            }
        }
    },
    requestIdLogLabel: 'requestId',
    genReqId: (req) => req.headers['x-request-id'] as string ?? crypto.randomUUID()
});

server.register(requestId);
server.register(cors, {
    // Native app + MCP servers don't use CORS; only browsers do. Fail closed in
    // production when no explicit origin is configured.
    origin: process.env.CORS_ORIGIN || (process.env.NODE_ENV === 'production' ? false : true),
    credentials: true
});

// Global rate limit. Routes can tighten this via `config.rateLimit`.
server.register(require('@fastify/rate-limit'), {
    global: true,
    max: 120,
    timeWindow: '1 minute',
    allowList: ['127.0.0.1'],
    errorResponseBuilder: (_req: any, context: any) => ({
        error: { code: 'RATE_LIMIT_EXCEEDED', message: `Rate limit exceeded, retry after ${context.after}` }
    })
});

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

import mobileRoutes from './routes/mobile';
import mcpApiRoutes from './routes/mcp_api';
import accessLogsRoutes from './routes/access_logs';
import { mcpServerPlugin } from './mcp';

// ... imports

import fastifyStatic from '@fastify/static';

// ... imports

server.register(mobileRoutes, { prefix: '/api' });
server.register(mcpApiRoutes, { prefix: '/api/mcp' }); // Mounted at /api/mcp
server.register(accessLogsRoutes, { prefix: '/api/access-logs' }); // Mounted at /api/access-logs
server.register(require('@fastify/formbody'));

// Serve static files
server.register(fastifyStatic, {
    root: join(__dirname, '../public'),
    prefix: '/', // optional: default is '/'
});

// Register MCP Server Plugin
// No prefix, because it handles /sse and /messages directly
server.register(mcpServerPlugin);

const packageJson = JSON.parse(
    readFileSync(join(__dirname, '../package.json'), 'utf-8')
);
const SERVER_VERSION = packageJson.version;

// Health check
server.get('/health', async (request, reply) => {
    try {
        // Check basic DB connection
        await query('SELECT 1');

        // Check PostGIS extension
        const postgisCheck = await query(
            `SELECT PostGIS_Version() as version`
        );

        return {
            status: 'ok',
            db: 'connected',
            version: SERVER_VERSION,
            postgis: postgisCheck.rows[0]?.version || 'unknown'
        };
    } catch (e) {
        server.log.error(e);
        reply.code(500);
        return {
            status: 'error',
            db: 'disconnected',
            version: SERVER_VERSION
        };
    }
});

// Status route - public operational status. Aggregate user/location counts are
// intentionally not exposed here.
server.get('/status/', async (request, reply) => {
    try {
        await query('SELECT 1');
        return { status: 'ok', version: SERVER_VERSION };
    } catch (e) {
        server.log.error(e);
        reply.code(500);
        return { status: 'error', message: 'Service unavailable' };
    }
});

const start = async () => {
    try {
        try {
            await initDb();
        } catch (e) {
            server.log.error({ err: e }, 'Database initialization failed');
            process.exit(1);
        }
        await server.listen({ port: PORT, host: '0.0.0.0' });
        console.log(`Server listening on ${PORT}`);

        // Start Cron Jobs
        startCleanupJob();
    } catch (err) {

        server.log.error(err);
        process.exit(1);
    }
};



start();

const gracefulShutdown = async (signal: string) => {
    console.log(`Received ${signal}, shutting down gracefully...`);

    try {
        await server.close();
        // await db.pool.end(); // If we exported pool, but we exported query. 
        // We imported pool in db/index.ts, let's fix imports or assume db handles it?
        // Actually we need to access pool to close it. 
        // index.ts has `import { initDb, query } from './db';`
        // We need `pool` from './db'.
        // Let's assume we update import OR import default as db
        const { default: db } = await import('./db');
        await db.pool.end();

        console.log('Shutdown complete');
        process.exit(0);
    } catch (err) {
        console.error('Error during shutdown:', err);
        process.exit(1);
    }
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
