-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- RESET FOR V2.1 (MVP Development)
-- Users table (device-based accounts)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    api_key TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    retention_days INTEGER DEFAULT 30 CHECK (retention_days >= -1 AND retention_days != 0),
    privacy_settings JSONB DEFAULT '{
        "precision_level": "medium",
        "history_access_days": 7,
        "enabled": true
    }'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_users_api_key ON users(api_key);

-- Locations table (time-series optimized)
CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    point GEOGRAPHY(POINT, 4326) NOT NULL,
    accuracy FLOAT NOT NULL CHECK (accuracy > 0),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_locations_user_time ON locations(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_locations_timestamp ON locations(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_locations_geog ON locations USING GIST(point);

-- Assistant connections (MCP tokens)
CREATE TABLE IF NOT EXISTS assistant_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_type TEXT NOT NULL CHECK (assistant_type IN ('claude')),
    mcp_token TEXT UNIQUE NOT NULL,
    token_name TEXT,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE NULL,
    last_used_at TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_assistant_tokens ON assistant_connections(mcp_token) 
    WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_assistant_user ON assistant_connections(user_id, assistant_type);

-- Access logs (transparency)
CREATE TABLE IF NOT EXISTS access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_type TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    location_count INTEGER DEFAULT 0,
    query_params JSONB,
    response_time_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_access_logs_user_time ON access_logs(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_access_logs_timestamp ON access_logs(timestamp DESC);
