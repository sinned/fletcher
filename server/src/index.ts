import fastify from 'fastify';
import dotenv from 'dotenv';
import { z } from 'zod';
import { initDb, query } from './db';
import { startCleanupJob } from './cron';
import { readFileSync } from 'fs';
import { join } from 'path';


dotenv.config();

const server = fastify({
    logger: true,
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
        await query('SELECT 1');
        return { status: 'ok', db: 'connected', version: SERVER_VERSION };
    } catch (e) {
        server.log.error(e);
        reply.code(500);
        return { status: 'error', db: 'disconnected', version: SERVER_VERSION };
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
