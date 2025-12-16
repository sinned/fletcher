# Technical Design Document - Fletcher Server v2.0

**Version:** 2.0 (MVP)  
**Last Updated:** December 2025  
**Status:** Ready for Implementation

---

## 1. System Overview

The Fletcher Server is the central backend for the Fletcher ecosystem, responsible for securely storing user location data and exposing it to AI assistants (Claude) via the Model Context Protocol (MCP).

### Tech Stack

- **Runtime:** Node.js 20+ (TypeScript 5.3+)
- **Framework:** Fastify 4.x
- **Database:** PostgreSQL 15+ with PostGIS 3.4+
- **Cache:** Redis 7+ (optional for MVP, recommended for production)
- **Deployment:** Railway or Render (managed platform)
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
- Authenticates via API keys
- Rate limited per user

**2. MCP Server**
- Handles AI assistant connections via Server-Sent Events (SSE)
- Authenticates via pre-shared MCP tokens
- Exposes resources and tools per MCP spec

**3. Background Jobs**
- Data retention cleanup (daily at 3 AM UTC)
- Access log aggregation (optional)
- Health checks and metrics

### Connection Flow (Pre-Shared Token)

**How Users Connect Claude to Fletcher:**

```
┌──────────────────────────────────────────────────────────────┐
│ 1. User opens Fletcher app → Settings → "Connect Claude"    │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. App calls: POST /api/mcp/generate-token                  │
│    Server generates MCP token and returns it                │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. App displays:                                            │
│    ┌────────────────────────────────────┐                   │
│    │ Copy these to Claude Settings:     │                   │
│    │                                    │                   │
│    │ URL: https://mcp.fletcher.app/sse  │ [Copy]           │
│    │ Token: mcp_a1b2c3d4...            │ [Copy]           │
│    │                                    │                   │
│    │ [Open Claude Settings]             │                   │
│    └────────────────────────────────────┘                   │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. User goes to Claude → Settings → Add MCP Server          │
│    Pastes URL and token from Fletcher                       │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. Claude connects: GET /sse                                │
│    Headers: Authorization: Bearer mcp_...                   │
#### Authentication Flow (Simplified)
1.  **Mobile App:** Uses API Key (`fletch_sk_...`) sent in `Authorization: Bearer` header.
2.  **MCP (Claude):** Uses query parameter `?token=mcp_...` or Header. 
    *   *Reasoning:* Claude Desktop often prefers single-URL configuration.
    *   The server uses a **Fastify Plugin** to handle MCP routes (`/sse`, `/messages`) separately, disabling standard JSON parsing to allow the MCP SDK to handle the raw stream.
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 6. Done! Claude can now access location data                │
└──────────────────────────────────────────────────────────────┘
```

**Benefits of This Approach:**
- ✅ No OAuth complexity
- ✅ User can initiate from Fletcher OR Claude
- ✅ Standard MCP pattern (follows how other MCP servers work)
- ✅ No sign-in required (device-ID based)
- ✅ User sees the token, maintains control
- ✅ Instantly revocable from Fletcher app

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
    created_at TIMESTAMP DEFAULT NOW(),
    retention_days INTEGER DEFAULT 30 CHECK (retention_days BETWEEN 1 AND 90),
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
    timestamp TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
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
    connected_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP NULL,
    last_used_at TIMESTAMP NULL
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
    timestamp TIMESTAMP DEFAULT NOW(),
    location_count INTEGER DEFAULT 0,
    query_params JSONB,
    response_time_ms INTEGER
);

