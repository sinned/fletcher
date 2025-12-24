
import { query } from './src/db';

async function migrate() {
    try {
        console.log('Starting migration...');

        // 1. Add token_name if missing
        console.log('Checking for token_name column...');
        await query(`
            ALTER TABLE assistant_connections 
            ADD COLUMN IF NOT EXISTS token_name TEXT;
        `);

        // 2. Fix assistant_type constraint
        console.log('Updating assistant_type constraint...');
        await query(`ALTER TABLE assistant_connections DROP CONSTRAINT IF EXISTS assistant_connections_assistant_type_check`);
        await query(`ALTER TABLE assistant_connections ADD CONSTRAINT assistant_connections_assistant_type_check CHECK (assistant_type IN ('claude', 'chatgpt', 'cursor', 'other'))`);

        console.log('Migration successful.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

migrate();
