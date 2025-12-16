import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { saveLocations, LocationPoint } from '../models/location';

export default async function locationRoutes(fastify: FastifyInstance) {
    fastify.post('/locations', async (request, reply) => {
        const LocationSchema = z.object({
            latitude: z.number(),
            longitude: z.number(),
            accuracy: z.number(),
            timestamp: z.string().or(z.date()).transform(val => new Date(val))
        });

        const BodySchema = z.object({
            locations: z.array(LocationSchema)
        });

        try {
            // Get user ID from header
            const userId = request.headers['x-user-id'] as string;
            if (!userId) { // Simple check, real app would validate UUID format
                return reply.code(400).send({ error: 'Missing X-User-Id header' });
            }

            // Ensure user exists (for FK constraint)
            const { ensureUser } = await import('../models/user');
            await ensureUser(userId);

            const { locations } = BodySchema.parse(request.body);

            await saveLocations(userId, locations);

            return { status: 'ok', count: locations.length };
        } catch (err) {
            fastify.log.error(err);
            reply.code(400).send({ error: 'Invalid data' });
        }
    });

    // Delete location
    fastify.delete('/locations/:id', async (request, reply) => {
        const userId = request.headers['x-user-id'] as string;
        if (!userId) {
            return reply.code(400).send({ error: 'Missing X-User-Id header' });
        }

        const { id } = request.params as { id: string };
        const { deleteLocation } = await import('../models/location');

        try {
            const deleted = await deleteLocation(id, userId);
            if (deleted) {
                return { status: 'ok', id };
            } else {
                return reply.code(404).send({ error: 'Location not found or access denied' });
            }
        } catch (err) {
            fastify.log.error(err);
            reply.code(500).send({ error: 'Internal server error' });
        }
    });
}