CREATE INDEX idx_access_logs_user_time ON access_logs(user_id, timestamp DESC);
CREATE INDEX idx_access_logs_timestamp ON access_logs(timestamp DESC);
```

### Data Model Details

**Users**
- `id`: Client-generated UUID (device identifier)
- `api_key`: Server-generated secret (format: `fletch_sk_<random>`)
- `retention_days`: How long to keep location history (1-90 days)
- `privacy_settings`: JSONB with user preferences

**Locations**
- `point`: PostGIS geography type (stores lat/lon in WGS84)
- `accuracy`: GPS accuracy in meters
- `timestamp`: When location was recorded (not inserted)
- `created_at`: When record was inserted (for debugging)

**Assistant Connections**
- `mcp_token`: Bearer token for MCP access (format: `mcp_<random>`)
- `token_name`: Optional user-friendly name (e.g., "My MacBook", "Work Setup")
- `expires_at`: Token expiration (1 year for MVP)
- `revoked_at`: If user disconnected, timestamp of revocation
- `last_used_at`: For monitoring inactive connections

**Access Logs**
- Complete audit trail of all AI assistant access
- `query_params`: Stores request details (date ranges, etc.)
- `response_time_ms`: For performance monitoring

---

## 4. API Specification

### Authentication

All mobile app endpoints require API key authentication:

```
Authorization: Bearer fletch_sk_<random_string>
```

All MCP endpoints require OAuth token:

```
Authorization: Bearer mcp_<random_string>
```

### Mobile App API

#### 1. Register Device

**POST** `/api/register`

Creates a new user account with device ID.

**Request:**
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response:** `201 Created`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "api_key": "fletch_sk_a1b2c3d4e5f6...",
  "created_at": "2025-12-14T17:30:00Z"
}
```

**Errors:**
- `400` - Invalid user_id format
- `409` - User ID already registered

**Notes:**
- Call once on first app launch
- Store `api_key` securely in iOS Keychain
- `user_id` must be valid UUIDv4

---

#### 2. Store Locations

**POST** `/api/locations`

Batch upload location points from device.

**Request:**
```json
{
  "locations": [
    {
      "latitude": 37.7749,
      "longitude": -122.4194,
      "accuracy": 15.0,
      "timestamp": "2025-12-14T17:25:00Z"
    },
    {
      "latitude": 37.7750,
      "longitude": -122.4195,
      "accuracy": 20.0,
      "timestamp": "2025-12-14T17:30:00Z"
    }
  ]
}
```

**Response:** `200 OK`
```json
{
  "status": "ok",
  "count": 2,
  "inserted_at": "2025-12-14T17:30:15Z"
}
```

**Validation:**
- `latitude`: -90 to 90
- `longitude`: -180 to 180
- `accuracy`: > 0 (meters)
- `timestamp`: ISO 8601 format, not in future
- Max 100 locations per request

**Errors:**
- `400` - Invalid location data
- `401` - Invalid or missing API key
- `429` - Rate limit exceeded

**Rate Limit:** 60 requests/minute per user

---

#### 3. Get Privacy Settings

**GET** `/api/privacy-settings`

Retrieve current privacy configuration.

**Response:** `200 OK`
```json
{
  "precision_level": "medium",
  "history_access_days": 7,
  "enabled": true,
  "retention_days": 30
}
```

**Precision Levels:**
- `high`: Full GPS accuracy (~10m)
- `medium`: Reduced accuracy (~100m)
- `low`: City-level (~1km)

---

#### 4. Update Privacy Settings

**PATCH** `/api/privacy-settings`

Update user privacy preferences.

**Request:**
```json
{
  "precision_level": "low",
  "history_access_days": 1,
  "enabled": true
}
```

**Response:** `200 OK`
```json
{
  "status": "ok",
  "updated_at": "2025-12-14T17:30:00Z"
}
```

**Validation:**
- `precision_level`: "high" | "medium" | "low"
- `history_access_days`: 0-30 (0 = current location only)
- `enabled`: boolean

---

#### 5. Get Access Logs

**GET** `/api/access-logs`

Retrieve audit trail of AI assistant access.

**Query Parameters:**
- `limit`: Number of records (default: 50, max: 200)
- `offset`: Pagination offset (default: 0)

**Response:** `200 OK`
```json
{
  "logs": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "assistant_type": "claude",
      "endpoint": "location_history",
      "timestamp": "2025-12-14T17:28:00Z",
      "location_count": 48,
      "query_params": {
        "start_date": "2025-12-14T00:00:00Z",
        "end_date": "2025-12-14T23:59:59Z"
      }
    }
  ],
  "total": 127,
  "limit": 50,
  "offset": 0
}
```

---

#### 6. Get Connections

**GET** `/api/connections`

List connected AI assistants.

