
import { query } from './src/db';

async function migrate() {
    try {
        console.log('Dropping old constraint...');
        await query(`ALTER TABLE assistant_connections DROP CONSTRAINT IF EXISTS assistant_connections_assistant_type_check`);

        console.log('Adding new constraint...');
        await query(`ALTER TABLE assistant_connections ADD CONSTRAINT assistant_connections_assistant_type_check CHECK (assistant_type IN ('claude', 'chatgpt', 'cursor', 'other'))`);

        console.log('Migration successful.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

migrate();
