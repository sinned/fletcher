-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_id TEXT UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    privacy_settings JSONB,
    retention_days INTEGER DEFAULT 30
);

-- Location history (time-series optimized)
CREATE TABLE IF NOT EXISTS locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    point GEOGRAPHY(POINT, 4326),
    accuracy FLOAT,
    timestamp TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_locations_user_time ON locations (user_id, timestamp DESC);

-- AI assistant access
CREATE TABLE IF NOT EXISTS assistant_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    assistant_type TEXT,  -- 'claude', 'poke', etc.
    oauth_token TEXT, -- Encrypted in app logic, but here simple text for MVP schema
    precision_level TEXT,  -- 'high', 'medium', 'low'
    enabled BOOLEAN DEFAULT TRUE,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Access audit log
CREATE TABLE IF NOT EXISTS access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    assistant_type TEXT,
    endpoint TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    location_count INTEGER,
    precision_shared TEXT
);
