import { FastifyInstance } from 'fastify';

export default async function authRoutes(fastify: FastifyInstance) {
    // OAuth2 Authorize Endpoint
    // Client (Claude) redirects user here
    fastify.get('/oauth/authorize', async (request, reply) => {
        // In a real app, this would show a login screen or redirect to app
        // For MVP, we render a simple page to "approve"
        const { client_id, redirect_uri, state } = request.query as any;

        // Simple HTML response
        reply.type('text/html').send(`
      <html>
        <body>
          <h1>Connect Fletcher</h1>
          <p>Authorize Claude to access your location?</p>
          <form action="/auth/oauth/approve" method="post">
            <input type="hidden" name="redirect_uri" value="${redirect_uri}" />
            <input type="hidden" name="state" value="${state}" />
            <button type="submit">Approve</button>
          </form>
        </body>
      </html>
    `);
    });

    // Handle approval
    fastify.post('/oauth/approve', async (request, reply) => {
        const { redirect_uri, state } = request.body as any;
        const code = 'mock_auth_code_' + Date.now();

        // Redirect back to client
        const target = new URL(redirect_uri);
        target.searchParams.set('code', code);
        if (state) target.searchParams.set('state', state);

        reply.redirect(target.toString());
    });

    // OAuth2 Token Endpoint
    // Client exchanges code for token
    fastify.post('/oauth/token', async (request, reply) => {
        const { code, client_id, client_secret } = request.body as any;

        // Return mock token
        return {
            access_token: 'mock_access_token_' + Date.now(),
            token_type: 'Bearer',
            expires_in: 3600
        };
    });
}
