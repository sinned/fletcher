-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- RESET FOR V2 (MVP Development)
DROP TABLE IF EXISTS access_logs CASCADE;
DROP TABLE IF EXISTS oauth_codes CASCADE;
DROP TABLE IF EXISTS assistant_connections CASCADE;
DROP TABLE IF EXISTS locations CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table (device-based accounts)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    api_key TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    retention_days INTEGER DEFAULT 30 CHECK (retention_days BETWEEN 1 AND 90),
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

-- Assistant connections (OAuth tokens)
CREATE TABLE IF NOT EXISTS assistant_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_type TEXT NOT NULL CHECK (assistant_type IN ('claude')),
    oauth_token TEXT UNIQUE NOT NULL,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE NULL,
    last_used_at TIMESTAMP WITH TIME ZONE NULL,
    UNIQUE(user_id, assistant_type)
);

CREATE INDEX IF NOT EXISTS idx_assistant_tokens ON assistant_connections(oauth_token) 
    WHERE revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_assistant_user ON assistant_connections(user_id);

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

-- OAuth authorization codes (temporary)
CREATE TABLE IF NOT EXISTS oauth_codes (
    code TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_id TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    used_at TIMESTAMP WITH TIME ZONE NULL
);

CREATE INDEX IF NOT EXISTS idx_oauth_codes_created ON oauth_codes(created_at);
