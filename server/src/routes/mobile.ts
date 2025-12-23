import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { createUser, validateAPIKey, getPrivacySettings, updatePrivacySettings } from '../models/user';
import { saveLocations, deleteLocation } from '../models/location';

export default async function mobileRoutes(fastify: FastifyInstance) {

    // Auth Middleware for Mobile Routes (except register)
    fastify.addHook('onRequest', async (request, reply) => {
        const url = request.url;
        // Check for register or other exempted paths
        if (url === '/api/register' || url.startsWith('/auth') || url.startsWith('/mcp')) {
            return;
        }

        // Check API Key
        const authHeader = request.headers['authorization'];
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Missing API Key' } });
        }

        const apiKey = authHeader.replace('Bearer ', '');
        const userId = await validateAPIKey(apiKey);

        if (!userId) {
            return reply.code(401).send({ error: { code: 'INVALID_API_KEY', message: 'Invalid API Key' } });
        }

        // Attach user to request
        (request as any).userId = userId;
    });

    // 1. Register Device
    fastify.post('/register', async (request, reply) => {
        const BodySchema = z.object({
            user_id: z.string().uuid()
        });

        try {
            const { user_id } = BodySchema.parse(request.body);
            // Check if exists? schema constraint handles duplicates (or we catch error)

            // Actually TDD says 409 if exists.
            try {
                const user = await createUser(user_id);
                return reply.code(201).send({
                    user_id: user.id,
                    api_key: user.api_key,
                    created_at: user.created_at
                });
            } catch (e: any) {
                if (e.code === '23505') { // Postgres Primary Key violation
                    return reply.code(409).send({ error: { code: 'USER_EXISTS', message: 'User ID already registered' } });
                }
                throw e;
            }
        } catch (err) {
            fastify.log.error(err);
            return reply.code(400).send({ error: 'Invalid Request' });
        }
    });

    // 2. Store Locations
    fastify.post('/locations', async (request, reply) => {
        const LocationSchema = z.object({
            latitude: z.number().min(-90).max(90),
            longitude: z.number().min(-180).max(180),
            accuracy: z.number().positive(),
            timestamp: z.string().or(z.date()).transform(val => new Date(val))
        });

        const BodySchema = z.object({
            locations: z.array(LocationSchema).max(100)
        });

        const userId = (request as any).userId;

        try {
            const { locations } = BodySchema.parse(request.body);
            await saveLocations(userId, locations);

            return {
                status: 'ok',
                count: locations.length,
                inserted_at: new Date()
            };
        } catch (err: any) {
            fastify.log.error(err);
            if (err instanceof z.ZodError) {
                return reply.code(400).send({ error: 'Validation Error', details: err.issues });
            }
            return reply.code(400).send({ error: 'Invalid data', details: err.message });
        }
    });

    // 3. Get Privacy Settings
    fastify.get('/privacy-settings', async (request, reply) => {
        const userId = (request as any).userId;
        const settings = await getPrivacySettings(userId);
        if (!settings) {
            // Should not happen if auth passed
            return reply.code(404).send({ error: 'User not found' });
        }
        // Flatten structure as per API spec
        return {
            ...settings.privacy_settings,
            retention_days: settings.retention_days
        };
    });

    // 4. Update Privacy Settings
    fastify.patch('/privacy-settings', async (request, reply) => {
        const userId = (request as any).userId;
        const BodySchema = z.object({
            precision_level: z.enum(['high', 'medium', 'low']).optional(),
            history_access_days: z.number().min(0).max(30).optional(),
            enabled: z.boolean().optional(),
            retention_days: z.number().min(-1).refine(val => val !== 0, { message: "Cannot be 0" }).optional()
        });

        try {
            const updates = BodySchema.parse(request.body);
            const updated = await updatePrivacySettings(userId, updates);

            return { status: 'ok', updated_at: new Date(), ...updated };
        } catch (e) {
            reply.code(400).send({ error: 'Invalid settings' });
        }
    });

    // 5. Delete Location (Keep from v1)
    fastify.delete('/locations/:id', async (request, reply) => {
        const userId = (request as any).userId;
        const { id } = request.params as { id: string };

        const deleted = await deleteLocation(id, userId);
        if (deleted) {
            return { status: 'ok', id };
        } else {
            return reply.code(404).send({ error: 'Location not found' });
        }
    });
}
