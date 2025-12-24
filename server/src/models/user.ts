import { query } from '../db';
import { generateAPIKey, hashAPIKey } from '../utils/crypto';

export interface PgError {
    code: string;
    detail?: string;
    table?: string;
}

export function isPgError(error: unknown): error is PgError {
    return typeof error === 'object' &&
        error !== null &&
        'code' in error;
}

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

    // Get current settings to validate against
    const current = await getPrivacySettings(userId);
    if (!current) throw new Error('User not found');

    // Validate: history_access can't exceed retention
    const newRetention = retention_days ?? current.retention_days;
    const newHistoryDays = privacyUpdates.history_access_days ?? current.history_access_days;

    if (newRetention > 0 && newHistoryDays > newRetention) {
        throw new Error('history_access_days cannot exceed retention_days');
    }

    // Validate: retention_days constraints
    if (retention_days !== undefined) {
        if (retention_days === 0) {
            throw new Error('retention_days cannot be 0 (use -1 for unlimited)');
        }
        if (retention_days < -1) {
            throw new Error('retention_days must be -1 or positive');
        }
    }

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