**Response:** `200 OK`
```json
{
  "connections": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "assistant_type": "claude",
      "connected_at": "2025-12-10T14:22:00Z",
      "last_used_at": "2025-12-14T17:28:00Z",
      "status": "active"
    }
  ]
}
```

**Status Values:**
- `active`: Currently connected
- `expired`: Token expired
- `revoked`: User disconnected

---

#### 7. Revoke Connection

**DELETE** `/api/connections/:assistant_type`

Disconnect an AI assistant (e.g., `claude`).

**Response:** `200 OK`
```json
{
  "status": "ok",
  "revoked_at": "2025-12-14T17:30:00Z"
}
```

**Effect:** Immediately invalidates OAuth token, Claude can no longer access location.

---

#### 8. Get Stats

**GET** `/api/stats`

Retrieve account statistics.

**Response:** `200 OK`
```json
{
  "total_locations": 4832,
  "oldest_location": "2025-11-14T08:15:00Z",
  "newest_location": "2025-12-14T17:30:00Z",
  "storage_used_mb": 2.3,
  "days_tracked": 30,
  "retention_days": 30
}
```

---

#### 9. Delete Account

**DELETE** `/api/account`

Permanently delete all user data.

**Response:** `200 OK`
```json
{
  "status": "ok",
  "deleted_at": "2025-12-14T17:30:00Z"
}
```

**Effect:** 
- Deletes user, all locations, connections, and logs
- CASCADE delete ensures complete removal
- Invalidates API key immediately

---

#### 10. Generate MCP Token

**POST** `/api/mcp/generate-token`

Generate a new MCP token for connecting Claude to Fletcher.

**Request:**
```json
{
  "assistant_type": "claude",
  "token_name": "My MacBook"
}
```

**Response:** `201 Created`
```json
{
  "token": "mcp_a1b2c3d4e5f6g7h8i9j0...",
  "sse_url": "https://mcp.fletcher.app/sse",
  "expires_at": "2026-12-14T17:30:00Z",
  "instructions": "Add this MCP server to Claude:\n1. Open Claude Settings → Integrations\n2. Click 'Add MCP Server'\n3. Enter the URL and token above"
}
```

**Validation:**
- `assistant_type`: Must be "claude" (for MVP)
- `token_name`: Optional, max 50 characters
- User can have multiple tokens per assistant type

**Notes:**
- Token is shown only once - user must copy it
- Store token securely in Claude's MCP settings
- Token grants full access to location data (per privacy settings)

---

#### 11. List MCP Tokens

**GET** `/api/mcp/tokens`

List all MCP tokens for this user.

**Response:** `200 OK`
```json
{
  "tokens": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "assistant_type": "claude",
      "token_name": "My MacBook",
      "connected_at": "2025-12-10T14:22:00Z",
      "last_used_at": "2025-12-14T17:28:00Z",
      "expires_at": "2026-12-10T14:22:00Z",
      "status": "active",
      "token_preview": "mcp_a1b2...j0k1"
    }
  ]
}
```

**Token Preview:**
- First 8 and last 4 characters shown for identification
- Full token never returned after creation

---

#### 12. Revoke MCP Token

**DELETE** `/api/mcp/tokens/:token_id`

Revoke a specific MCP token.

**Response:** `200 OK`
```json
{
  "status": "ok",
  "revoked_at": "2025-12-14T17:30:00Z"
}
```

**Effect:** Claude immediately loses access to location data.

---

### Model Context Protocol (MCP) Endpoints

#### MCP Server Endpoint

**GET** `/sse`

Establishes MCP connection via Server-Sent Events.

**Headers:**
```
Authorization: Bearer mcp_a1b2c3d4e5f6...
```

**Response:** SSE stream with MCP messages

**Connection Flow:**
1. Validate Bearer token
2. Extract `user_id` from token
3. Establish SSE connection
4. Send MCP initialization message
5. Wait for tool/resource requests
6. Log all access to `access_logs`

---

#### MCP Initialization Message

Sent immediately after connection:

