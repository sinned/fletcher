const { Client } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function setup() {
    console.log('Starting database setup...');

    // 1. Connect to default database (postgres) to create the new one
    // We try to connect with the user from env, but default database.
    // If password is in env, we use it.

    // Parse DATABASE_URL from .env to get credentials
    // Default format: postgres://user:password@localhost:5432/fletcher

    // We will attempt to connect to 'postgres' database first.
    const envUrl = process.env.DATABASE_URL;
    // user:password@host:port/dbname

    const parts = envUrl.replace('postgres://', '').split('/');
    const credsAndHost = parts[0];
    const dbName = parts[1];

    const rootUrl = `postgres://${credsAndHost}/postgres`;

    console.log(`Connecting to temporary DB to check/create '${dbName}'...`);
    const client = new Client({ connectionString: rootUrl });

    try {
        await client.connect();

        // Check if database exists
        const res = await client.query(`SELECT 1 FROM pg_database WHERE datname = $1`, [dbName]);
        if (res.rowCount === 0) {
            console.log(`Creating database '${dbName}'...`);
            await client.query(`CREATE DATABASE "${dbName}"`);
        } else {
            console.log(`Database '${dbName}' already exists.`);
        }
    } catch (err) {
        console.error('Error connecting or creating database:', err);
        // Fallback: maybe user doesn't have 'postgres' db or creds are different?
        // We will proceed to try connecting to the target db directly, maybe it exists.
    } finally {
        await client.end();
    }

    // 2. Connect to the target database and run schema
    console.log(`Connecting to '${dbName}' to run migrations...`);
    const dbClient = new Client({ connectionString: envUrl });

    try {
        await dbClient.connect();

        // Enable PostGIS (schema.sql does this, but good to ensure permissions work here)
        // Read schema.sql
        const schemaPath = path.join(__dirname, '../src/db/schema.sql');
        const schemaSql = fs.readFileSync(schemaPath, 'utf8');

        console.log('Running schema.sql...');
        await dbClient.query(schemaSql);

        console.log('Database setup complete!');
    } catch (err) {
        console.error('Error running migrations:', err);
        process.exit(1);
    } finally {
        await dbClient.end();
    }
}

setup();
