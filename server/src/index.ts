import fastify from 'fastify';
import dotenv from 'dotenv';
import { z } from 'zod';
import { initDb, query } from './db';
import { startCleanupJob } from './cron';
import { readFileSync } from 'fs';
import { join } from 'path';
import cors from '@fastify/cors';
import requestId from 'fastify-request-id';
import crypto from 'crypto';


dotenv.config();

const server = fastify({
    logger: {
        level: process.env.LOG_LEVEL || 'info',
        serializers: {
            req(request) {
                return {
                    method: request.method,
                    url: request.url,
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
    origin: process.env.CORS_ORIGIN || true,
    credentials: true
});

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

import mobileRoutes from './routes/mobile';
import mcpApiRoutes from './routes/mcp_api';
import { mcpServerPlugin } from './mcp';

// ... imports

server.register(mobileRoutes, { prefix: '/api' });
server.register(mcpApiRoutes, { prefix: '/api/mcp' }); // Mounted at /api/mcp
server.register(require('@fastify/formbody'));

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

// Root route - stats
server.get('/', async (request, reply) => {
    try {
        const usersRes = await query('SELECT COUNT(*) as count FROM users');
        const locationsRes = await query('SELECT COUNT(*) as count FROM locations');

        return {
            status: 'ok',
            version: SERVER_VERSION,
            users: parseInt(usersRes.rows[0].count),
            locations: parseInt(locationsRes.rows[0].count)
        };
    } catch (e) {
        server.log.error(e);
        reply.code(500);
        return { status: 'error', message: 'Could not fetch stats' };
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