```json
{
  "jsonrpc": "2.0",
  "method": "initialize",
  "params": {
    "protocolVersion": "0.1.0",
    "capabilities": {
      "resources": {
        "subscribe": false
      },
      "tools": {}
    },
    "serverInfo": {
      "name": "fletcher-mcp",
      "version": "1.0.0"
    }
  }
}
```

---

#### MCP Resources

**1. Current Location**

**Resource URI:** `fletcher://location/current`

**Description:** Most recent location fix (within last 5 minutes)

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "resources/read",
  "params": {
    "uri": "fletcher://location/current"
  },
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "contents": [{
      "uri": "fletcher://location/current",
      "mimeType": "application/geo+json",
      "text": "{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[-122.4194,37.7749]},\"properties\":{\"accuracy\":15.0,\"timestamp\":\"2025-12-14T17:30:00Z\",\"precision_level\":\"medium\"}}"
    }]
  },
  "id": 1
}
```

**Precision Application:**
- `high`: Exact coordinates
- `medium`: Rounded to ~100m (~0.001 degrees)
- `low`: Rounded to ~1km (~0.01 degrees)

---

**2. Location History**

**Resource URI:** `fletcher://location/history`

**Description:** Last 24 hours of location data (respects `history_access_days` setting)

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "resources/read",
  "params": {
    "uri": "fletcher://location/history"
  },
  "id": 2
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "contents": [{
      "uri": "fletcher://location/history",
      "mimeType": "application/geo+json",
      "text": "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[-122.4194,37.7749]},\"properties\":{\"accuracy\":15.0,\"timestamp\":\"2025-12-14T17:30:00Z\"}},{\"type\":\"Feature\",\"geometry\":{\"type\":\"Point\",\"coordinates\":[-122.4195,37.7750]},\"properties\":{\"accuracy\":20.0,\"timestamp\":\"2025-12-14T17:25:00Z\"}}]}"
    }]
  },
  "id": 2
}
```

**History Limits:**
- Respect user's `history_access_days` setting
- Max 1000 points per response
- If more points exist, return most recent 1000

---

#### MCP Tools

**1. Get Location History (Custom Date Range)**

**Tool Name:** `get_location_history`

**Description:** Fetch location history for specific time period

**Input Schema:**
```json
{
  "type": "object",
  "properties": {
    "start_date": {
      "type": "string",
      "format": "date-time",
      "description": "Start of time range (ISO 8601)"
    },
    "end_date": {
      "type": "string",
      "format": "date-time",
      "description": "End of time range (ISO 8601)"
    }
  },
  "required": []
}
```

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "get_location_history",
    "arguments": {
      "start_date": "2025-12-14T00:00:00Z",
      "end_date": "2025-12-14T23:59:59Z"
    }
  },
  "id": 3
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "content": [{
      "type": "text",
      "text": "{\"type\":\"FeatureCollection\",\"features\":[...]}"
    }],
    "isError": false
  },
  "id": 3
}
```

**Validation:**
- `end_date` must be after `start_date`
- Range cannot exceed user's `history_access_days` setting
- Range cannot exceed 30 days total
- Dates cannot be in the future

---

## 5. Security Implementation

### API Key Generation

```typescript
import crypto from 'crypto';

function generateAPIKey(): string {
  const randomBytes = crypto.randomBytes(32);
  const key = randomBytes.toString('base64url');
  return `fletch_sk_${key}`;
}

// Store hashed version in database
function hashAPIKey(apiKey: string): string {
  return crypto
    .createHash('sha256')
    .update(apiKey)
    .digest('hex');
}
```

**Storage:**
- Store hashed API key in database
- Return plaintext key only once during registration
- User must store in iOS Keychain

### MCP Token Generation

```typescript
function generateMCPToken(): string {
  const randomBytes = crypto.randomBytes(32);
  const token = randomBytes.toString('base64url');
  return `mcp_${token}`;
}
```

**Token Validation:**
```typescript
async function validateMCPToken(token: string): Promise<{ userId: string } | null> {
  const connection = await db.query(`
    SELECT user_id, expires_at, revoked_at
    FROM assistant_connections
    WHERE mcp_token = $1
  `, [token]);
  
  if (!connection.rows[0]) return null;
  if (connection.rows[0].revoked_at) return null;
  if (new Date(connection.rows[0].expires_at) < new Date()) return null;
  
  // Update last_used_at
  await db.query(`
    UPDATE assistant_connections
    SET last_used_at = NOW()
    WHERE mcp_token = $1
  `, [token]);
  
  return { userId: connection.rows[0].user_id };
}
```

