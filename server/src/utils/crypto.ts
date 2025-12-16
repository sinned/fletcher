import crypto from 'crypto';

export function generateAPIKey(): string {
    const randomBytes = crypto.randomBytes(32);
    // base64url is safe for URLs and headers
    const key = randomBytes.toString('base64url');
    return `fletch_sk_${key}`;
}

// In a real production app, we should hash this key before storing.
// For MVP, TDD suggests hashing, but we also want to return it once.
// We'll trust the plan: return plaintext once, store hash.
export function hashAPIKey(apiKey: string): string {
    return crypto
        .createHash('sha256')
        .update(apiKey)
        .digest('hex');
}

export function generateMCPToken(): string {
    const randomBytes = crypto.randomBytes(32);
    const token = randomBytes.toString('base64url');
    return `mcp_${token}`;
}

export function generateAuthCode(): string {
    const randomBytes = crypto.randomBytes(16);
    return `auth_${randomBytes.toString('base64url')}`;
}
