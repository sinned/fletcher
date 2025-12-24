import db, { query } from '../db';

export interface LocationPoint {
    latitude: number;
    longitude: number;
    accuracy: number;
    timestamp: Date;
}

export const saveLocations = async (userId: string, locations: LocationPoint[]) => {
    if (locations.length === 0) return;

    const client = await db.pool.connect();
    try {
        await client.query('BEGIN');

        // Build VALUES clause for batch insert
        const values: any[] = [];
        const valueStrings: string[] = [];

        locations.forEach((loc, idx) => {
            const base = idx * 5;
            valueStrings.push(
                `($${base + 1}, ST_SetSRID(ST_MakePoint($${base + 2}, $${base + 3}), 4326), $${base + 4}, $${base + 5})`
            );
            values.push(userId, loc.longitude, loc.latitude, loc.accuracy, loc.timestamp);
        });

        const query = `
            INSERT INTO locations (user_id, point, accuracy, timestamp)
            VALUES ${valueStrings.join(', ')}
        `;

        await client.query(query, values);
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

export const getLocationHistory = async (userId: string, options: { start?: Date, end?: Date, limit?: number, offset?: number } = {}) => {
    const { start, end, limit = 100, offset = 0 } = options;

    let queryStr = `SELECT 
       ST_Y(point::geometry) as latitude, 
       ST_X(point::geometry) as longitude, 
       accuracy, 
       timestamp 
     FROM locations 
     WHERE user_id = $1`;

    const params: any[] = [userId];
    let paramIdx = 2;

    if (start) {
        queryStr += ` AND timestamp >= $${paramIdx++}`;
        params.push(start);
    }
    if (end) {
        queryStr += ` AND timestamp <= $${paramIdx++}`;
        params.push(end);
    }

    queryStr += ` ORDER BY timestamp ASC LIMIT $${paramIdx++} OFFSET $${paramIdx++}`;
    params.push(limit, offset);

    const res = await query(queryStr, params);
    return res.rows;
};

export const getTotalLocationCount = async (userId: string, options: { start?: Date, end?: Date } = {}) => {
    const { start, end } = options;
    let queryStr = `SELECT COUNT(*) as count FROM locations WHERE user_id = $1`;
    const params: any[] = [userId];
    let paramIdx = 2;

    if (start) {
        queryStr += ` AND timestamp >= $${paramIdx++}`;
        params.push(start);
    }
    if (end) {
        queryStr += ` AND timestamp <= $${paramIdx++}`;
        params.push(end);
    }

    const res = await query(queryStr, params);
    return parseInt(res.rows[0].count, 10);
};

export const getLocationHistoryWithRadius = async (userId: string, centerLat: number, centerLon: number, radiusMeters: number, options: { start?: Date, end?: Date, limit?: number, offset?: number } = {}) => {
    const { start, end, limit = 100, offset = 0 } = options;

    let queryStr = `SELECT 
       ST_Y(point::geometry) as latitude, 
       ST_X(point::geometry) as longitude, 
       accuracy, 
       timestamp 
     FROM locations 
     WHERE user_id = $1
     AND ST_DWithin(point::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)`;

    const params: any[] = [userId, centerLon, centerLat, radiusMeters];
    let paramIdx = 5;

    if (start) {
        queryStr += ` AND timestamp >= $${paramIdx++}`;
        params.push(start);
    }
    if (end) {
        queryStr += ` AND timestamp <= $${paramIdx++}`;
        params.push(end);
    }

    queryStr += ` ORDER BY timestamp ASC LIMIT $${paramIdx++} OFFSET $${paramIdx++}`;
    params.push(limit, offset);

    const res = await query(queryStr, params);
    return res.rows;
};

export const getRecentTrajectory = async (userId: string, limit: number = 10, offset: number = 0) => {
    // Returns points in chronological order, taking the most recent N
    const res = await query(
        `SELECT * FROM (
            SELECT 
                ST_Y(point::geometry) as latitude, 
                ST_X(point::geometry) as longitude, 
                accuracy, 
                timestamp 
            FROM locations 
            WHERE user_id = $1 
            ORDER BY timestamp DESC 
            LIMIT $2 OFFSET $3
        ) sub ORDER BY timestamp ASC`,
        [userId, limit, offset]
    );
    return res.rows;
};

export const getFrequentLocations = async (userId: string, limit: number = 5, lookbackDays: number = 30) => {
    // Cluster locations using DBSCAN or grid snapping. 
    // Using ST_SnapToGrid for simple clustering (approx 0.001 deg ~ 111m) 
    // This is a heuristic for 'places visited'.
    const lookbackDate = new Date();
    lookbackDate.setDate(lookbackDate.getDate() - lookbackDays);

    const res = await query(
        `WITH clusters AS (
            SELECT 
                ST_SnapToGrid(point::geometry, 0.001) as cluster_point,
                COUNT(*) as visit_count,
                MIN(timestamp) as first_seen,
                MAX(timestamp) as last_seen,
                MAX(timestamp) - MIN(timestamp) as time_span_interval
            FROM locations
            WHERE user_id = $1 AND timestamp >= $2
            GROUP BY cluster_point
        )
        SELECT 
            ST_Y(cluster_point) as latitude,
            ST_X(cluster_point) as longitude,
            visit_count,
            first_seen,
            last_seen,
            time_span_interval as total_time_spent
        FROM clusters
        ORDER BY visit_count DESC
        LIMIT $3`,
        [userId, lookbackDate, limit]
    );
    return res.rows;
};

export const getRecentLocations = async (userId: string, limit: number) => {
    const res = await query(
        `SELECT 
       ST_Y(point::geometry) as latitude, 
       ST_X(point::geometry) as longitude, 
       accuracy, 
       timestamp 
     FROM locations 
     WHERE user_id = $1 
     ORDER BY timestamp DESC 
     LIMIT $2`,
        [userId, limit]
    );
    return res.rows.reverse(); // Return in chronological order (oldest to newest) for history context
};

export const deleteLocation = async (id: string, userId: string) => {
    const res = await query(
        'DELETE FROM locations WHERE id = $1 AND user_id = $2 RETURNING id',
        [id, userId]
    );
    return res.rowCount && res.rowCount > 0;
};

export const deleteAllLocations = async (userId: string) => {
    const res = await query(
        'DELETE FROM locations WHERE user_id = $1',
        [userId]
    );
    return res.rowCount || 0;
};