### Rate Limiting

```typescript
// Per-endpoint rate limits
const rateLimits = {
  '/api/locations': { points: 60, duration: 60 }, // 60 req/min
  '/api/*': { points: 120, duration: 60 },        // 120 req/min
  '/mcp/tools/*': { points: 30, duration: 60 }    // 30 req/min
};

// Use @fastify/rate-limit plugin
fastify.register(rateLimit, {
  max: 60,
  timeWindow: '1 minute',
  keyGenerator: (request) => {
    // Extract user_id from API key or OAuth token
    return getUserIdFromAuth(request);
  }
});
```

### HTTPS Enforcement

```typescript
// Redirect HTTP to HTTPS in production
if (process.env.NODE_ENV === 'production') {
  fastify.addHook('onRequest', async (request, reply) => {
    if (request.headers['x-forwarded-proto'] !== 'https') {
      reply.redirect(301, `https://${request.hostname}${request.url}`);
    }
  });
}
```

---

## 6. Privacy Implementation

### Precision Reduction

```typescript
function applyPrecisionLevel(
  lat: number, 
  lon: number, 
  level: 'high' | 'medium' | 'low'
): [number, number] {
  switch (level) {
    case 'high':
      return [lat, lon]; // No reduction
    
    case 'medium':
      // Round to ~100m (0.001 degrees ≈ 111m)
      return [
        Math.round(lat * 1000) / 1000,
        Math.round(lon * 1000) / 1000
      ];
    
    case 'low':
      // Round to ~1km (0.01 degrees ≈ 1.1km)
      return [
        Math.round(lat * 100) / 100,
        Math.round(lon * 100) / 100
      ];
  }
}
```

### Access Logging

```typescript
async function logAccess(params: {
  userId: string;
  assistantType: string;
  endpoint: string;
  locationCount: number;
  queryParams?: any;
  responseTimeMs: number;
}) {
  await db.query(`
    INSERT INTO access_logs (
      user_id, assistant_type, endpoint, 
      location_count, query_params, response_time_ms
    ) VALUES ($1, $2, $3, $4, $5, $6)
  `, [
    params.userId,
    params.assistantType,
    params.endpoint,
    params.locationCount,
    JSON.stringify(params.queryParams || {}),
    params.responseTimeMs
  ]);
}

// Use in middleware
fastify.addHook('onResponse', async (request, reply) => {
  if (request.url.startsWith('/mcp/')) {
    const userId = (request as any).userId;
    const responseTime = reply.getResponseTime();
    
    await logAccess({
      userId,
      assistantType: 'claude',
      endpoint: request.url,
      locationCount: (reply as any).locationCount || 0,
      queryParams: request.body,
      responseTimeMs: Math.round(responseTime)
    });
  }
});
```

### Data Retention Cleanup

```typescript
import cron from 'node-cron';

// Run daily at 3 AM UTC
cron.schedule('0 3 * * *', async () => {
  console.log('Running data retention cleanup...');
  
  const result = await db.query(`
    DELETE FROM locations
    WHERE timestamp < NOW() - INTERVAL '1 day' * (
      SELECT retention_days FROM users WHERE id = locations.user_id
    )
  `);
  
  console.log(`Deleted ${result.rowCount} expired location records`);
  
  // Cleanup old access logs (keep 90 days)
  await db.query(`
    DELETE FROM access_logs
    WHERE timestamp < NOW() - INTERVAL '90 days'
  `);
});
```

---

## 7. Error Handling

### Standard Error Response

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": {},
    "timestamp": "2025-12-14T17:30:00Z",
    "request_id": "req_abc123"
  }
}
```

### Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_API_KEY` | 401 | API key missing or invalid |
| `INVALID_TOKEN` | 401 | OAuth token invalid or expired |
| `USER_NOT_FOUND` | 404 | User ID doesn't exist |
| `INVALID_REQUEST` | 400 | Request validation failed |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |
| `PRIVACY_RESTRICTED` | 403 | Privacy settings prevent access |
| `INVALID_DATE_RANGE` | 400 | Date range validation failed |

### Error Handler Middleware

```typescript
fastify.setErrorHandler((error, request, reply) => {
  // Log error for monitoring
  console.error({
    error: error.message,
    stack: error.stack,
    url: request.url,
    method: request.method,
    requestId: request.id
  });
  
  // Determine error code
  let statusCode = error.statusCode || 500;
  let errorCode = 'INTERNAL_ERROR';
  
  if (error.validation) {
    statusCode = 400;
    errorCode = 'INVALID_REQUEST';
  }
  
  // Send error response
  reply.status(statusCode).send({
    error: {
      code: errorCode,
      message: error.message,
      details: error.validation || {},
      timestamp: new Date().toISOString(),
      request_id: request.id
    }
  });
});
```

---

## 8. Deployment

### Environment Variables

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:5432/fletcher
DATABASE_POOL_MIN=2
DATABASE_POOL_MAX=10

# Server
NODE_ENV=production
PORT=3000
HOST=0.0.0.0

# Security
API_SECRET_KEY=<random-256-bit-key>

# CORS
ALLOWED_ORIGINS=https://fletcher-app.com,https://claude.ai

# Rate Limiting
RATE_LIMIT_MAX=60
RATE_LIMIT_WINDOW=60000

# Monitoring (optional)
SENTRY_DSN=https://...
LOG_LEVEL=info
```

### Database Migrations

Use a migration tool like `node-pg-migrate`:

```bash
# migrations/001_initial_schema.sql
# migrations/002_add_access_logs.sql
# etc.

npm run migrate up
```

### Deployment Platform: Railway

**Why Railway:**
- PostgreSQL built-in with PostGIS support
- Automatic HTTPS
- Zero-config deployments
- Affordable ($5-20/month for MVP)

**Setup:**
1. Connect GitHub repo
2. Add PostgreSQL service
3. Enable PostGIS extension
4. Set environment variables
5. Deploy

**Alternative: Render**
- Similar features
- Slightly different pricing
- Both are good for MVP

### Health Check Endpoint

```typescript
fastify.get('/health', async (request, reply) => {
  try {
    // Check database connection
    await db.query('SELECT 1');
    
    return {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      uptime: process.uptime()
    };
  } catch (error) {
    reply.status(503).send({
      status: 'unhealthy',
      error: error.message
    });
  }
});
```

---

## 9. Monitoring & Observability

### Logging

```typescript
import pino from 'pino';

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true
    }
  }
});

// Request logging
fastify.addHook('onRequest', (request, reply, done) => {
  logger.info({
    requestId: request.id,
    method: request.method,
    url: request.url
  }, 'Incoming request');
  done();
});

