import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getAccessLogs, getAccessLogsCount } from '../models/access_log';

export default async function accessLogsRoutes(fastify: FastifyInstance) {
    // Auth middleware - same pattern as mcp_api.ts
    fastify.addHook('onRequest', async (request, reply) => {
        const authHeader = request.headers['authorization'];
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Missing API Key' } });
        }

        const { validateAPIKey } = await import('../models/user');
        const apiKey = authHeader.replace('Bearer ', '');
        const userId = await validateAPIKey(apiKey);

        if (!userId) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Invalid API Key' } });
        }

        (request as any).userId = userId;
    });

    // GET /api/access-logs - Retrieve access logs
    fastify.get('/', async (request, reply) => {
        const QuerySchema = z.object({
            limit: z.coerce.number().optional().default(50),
            offset: z.coerce.number().optional().default(0),
            assistant_type: z.string().optional(),
            start_date: z.string().optional(),
            end_date: z.string().optional()
        });

        try {
            const { limit, offset, assistant_type, start_date, end_date } = QuerySchema.parse(request.query);
            const userId = (request as any).userId;

            const options: any = {
                limit,
                offset,
                assistantType: assistant_type
            };

            if (start_date) {
                options.startDate = new Date(start_date);
            }
            if (end_date) {
                options.endDate = new Date(end_date);
            }

            const [logs, totalCount] = await Promise.all([
                getAccessLogs(userId, options),
                getAccessLogsCount(userId, {
                    assistantType: assistant_type,
                    startDate: options.startDate,
                    endDate: options.endDate
                })
            ]);

            return {
                logs,
                metadata: {
                    total_count: totalCount,
                    returned_count: logs.length,
                    has_more: totalCount > offset + logs.length,
                    limit,
                    offset
                }
            };
        } catch (err) {
            fastify.log.error(err);
            return reply.code(400).send({ error: 'Invalid request parameters' });
        }
    });
}
