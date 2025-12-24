
import { query } from './src/db';

async function debugToken(token: string) {
    try {
        console.log(`Inspecting token: ${token}`);

        // 1. Find the token
        const res = await query(`
            SELECT t.*, u.api_key 
            FROM assistant_connections t
            JOIN users u ON t.user_id = u.id
            WHERE t.mcp_token = $1
        `, [token]);

        if (res.rows.length === 0) {
            console.log('Token NOT found in database.');
        } else {
            const row = res.rows[0];
            console.log('Token FOUND:');
            console.log(`- User ID: ${row.user_id}`);
            console.log(`- API Key (first 10 chars): ${row.api_key.substring(0, 10)}...`);
            console.log(`- Assistant Type: ${row.assistant_type}`);
            console.log(`- Token Name: ${row.token_name}`);
            console.log(`- Revoked At: ${row.revoked_at}`);
            console.log(`- Expires At: ${row.expires_at}`);
        }

        process.exit(0);
    } catch (err) {
        console.error('Debug failed:', err);
        process.exit(1);
    }
}

// Extract token from arg or use default from user prompt
const token = process.argv[2] || 'mcp_UJNsbWSAEMmDBFNlWR6LnFgjUpGeZxVmK5Hf1G1paIY';
debugToken(token);
