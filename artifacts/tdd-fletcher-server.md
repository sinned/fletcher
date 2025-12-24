# Technical Design Document - Fletcher Server v2.1

**Version:** 2.1 (Implemented)
**Last Updated:** December 2025
**Status:** IMPLEMENTED/LIVE

---

## 1. System Overview

The Fletcher Server is the central backend for the Fletcher ecosystem, responsible for securely storing user location data and exposing it to AI assistants (Claude) via the Model Context Protocol (MCP).

### Tech Stack

- **Runtime:** Node.js 20+ (TypeScript 5.3+)
- **Framework:** Fastify 4.x
- **Database:** PostgreSQL 15+ with PostGIS 3.4+
- **Deployment:** Render (managed platform)
- **Protocol:** HTTP/REST for mobile app, MCP over SSE for AI assistants

### Design Principles

1. **Privacy First:** User data is isolated, access is logged, deletion is immediate
2. **Simple MVP:** Focus on core functionality, defer complexity
3. **Security by Default:** API keys, token validation, rate limiting
4. **Observable:** Comprehensive logging and error tracking

---

## 2. Architecture

### System Components

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│   iOS App   │────────▶│  Fletcher Server │◀────────│   Claude    │
│             │  HTTPS  │                  │   MCP   │             │
│  (Client)   │         │  REST + MCP/SSE  │  (SSE)  │ (AI Agent)  │
└─────────────┘         └──────────────────┘         └─────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │   PostgreSQL    │
                        │   + PostGIS     │
                        └─────────────────┘
```

### Service Architecture

**1. REST API Server**
- Handles mobile app requests (location ingestion, settings, logs)
- Authenticates via API keys (`Bearer fletch_sk_...`)
- Rate limited per user

**2. MCP Server**
- Handles AI assistant connections via Server-Sent Events (SSE)
- Authenticates via `mcp_...` tokens
- Exposes resources (`current_location`, `location_history`) and tools (`get_location_history`) per MCP spec

### Connection Flow

**How Users Connect Claude to Fletcher:**

1.  **Mobile App:** Calls `POST /api/mcp/generate-token` using the device's API Key.
2.  **Server:** Generates a unique MCP token (`mcp_...`) linked to the user.
3.  **User:** Copies the MCP token and SSE URL (`https://.../sse`) to Claude Desktop configuration.
4.  **Claude:** Connects via SSE using `Authorization: Bearer mcp_...` or `?token=mcp_...`.

---

## 3. Data Models

### Database Schema

```sql
-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table (device-based accounts)
CREATE TABLE users (
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

CREATE INDEX idx_users_api_key ON users(api_key);

-- Locations table (time-series optimized)
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    point GEOGRAPHY(POINT, 4326) NOT NULL,
    accuracy FLOAT NOT NULL CHECK (accuracy > 0),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX idx_locations_user_time ON locations(user_id, timestamp DESC);
CREATE INDEX idx_locations_timestamp ON locations(timestamp DESC);
CREATE INDEX idx_locations_geog ON locations USING GIST(point);

-- Assistant connections (MCP tokens)
CREATE TABLE assistant_connections (
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

CREATE INDEX idx_assistant_tokens ON assistant_connections(mcp_token) 
    WHERE revoked_at IS NULL;
CREATE INDEX idx_assistant_user ON assistant_connections(user_id, assistant_type);

-- Access logs (transparency)
CREATE TABLE access_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    assistant_type TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    location_count INTEGER DEFAULT 0,
    query_params JSONB,
    response_time_ms INTEGER
);

CREATE INDEX idx_access_logs_user_time ON access_logs(user_id, timestamp DESC);
```

### Data Model Details

**Users**
- `id`: Client-generated UUID (device identifier)
- `api_key`: Server-generated secret (format: `fletch_sk_<random>`)
- `retention_days`: -1 for indefinite, otherwise positive integer (default 30).
- `privacy_settings`: JSONB with user preferences

**Locations**
- `point`: PostGIS geography type (stores lat/lon in WGS84)
- `timestamp`: When location was recorded (not inserted)

---

## 4. API Specification

### Authentication

**Mobile App API:**
All endpoints (except `/api/register` and `/health`) require:
```
Authorization: Bearer fletch_sk_<random_string>
```

**MCP Server (SSE):**
Requires:
```
Authorization: Bearer mcp_<random_string>
```
Or query param `?token=mcp_<random_string>`

### Mobile App API

#### 1. Register Device
**POST** `/api/register`

Creates a new user account.
**Request:** `{ "user_id": "UUID" }`
**Response:** `{ "user_id": "UUID", "api_key": "fletch_sk_...", "created_at": "..." }`

#### 2. Store Locations
**POST** `/api/locations`

Batch upload location points.
**Request:**
```json
{
  "locations": [
    { "latitude": 37.7749, "longitude": -122.4194, "accuracy": 15.0, "timestamp": "ISO8601" }
  ]
}
```

#### 3. Get Location History
**GET** `/api/locations`

Retrieve location history.
**Query Parameters:**
- `limit`: Number of records (default: 100, max: 10000)
- `before`: ISO Date string (pagination cursor, get records older than this date)

**Response:**
```json
{
  "status": "ok",
  "locations": [ ... ]
}
```

#### 4. Privacy Settings
**GET** `/api/privacy-settings`
**PATCH** `/api/privacy-settings`

Manage precision, history access window, and retention policy.

### MCP Management API (Mobile App)

These endpoints are called by the mobile app to manage MCP tokens. Auth: `fletch_sk_...`

#### 1. Generate MCP Token
**POST** `/api/mcp/generate-token`

**Request:** `{ "assistant_type": "claude", "token_name": "My MacBook" }`
**Response:** `{ "token": "mcp_...", "sse_url": "...", "expires_at": "..." }`

#### 2. List MCP Tokens
**GET** `/api/mcp/tokens`

**Response:** `{ "tokens": [ { "id": "...", "token_name": "...", "status": "active", ... } ] }`

#### 3. Revoke MCP Token
**DELETE** `/api/mcp/tokens/:id`

Revokes access immediately.

---

## 5. Model Context Protocol (MCP)

### Endpoints

**GET /sse**
Establishes SSE connection for MCP.
**Headers:** `Authorization: Bearer mcp_...`

### Resources

**1. Current Location**
URI: `fletcher://location/current`
Returns the single most recent location fix.

**2. Location History**
URI: `fletcher://location/history`
Returns recent history (last 24h by default), respecting privacy settings.

### Tools

**1. get_location_history**
Arguments: `start_date` (ISO), `end_date` (ISO).
Returns GeoJSON FeatureCollection of locations within range.

---

## 6. Security & Privacy

### Data Minimization
- Only Latitude, Longitude, Accuracy, and Timestamp are stored.
- No PII (names, emails) collected.

### Retention Policy
- Default: 30 Days.
- Configurable: 1-90 days, or -1 (Indefinite).
- Automated cleanup job runs daily to remove expired data.