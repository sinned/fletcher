import { query } from '../db';
import { generateAPIKey, hashAPIKey } from '../utils/crypto';

export interface User {
    id: string;
    api_key: string;
    created_at: Date;
    retention_days: number;
    privacy_settings: {
        precision_level: 'high' | 'medium' | 'low';
        history_access_days: number;
        enabled: boolean;
    };
}

export const createUser = async (userId: string): Promise<User> => {
    // Generate new key
    const rawApiKey = generateAPIKey();
    const hashedKey = hashAPIKey(rawApiKey);

    const res = await query(
        `INSERT INTO users (id, api_key, created_at)
         VALUES ($1, $2, NOW())
         RETURNING id, created_at, retention_days, privacy_settings`,
        [userId, hashedKey]
    );

    // Return the raw key ONLY once here so it can be sent to client
    const user = res.rows[0];
    return {
        ...user,
        api_key: rawApiKey
    };
};

export const validateAPIKey = async (apiKey: string): Promise<string | null> => {
    const hashedKey = hashAPIKey(apiKey);
    const res = await query(
        `SELECT id FROM users WHERE api_key = $1`,
        [hashedKey]
    );
    if (res.rows.length > 0) {
        return res.rows[0].id;
    }
    return null;
};

export const ensureUser = async (userId: string) => {
    // For migration compatibility or testing - ideally we use register
    // But if we need 'ensure' logic without replacing key:
    const res = await query('SELECT id FROM users WHERE id = $1', [userId]);
    if (res.rows.length === 0) {
        // If user doesn't exist, we must create them properly via createUser
        // But createUser returns the key.
        // This function is often used for internal checks. 
        // For TDD v2, implicit creation is discouraged.
        // We'll throw if not found? Or create with dummy key? 
        // Let's assume explicit registration is required now.
        throw new Error('User not found. Must register first.');
    }
};

export const getPrivacySettings = async (userId: string) => {
    const res = await query(
        `SELECT privacy_settings, retention_days FROM users WHERE id = $1`,
        [userId]
    );
    const row = res.rows[0];
    if (!row) return null;
    return {
        ...row.privacy_settings,
        retention_days: row.retention_days
    };
};

export const updatePrivacySettings = async (userId: string, settings: any) => {
    const { retention_days, ...privacyUpdates } = settings;

    // We use COALESCE to keep existing value if retention_days is undefined (passed as null/undefined)
    // But since it's optional in schema, it might be undefined in 'settings' object.

    // Construct dynamic query or just use COALESCE with explicit parameter
    // If retention_days is undefined, we pass null and use COALESCE(null, col) = col? No, COALESCE($2, col) works if $2 is null.

    const res = await query(
        `UPDATE users 
         SET 
            retention_days = COALESCE($2, retention_days),
            privacy_settings = privacy_settings || $3::jsonb 
         WHERE id = $1 
         RETURNING privacy_settings, retention_days`,
        [userId, retention_days ?? null, JSON.stringify(privacyUpdates)]
    );
    const row = res.rows[0];
    return {
        ...row.privacy_settings,
        retention_days: row.retention_days
    };
};
