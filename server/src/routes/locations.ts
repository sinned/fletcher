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
            const { locations } = BodySchema.parse(request.body);

            // In MVP, userId is hardcoded or from header
            const userId = '00000000-0000-0000-0000-000000000000';

            await saveLocations(userId, locations);

            return { status: 'ok', count: locations.length };
        } catch (err) {
            fastify.log.error(err);
            reply.code(400).send({ error: 'Invalid data' });
        }
    });
}