// Response logging
fastify.addHook('onResponse', (request, reply, done) => {
  logger.info({
    requestId: request.id,
    statusCode: reply.statusCode,
    responseTime: reply.getResponseTime()
  }, 'Request completed');
  done();
});
```

### Metrics to Track

**Application Metrics:**
- Request count (by endpoint, status code)
- Response times (p50, p95, p99)
- Error rate
- Active SSE connections

**Business Metrics:**
- Daily/Weekly/Monthly active users
- Location points ingested per day
- MCP requests per user
- Average locations per batch

**Database Metrics:**
- Query execution time
- Connection pool usage
- Table sizes
- Index hit rates

### Error Tracking

Use Sentry for production error tracking:

```typescript
import * as Sentry from '@sentry/node';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV,
    tracesSampleRate: 0.1
  });
  
  fastify.addHook('onError', (request, reply, error, done) => {
    Sentry.captureException(error, {
      extra: {
        url: request.url,
        method: request.method,
        userId: (request as any).userId
      }
    });
    done();
  });
}
```

---

## 10. Testing Strategy

### Unit Tests

```typescript
// Example: test precision reduction
describe('applyPrecisionLevel', () => {
  it('should not modify coordinates at high precision', () => {
    const [lat, lon] = applyPrecisionLevel(37.7749, -122.4194, 'high');
    expect(lat).toBe(37.7749);
    expect(lon).toBe(-122.4194);
  });
  
  it('should round to ~100m at medium precision', () => {
    const [lat, lon] = applyPrecisionLevel(37.77499, -122.41949, 'medium');
    expect(lat).toBe(37.775);
    expect(lon).toBe(-122.419);
  });
  
  it('should round to ~1km at low precision', () => {
    const [lat, lon] = applyPrecisionLevel(37.7749, -122.4194, 'low');
    expect(lat).toBe(37.77);
    expect(lon).toBe(-122.42);
  });
});
```

### Integration Tests

```typescript
// Example: test location ingestion
describe('POST /api/locations', () => {
  let apiKey: string;
  
  beforeEach(async () => {
    // Create test user
    const response = await fastify.inject({
      method: 'POST',
      url: '/api/register',
      payload: { user_id: TEST_USER_ID }
    });
    apiKey = response.json().api_key;
  });
  
  it('should store locations successfully', async () => {
    const response = await fastify.inject({
      method: 'POST',
      url: '/api/locations',
      headers: { Authorization: `Bearer ${apiKey}` },
      payload: {
        locations: [{
          latitude: 37.7749,
          longitude: -122.4194,
          accuracy: 15.0,
          timestamp: new Date().toISOString()
        }]
      }
    });
    
    expect(response.statusCode).toBe(200);
    expect(response.json().count).toBe(1);
  });
  
  it('should reject invalid coordinates', async () => {
    const response = await fastify.inject({
      method: 'POST',
      url: '/api/locations',
      headers: { Authorization: `Bearer ${apiKey}` },
      payload: {
        locations: [{
          latitude: 999, // Invalid
          longitude: -122.4194,
          accuracy: 15.0,
          timestamp: new Date().toISOString()
        }]
      }
    });
    
    expect(response.statusCode).toBe(400);
  });
});
```

### Load Testing

Use k6 for load testing:

```javascript
// load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 50 },  // Ramp up to 50 users
    { duration: '3m', target: 50 },  // Stay at 50 users
    { duration: '1m', target: 0 },   // Ramp down
  ],
};

