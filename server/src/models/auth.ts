import { query } from '../db';
import { generateMCPToken, generateAuthCode } from '../utils/crypto';

export const createAuthCode = async (userId: string, clientId: string, redirectUri: string) => {
    const code = generateAuthCode();
    await query(
        `INSERT INTO oauth_codes (code, user_id, client_id, redirect_uri)
         VALUES ($1, $2, $3, $4)`,
        [code, userId, clientId, redirectUri]
    );
    return code;
};

export const validateAuthCode = async (code: string, clientId: string) => {
    const res = await query(
        `UPDATE oauth_codes 
         SET used_at = NOW() 
         WHERE code = $1 AND client_id = $2 AND used_at IS NULL
           AND created_at > NOW() - INTERVAL '10 minutes'
         RETURNING user_id`,
        [code, clientId]
    );
    if (res.rows.length > 0) {
        return res.rows[0].user_id;
    }
    return null;
};

export const createMCPToken = async (userId: string, assistantType: string) => {
    const token = generateMCPToken();
    const expiresAt = new Date();
    expiresAt.setFullYear(expiresAt.getFullYear() + 1); // 1 year expiry

    await query(
        `INSERT INTO assistant_connections (user_id, assistant_type, oauth_token, expires_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (user_id, assistant_type) 
         DO UPDATE SET oauth_token = $3, expires_at = $4, revoked_at = NULL, connected_at = NOW()`,
        [userId, assistantType, token, expiresAt]
    );

    return { token, expiresAt };
};

export const validateMCPToken = async (token: string) => {
    const res = await query(
        `SELECT user_id FROM assistant_connections 
         WHERE oauth_token = $1 
           AND revoked_at IS NULL 
           AND expires_at > NOW()`,
        [token]
    );

    if (res.rows.length > 0) {
        // Async update last_used
        query(`UPDATE assistant_connections SET last_used_at = NOW() WHERE oauth_token = $1`, [token]).catch(console.error);
        return res.rows[0].user_id;
    }
    return null;
};
