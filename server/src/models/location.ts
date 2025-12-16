import { query } from '../db';

export interface LocationPoint {
    latitude: number;
    longitude: number;
    accuracy: number;
    timestamp: Date;
}

export const saveLocations = async (userId: string, locations: LocationPoint[]) => {
    // Simple batch insert
    // in production, use a transaction or UNNEST
    const client = await import('../db').then(m => m.default.pool.connect());
    try {
        await client.query('BEGIN');
        for (const loc of locations) {
            await client.query(
                `INSERT INTO locations (user_id, point, accuracy, timestamp)
         VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326), $4, $5)`,
                [userId, loc.longitude, loc.latitude, loc.accuracy, loc.timestamp]
            );
        }
        await client.query('COMMIT');
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
};

export const getLatestLocation = async (userId: string) => {
    const res = await query(
        `SELECT 
       ST_Y(point::geometry) as latitude, 
       ST_X(point::geometry) as longitude, 
       accuracy, 
       timestamp 
     FROM locations 
     WHERE user_id = $1 
     ORDER BY timestamp DESC 
     LIMIT 1`,
        [userId]
    );
    return res.rows[0];
};

export const getLocationHistory = async (userId: string, start: Date, end: Date) => {
    const res = await query(
        `SELECT 
       ST_Y(point::geometry) as latitude, 
       ST_X(point::geometry) as longitude, 
       accuracy, 
       timestamp 
     FROM locations 
     WHERE user_id = $1 
       AND timestamp >= $2 
       AND timestamp <= $3
     ORDER BY timestamp ASC`,
        [userId, start, end]
    );
    return res.rows;
};

export const deleteLocation = async (id: string, userId: string) => {
    const res = await query(
        'DELETE FROM locations WHERE id = $1 AND user_id = $2 RETURNING id',
        [id, userId]
    );
    return res.rowCount && res.rowCount > 0;
};
