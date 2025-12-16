import { FastifyInstance } from 'fastify';
import { createAuthCode, validateAuthCode, createMCPToken } from '../models/auth';
import { ensureUser } from '../models/user';

export default async function authRoutes(fastify: FastifyInstance) {
  // OAuth2 Authorize Endpoint
  fastify.get('/oauth/authorize', async (request, reply) => {
    const { client_id, redirect_uri, state, user_id } = request.query as any;

    // In a real flow, checking user_id like this is insecure (phishing risk).
    // But for MVP device-based auth, we accept it contextually.
    // We'll trust the user_id exists if the client sends it.
    // Or we should redirect to a "Connect" page where user enters a code from the app?
    // TDD v2 says: GET /auth/oauth/authorize ... Auto-Approve for MVP.

    // Actually, GET request shouldn't enforce user_id presence if we plan to show UI.
    // But since we are Auto-Approving, we need the context immediately.

    // If user_id missing, we can't link.
    if (!user_id && !request.body) {
      return reply.type('text/html').send(`Error: Missing user_id context. Please start flow from Fletcher App.`);
    }

    // Validate Client ID (Mock for now)
    if (client_id !== 'claude') {
      return reply.code(400).send('Invalid Client ID');
    }

    // Auto-approve flow
    try {
      // Ensure user exists (optional check, but good for data integrity)
      try {
        await ensureUser(user_id);
      } catch (e) {
        return reply.code(400).send('User not found. Please register in app first.');
      }

      const code = await createAuthCode(user_id, client_id, redirect_uri);

      const target = new URL(redirect_uri);
      target.searchParams.set('code', code);
      if (state) target.searchParams.set('state', state);

      return reply.redirect(target.toString());
    } catch (err) {
      fastify.log.error(err);
      return reply.code(500).send('Internal Server Error');
    }
  });

  // OAuth2 Token Endpoint
  fastify.post('/oauth/token', async (request, reply) => {
    const { code, client_id, client_secret, grant_type } = request.body as any;

    if (grant_type !== 'authorization_code') {
      return reply.code(400).send({ error: 'unsupported_grant_type' });
    }

    try {
      const userId = await validateAuthCode(code, client_id);
      if (!userId) {
        return reply.code(400).send({ error: 'invalid_grant' });
      }

      const { token, expiresAt } = await createMCPToken(userId, 'claude');

      return {
        access_token: token,
        token_type: 'Bearer',
        expires_in: Math.floor((expiresAt.getTime() - Date.now()) / 1000),
        scope: 'location:read'
      };
    } catch (err) {
      fastify.log.error(err);
      return reply.code(500).send({ error: 'server_error' });
    }
  });
}
