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

        // ON CONFLICT DO NOTHING makes re-sync idempotent: re-uploading the same
        // points (matched by the unique index on user_id, timestamp) is a no-op
        // rather than creating duplicates.
        const query = `
            INSERT INTO locations (user_id, point, accuracy, timestamp)
            VALUES ${valueStrings.join(', ')}
            ON CONFLICT (user_id, timestamp) DO NOTHING
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

// The single recorded point closest in time to `target` (optionally bounded to
// a window). Powers "where was I at 3pm last Tuesday?"
export const getLocationAtTime = async (userId: string, target: Date, options: { start?: Date } = {}) => {
    const params: any[] = [userId, target];
    let where = `user_id = $1`;
    let idx = 3;
    if (options.start) { where += ` AND timestamp >= $${idx++}`; params.push(options.start); }
    const res = await query(
        `SELECT
            ST_Y(point::geometry) as latitude,
            ST_X(point::geometry) as longitude,
            accuracy,
            timestamp,
            ABS(EXTRACT(EPOCH FROM (timestamp - $2))) as diff_seconds
         FROM locations
         WHERE ${where}
         ORDER BY diff_seconds ASC
         LIMIT 1`,
        params
    );
    return res.rows[0];
};

// Total distance traveled (meters) and point count over a window. Distance is a
// scalar, so no coordinates are exposed. Powers "how far did I go this week?"
export const getDistanceSummary = async (userId: string, options: { start?: Date, end?: Date } = {}) => {
    const { start, end } = options;
    const params: any[] = [userId];
    let where = `user_id = $1`;
    let idx = 2;
    if (start) { where += ` AND timestamp >= $${idx++}`; params.push(start); }
    if (end) { where += ` AND timestamp <= $${idx++}`; params.push(end); }
    const res = await query(
        `WITH ordered AS (
            SELECT point::geometry AS g,
                   LAG(point::geometry) OVER (ORDER BY timestamp) AS prev
            FROM locations WHERE ${where}
         )
         SELECT
            COALESCE(SUM(ST_Distance(g::geography, prev::geography)) FILTER (WHERE prev IS NOT NULL), 0) AS meters,
            COUNT(*) AS points
         FROM ordered`,
        params
    );
    const row = res.rows[0];
    return { meters: parseFloat(row.meters), points: parseInt(row.points, 10) };
};

// How many recorded points fall within `radiusMeters` of a coordinate, and the
// first/last time. The caller supplies the coordinate, so no new location is
// revealed. Powers "how often did I go to the gym?"
export const getPlaceVisits = async (userId: string, centerLat: number, centerLon: number, radiusMeters: number, options: { start?: Date, end?: Date } = {}) => {
    const { start, end } = options;
    const params: any[] = [userId, centerLon, centerLat, radiusMeters];
    let where = `user_id = $1 AND ST_DWithin(point::geography, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)`;
    let idx = 5;
    if (start) { where += ` AND timestamp >= $${idx++}`; params.push(start); }
    if (end) { where += ` AND timestamp <= $${idx++}`; params.push(end); }
    const res = await query(
        `SELECT COUNT(*) as visit_count, MIN(timestamp) as first_seen, MAX(timestamp) as last_seen
         FROM locations WHERE ${where}`,
        params
    );
    const row = res.rows[0];
    return {
        visit_count: parseInt(row.visit_count, 10),
        first_seen: row.first_seen,
        last_seen: row.last_seen
    };
};

// One-shot rollup for a day or period: point count, active window, distance,
// and how many distinct ~100m cells were visited. Powers "summarize my day".
export const getDaySummary = async (userId: string, options: { start: Date, end: Date }) => {
    const res = await query(
        `WITH pts AS (
            SELECT point::geometry AS g, timestamp,
                   LAG(point::geometry) OVER (ORDER BY timestamp) AS prev
            FROM locations
            WHERE user_id = $1 AND timestamp >= $2 AND timestamp <= $3
         )
         SELECT
            COUNT(*) AS points,
            MIN(timestamp) AS first_seen,
            MAX(timestamp) AS last_seen,
            COALESCE(SUM(ST_Distance(g::geography, prev::geography)) FILTER (WHERE prev IS NOT NULL), 0) AS meters,
            COUNT(DISTINCT ST_SnapToGrid(g, 0.001)) AS distinct_places
         FROM pts`,
        [userId, options.start, options.end]
    );
    const r = res.rows[0];
    return {
        points: parseInt(r.points, 10),
        first_seen: r.first_seen,
        last_seen: r.last_seen,
        meters: parseFloat(r.meters),
        distinct_places: parseInt(r.distinct_places, 10)
    };
};

// Infer likely home (dominant nighttime cluster) and work (dominant weekday
// daytime cluster) in the user's timezone. Returns the ~100m grid cell centers.
// Home and work can coincide for remote workers.
export const getSignificantPlaces = async (userId: string, timezone: string, options: { start?: Date } = {}) => {
    const params: any[] = [userId, timezone];
    let timeFilter = '';
    let idx = 3;
    if (options.start) { timeFilter = ` AND timestamp >= $${idx++}`; params.push(options.start); }

    const homeRes = await query(
        `SELECT ST_Y(cell) AS lat, ST_X(cell) AS lon, cnt FROM (
            SELECT ST_SnapToGrid(point::geometry, 0.001) AS cell, COUNT(*) AS cnt
            FROM locations
            WHERE user_id = $1${timeFilter}
              AND (EXTRACT(HOUR FROM timestamp AT TIME ZONE $2) >= 22
                   OR EXTRACT(HOUR FROM timestamp AT TIME ZONE $2) < 6)
            GROUP BY cell ORDER BY cnt DESC LIMIT 1
         ) h`,
        params
    );
    const workRes = await query(
        `SELECT ST_Y(cell) AS lat, ST_X(cell) AS lon, cnt FROM (
            SELECT ST_SnapToGrid(point::geometry, 0.001) AS cell, COUNT(*) AS cnt
            FROM locations
            WHERE user_id = $1${timeFilter}
              AND EXTRACT(DOW FROM timestamp AT TIME ZONE $2) BETWEEN 1 AND 5
              AND EXTRACT(HOUR FROM timestamp AT TIME ZONE $2) BETWEEN 9 AND 17
            GROUP BY cell ORDER BY cnt DESC LIMIT 1
         ) w`,
        params
    );
    const toPlace = (rows: any[]) => rows[0]
        ? { latitude: rows[0].lat, longitude: rows[0].lon, sample_count: parseInt(rows[0].cnt, 10) }
        : null;
    return { home: toPlace(homeRes.rows), work: toPlace(workRes.rows) };
};

// The bounds of what data exists, so an assistant can be honest about what it
// can and can't answer. days_with_data counts distinct calendar dates in the
// user's timezone (deterministic, independent of the DB session timezone).
export const getDataCoverage = async (userId: string, timezone: string = 'UTC') => {
    const res = await query(
        `SELECT
            COUNT(*) AS total_points,
            MIN(timestamp) AS earliest,
            MAX(timestamp) AS latest,
            COUNT(DISTINCT (timestamp AT TIME ZONE $2)::date) AS days_with_data
         FROM locations WHERE user_id = $1`,
        [userId, timezone]
    );
    const r = res.rows[0];
    return {
        total_points: parseInt(r.total_points, 10),
        earliest: r.earliest,
        latest: r.latest,
        days_with_data: parseInt(r.days_with_data, 10)
    };
};
