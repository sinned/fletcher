import { query } from '../db';

export interface AccessLogEntry {
    id: string;
    user_id: string;
    assistant_type: string;
    endpoint: string;
    timestamp: Date;
    location_count: number;
    query_params?: any;
    response_time_ms?: number;
}

export interface GetAccessLogsOptions {
    limit?: number;
    offset?: number;
    assistantType?: string;
    startDate?: Date;
    endDate?: Date;
}

export const logMCPRequest = async (
    userId: string,
    assistantType: string,
    endpoint: string,
    locationCount: number,
    queryParams?: any,
    responseTimeMs?: number
) => {
    await query(
        `INSERT INTO access_logs (user_id, assistant_type, endpoint, location_count, query_params, response_time_ms)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, assistantType, endpoint, locationCount, queryParams ? JSON.stringify(queryParams) : null, responseTimeMs]
    );
};

export const getAccessLogs = async (userId: string, options: GetAccessLogsOptions = {}): Promise<AccessLogEntry[]> => {
    const {
        limit = 50,
        offset = 0,
        assistantType,
        startDate,
        endDate
    } = options;

    // Build query dynamically based on filters
    let queryText = `
        SELECT id, user_id, assistant_type, endpoint, timestamp, location_count, query_params, response_time_ms
        FROM access_logs
        WHERE user_id = $1
    `;
    const queryParams: any[] = [userId];
    let paramIndex = 2;

    if (assistantType) {
        queryText += ` AND assistant_type = $${paramIndex}`;
        queryParams.push(assistantType);
        paramIndex++;
    }

    if (startDate) {
        queryText += ` AND timestamp >= $${paramIndex}`;
        queryParams.push(startDate);
        paramIndex++;
    }

    if (endDate) {
        queryText += ` AND timestamp <= $${paramIndex}`;
        queryParams.push(endDate);
        paramIndex++;
    }

    queryText += ` ORDER BY timestamp DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    queryParams.push(Math.min(limit, 500), offset);

    const res = await query(queryText, queryParams);

    return res.rows.map(row => ({
        id: row.id,
        user_id: row.user_id,
        assistant_type: row.assistant_type,
        endpoint: row.endpoint,
        timestamp: row.timestamp,
        location_count: row.location_count,
        query_params: row.query_params,
        response_time_ms: row.response_time_ms
    }));
};

export const getAccessLogsCount = async (userId: string, options: Omit<GetAccessLogsOptions, 'limit' | 'offset'> = {}): Promise<number> => {
    const {
        assistantType,
        startDate,
        endDate
    } = options;

    let queryText = 'SELECT COUNT(*) as count FROM access_logs WHERE user_id = $1';
    const queryParams: any[] = [userId];
    let paramIndex = 2;

    if (assistantType) {
        queryText += ` AND assistant_type = $${paramIndex}`;
        queryParams.push(assistantType);
        paramIndex++;
    }

    if (startDate) {
        queryText += ` AND timestamp >= $${paramIndex}`;
        queryParams.push(startDate);
        paramIndex++;
    }

    if (endDate) {
        queryText += ` AND timestamp <= $${paramIndex}`;
        queryParams.push(endDate);
        paramIndex++;
    }

    const res = await query(queryText, queryParams);
    return parseInt(res.rows[0].count);
};
