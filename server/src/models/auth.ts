import { query } from '../db';
import { generateMCPToken, hashMCPToken, mcpTokenPreview } from '../utils/crypto';

export const createMCPToken = async (userId: string, assistantType: string, tokenName?: string) => {
    const token = generateMCPToken();
    const tokenHash = hashMCPToken(token);
    const preview = mcpTokenPreview(token);
    const expiresAt = new Date();
    expiresAt.setFullYear(expiresAt.getFullYear() + 1); // 1 year expiry

    // Store only the hash and a display preview. The plaintext token is returned
    // to the caller once and never persisted.
    await query(
        `INSERT INTO assistant_connections (user_id, assistant_type, mcp_token, token_preview, token_name, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, assistantType, tokenHash, preview, tokenName || 'Default', expiresAt]
    );

    return { token, expiresAt };
};

export const validateMCPToken = async (token: string): Promise<{ userId: string; assistantType: string } | null> => {
    const tokenHash = hashMCPToken(token);
    const res = await query(
        `SELECT user_id, id, assistant_type FROM assistant_connections
         WHERE mcp_token = $1
           AND revoked_at IS NULL
           AND expires_at > NOW()`,
        [tokenHash]
    );

    if (res.rows.length > 0) {
        // Async update last_used (best-effort)
        query(`UPDATE assistant_connections SET last_used_at = NOW() WHERE mcp_token = $1`, [tokenHash]).catch(() => { });
        return {
            userId: res.rows[0].user_id,
            assistantType: res.rows[0].assistant_type
        };
    }

    return null;
};

export const listMCPTokens = async (userId: string) => {
    const res = await query(
        `SELECT id, assistant_type, token_name, token_preview, connected_at, last_used_at, expires_at
         FROM assistant_connections
         WHERE user_id = $1 AND revoked_at IS NULL
         ORDER BY connected_at DESC`,
        [userId]
    );
    return res.rows.map(row => ({
        ...row,
        token_preview: row.token_preview || null
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