export default function () {
  const payload = JSON.stringify({
    locations: [{
      latitude: 37.7749,
      longitude: -122.4194,
      accuracy: 15.0,
      timestamp: new Date().toISOString()
    }]
  });
  
  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${API_KEY}`
    },
  };
  
  let res = http.post('https://api.fletcher.app/api/locations', payload, params);
  check(res, { 'status is 200': (r) => r.status === 200 });
  
  sleep(1);
}
```

---

## 11. API Versioning Strategy

For MVP, no versioning needed. Future versions:

```
/v1/api/locations  (current)
/v2/api/locations  (future breaking changes)
```

Use header-based versioning:
```
Accept: application/vnd.fletcher.v1+json
```

---

## 12. Backup & Disaster Recovery

### Database Backups

Railway/Render provide automatic daily backups. Additionally:

```bash
# Manual backup
pg_dump $DATABASE_URL > backup-$(date +%Y%m%d).sql

# Restore
psql $DATABASE_URL < backup-20251214.sql
```

### Backup Schedule
- Automated daily backups (retained 7 days)
- Weekly backups (retained 30 days)
- Monthly backups (retained 1 year)

### Recovery Time Objective (RTO)
- Target: < 1 hour for full restoration
- Point-in-time recovery within 24 hours

### Recovery Point Objective (RPO)
- Target: < 15 minutes of data loss
- Achievable with proper backup frequency

---

## 13. Performance Targets

### Response Times (p95)
- `POST /api/locations`: < 100ms
- `GET /api/access-logs`: < 200ms
- `GET /mcp/resources/current`: < 50ms
- `GET /mcp/resources/history`: < 500ms

### Throughput
- Handle 1000 location points per second
- Support 500 concurrent SSE connections
- Database should handle 10,000 QPS

### Scalability
MVP targets 500 users, but architecture should scale to 10,000+ with minimal changes.

---

## 14. Security Checklist

- [x] API key authentication
- [x] OAuth2 token validation
- [x] Rate limiting per user
- [x] HTTPS enforcement
- [x] SQL injection prevention (parameterized queries)
- [x] CORS configuration
- [x] Request size limits
- [x] Token expiration
- [x] Access logging
- [x] Error message sanitization (no stack traces in production)
- [x] Environment variable secrets (not hardcoded)
- [x] Database connection encryption
- [x] Password hashing for API keys

---

## 15. Open Questions & Future Considerations

### For MVP
1. **Token Security:** Should tokens be revocable by Claude as well as the user?
2. **Token Limits:** Should there be a limit on how many tokens a user can generate?
3. **Token Names:** Should we require token names or make them optional?

### Post-MVP
4. **Token Rotation:** Implement automatic token rotation for security
5. **Scoped Tokens:** Allow tokens with limited permissions (read-only current location, etc.)
6. **Geofencing:** Add geofence resources to MCP
7. **Multi-Assistant:** Extend beyond Claude (Poke, ChatGPT, etc.)
8. **Analytics Dashboard:** Web dashboard for users to visualize location history
9. **Export Functionality:** Allow users to export all data as JSON/KML
10. **Real-time Updates:** WebSocket support for live location streaming
11. **Shared Locations:** Temporary location sharing with other users
12. **Offline Mode:** Store locations offline and sync when connected

---

## 16. Implementation Checklist

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Initialize Node.js/TypeScript project with Fastify
- [ ] Set up PostgreSQL with PostGIS on Railway/Render
- [ ] Create database schema and migrations
- [ ] Implement API key generation and validation
- [ ] Set up error handling and logging

### Phase 2: Mobile API (Week 3-4)
- [ ] Implement `/api/register` endpoint
- [ ] Implement `/api/locations` with batch upload
- [ ] Implement privacy settings endpoints
- [ ] Implement access logs endpoint
- [ ] Implement connection management endpoints
- [ ] Implement MCP token generation endpoints
- [ ] Add rate limiting middleware

### Phase 3: MCP Server (Week 5-6)
- [ ] Implement SSE connection handler
- [ ] Implement MCP resource endpoints
- [ ] Implement MCP tools
- [ ] Apply precision level filtering
- [ ] Add access logging for MCP requests
- [ ] Test MCP integration with Claude

### Phase 4: Privacy & Cleanup (Week 7-8)
- [ ] Implement data retention cleanup job
- [ ] Add precision reduction logic
- [ ] Test privacy settings enforcement
- [ ] Implement account deletion

### Phase 5: Testing & Launch (Week 9-10)
- [ ] Write unit tests (80%+ coverage)
- [ ] Write integration tests
- [ ] Load testing with k6
- [ ] Security audit
- [ ] Deploy to production
- [ ] Document API for mobile team

---

## Appendix A: Sample TypeScript Implementation

### Fastify Server Setup

```typescript
// src/server.ts
import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { config } from './config';
import { authPlugin } from './plugins/auth';
import { mobileRoutes } from './routes/mobile';
import { mcpRoutes } from './routes/mcp';

const fastify = Fastify({
  logger: {
    level: config.logLevel,
  },
  requestIdHeader: 'x-request-id',
  requestIdLogLabel: 'requestId',
});

// Plugins
await fastify.register(cors, {
  origin: config.allowedOrigins,
  credentials: true,
});

await fastify.register(rateLimit, {
  max: 60,
  timeWindow: '1 minute',
});

await fastify.register(authPlugin);

// Routes
await fastify.register(mobileRoutes, { prefix: '/api' });
await fastify.register(mcpRoutes, { prefix: '/mcp' });

// Health check
fastify.get('/health', async () => ({
  status: 'healthy',
  timestamp: new Date().toISOString(),
}));

// Start server
await fastify.listen({
  port: config.port,
  host: config.host,
});

console.log(`Server listening on ${config.host}:${config.port}`);
```

---

**End of Technical Design Document**

This document represents the complete technical specification for Fletcher Server MVP. All sections should be reviewed and approved before development begins.

**Next Steps:**
1. Review with engineering team
2. Estimate implementation time per phase
3. Set up development environment
4. Begin Phase 1 implementation