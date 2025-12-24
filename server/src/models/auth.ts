import { query } from '../db';
import { generateMCPToken } from '../utils/crypto';

export const createMCPToken = async (userId: string, assistantType: string, tokenName?: string) => {
    const token = generateMCPToken();
    const expiresAt = new Date();
    expiresAt.setFullYear(expiresAt.getFullYear() + 1); // 1 year expiry

    // We allow multiple tokens per user/assistant now? TDD v2.1 says "User can have multiple tokens".
    // Schema says PK is UUID, UNIQUE constraint on mcp_token only.
    // Previous schema had UNIQUE(user_id, assistant_type). v2.1 TDD removed that uniqueness constraint in text ("List all MCP tokens").

    // Note: Schema in TDD has `id UUID PK`. My previous unique constraint might block multiple tokens.
    // Let's check schema.sql I just wrote. It has `UNIQUE(user_id, assistant_type)`? 
    // Wait, in my previous schema write I kept `id` but I didn't see the unique constraint in the TDD block.
    // Let's assume multiple tokens are allowed.

    // Actually, looking at my schema.sql write just now:
    // `CREATE INDEX ... idx_assistant_user ON assistant_connections(user_id, assistant_type);`
    // I did NOT put a UNIQUE constraint on (user_id, assistant_type) in schema.sql. Good.

    await query(
        `INSERT INTO assistant_connections (user_id, assistant_type, mcp_token, token_name, expires_at)
         VALUES ($1, $2, $3, $4, $5)`,
        [userId, assistantType, token, tokenName || 'Default', expiresAt]
    );

    return { token, expiresAt };
};

export const validateMCPToken = async (token: string): Promise<{ userId: string; assistantType: string } | null> => {
    const res = await query(
        `SELECT user_id, id, assistant_type FROM assistant_connections 
         WHERE mcp_token = $1 
           AND revoked_at IS NULL 
           AND expires_at > NOW()`,
        [token]
    );

    if (res.rows.length > 0) {
        // Async update last_used
        query(`UPDATE assistant_connections SET last_used_at = NOW() WHERE mcp_token = $1`, [token]).catch(console.error);
        return {
            userId: res.rows[0].user_id,
            assistantType: res.rows[0].assistant_type
        };
    }

    // Debugging why it failed
    const debugRes = await query(`SELECT id, expires_at, revoked_at FROM assistant_connections WHERE mcp_token = $1`, [token]);
    if (debugRes.rows.length > 0) {
        const row = debugRes.rows[0];
        console.log(`[Auth] Token found but invalid: ID=${row.id}, Exp=${row.expires_at}, Revoked=${row.revoked_at}, Now=${new Date()}`);
    } else {
        console.log(`[Auth] Token not found: ${token.substring(0, 10)}...`);
    }

    return null;
};

export const listMCPTokens = async (userId: string) => {
    const res = await query(
        `SELECT id, assistant_type, token_name, connected_at, last_used_at, expires_at, mcp_token 
         FROM assistant_connections 
         WHERE user_id = $1 AND revoked_at IS NULL
         ORDER BY connected_at DESC`,
        [userId]
    );
    return res.rows.map(row => ({
        ...row,
        token_preview: row.mcp_token.substring(0, 8) + '...' + row.mcp_token.slice(-4),
        mcp_token: undefined // Don't return full token
    }));
};

export const revokeMCPToken = async (userId: string, tokenId: string) => {
    const res = await query(
        `UPDATE assistant_connections 
         SET revoked_at = NOW() 
         WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL`,
        [tokenId, userId]
    );
    return (res.rowCount || 0) > 0;
};
