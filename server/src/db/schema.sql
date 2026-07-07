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
    assistant_type TEXT NOT NULL CHECK (assistant_type IN ('claude', 'chatgpt', 'cursor', 'other')),
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

-- Optimizations

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO schema_version (version) VALUES (1) 
ON CONFLICT (version) DO NOTHING;

-- Optimize token cleanup queries
CREATE INDEX IF NOT EXISTS idx_assistant_expires 
    ON assistant_connections(expires_at) 
    WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_assistant_revoked
    ON assistant_connections(revoked_at)
    WHERE revoked_at IS NOT NULL;

-- Migration: hash MCP tokens at rest (v2.1.0)
-- Adds a display-safe preview column and rewrites any still-plaintext tokens to
-- their sha256 hash. Idempotent: once hashed, a value no longer starts with
-- 'mcp_', so redeploys skip it. Non-destructive: users' existing tokens keep
-- working because the server hashes the presented token on lookup.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE assistant_connections ADD COLUMN IF NOT EXISTS token_preview TEXT;

UPDATE assistant_connections
   SET token_preview = COALESCE(token_preview, left(mcp_token, 8) || '...' || right(mcp_token, 4)),
       mcp_token = encode(digest(mcp_token, 'sha256'), 'hex')
 WHERE left(mcp_token, 4) = 'mcp_';
