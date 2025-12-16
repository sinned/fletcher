import fastify from 'fastify';
import dotenv from 'dotenv';
import { z } from 'zod';
import { initDb } from './db';

dotenv.config();

const server = fastify({
    logger: true,
});

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

import mobileRoutes from './routes/mobile';
import mcpApiRoutes from './routes/mcp_api';
import { setupMcp } from './mcp';

// ... imports

server.register(mobileRoutes, { prefix: '/api' });
server.register(mcpApiRoutes, { prefix: '/api/mcp' }); // Mounted at /api/mcp
server.register(require('@fastify/formbody'));
setupMcp(server);

// Health check
server.get('/health', async (request, reply) => {
    return { status: 'ok' };
});

const start = async () => {
    try {
        try {
            await initDb();
        } catch (e) {
            server.log.warn('Database initialization failed, proceeding without DB connection: ' + e);
        }
        await server.listen({ port: PORT, host: '0.0.0.0' });
        console.log(`Server listening on ${PORT}`);
    } catch (err) {
        server.log.error(err);
        process.exit(1);
    }
};

start();
