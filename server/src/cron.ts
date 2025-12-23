import { query } from './db';

const CLEANUP_INTERVAL_MS = 1000 * 60 * 60 * 24; // Run once every 24 hours

export const startCleanupJob = () => {
    console.log('Starting retention cleanup job (runs daily)...');

    // Run immediately on start
    runCleanup();

    setInterval(() => {
        runCleanup();
    }, CLEANUP_INTERVAL_MS);
};

const runCleanup = async () => {
    try {
        console.log('Running retention cleanup...');
        const res = await query(`
            DELETE FROM locations l
            USING users u
            WHERE l.user_id = u.id
            AND u.retention_days > 0
            AND l.timestamp < NOW() - (u.retention_days * INTERVAL '1 day')
        `);
        if (res.rowCount && res.rowCount > 0) {
            console.log(`Cleanup complete: Deleted ${res.rowCount} old locations.`);
        } else {
            console.log('Cleanup complete: No old locations found.');
        }
    } catch (err) {
        console.error('Error during retention cleanup:', err);
    }
};
