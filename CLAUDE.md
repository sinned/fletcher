# CLAUDE.md - AI Assistant Guide for Fletcher

**Last Updated:** 2025-12-24
**Repository:** Fletcher - Privacy-first location tracking app with MCP integration
**Version:** iOS v1.5.1 | Server v1.3.0

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Technology Stack](#technology-stack)
4. [Directory Structure](#directory-structure)
5. [Development Workflows](#development-workflows)
6. [Code Conventions](#code-conventions)
7. [Key Patterns & Practices](#key-patterns--practices)
8. [Common Tasks](#common-tasks)
9. [Testing](#testing)
10. [Deployment](#deployment)
11. [Important Constraints](#important-constraints)
12. [Troubleshooting](#troubleshooting)

---

## Project Overview

Fletcher is a **privacy-first location tracking system** that enables AI assistants to provide location-aware assistance through the Model Context Protocol (MCP). The system consists of:

- **iOS Client**: Native SwiftUI app for background location tracking and data visualization
- **Backend Server**: Node.js/Fastify server with PostgreSQL/PostGIS for geospatial storage and MCP integration
- **MCP Integration**: Server-Sent Events (SSE) protocol for real-time AI assistant access

### Core Principles

1. **Privacy First**: User data is isolated, access is logged, deletion is immediate
2. **Transparency**: All AI assistant requests are logged and visible to users
3. **Simplicity**: MVP-focused, defer complexity, clear separation of concerns
4. **Security by Default**: API keys, token validation, rate limiting, encrypted storage

---

## Architecture

### High-Level System Design

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

### iOS Architecture (MVVM)

- **View**: SwiftUI declarative UI components
- **ViewModel**: State management using `@StateObject`, `@EnvironmentObject`
- **Model**: Data structures (`LocationPoint`, `MCPToken`, `MCPRequest`)
- **Services**: Singleton managers (`BackgroundLocationService`, `LocationStore`, `APIClient`)

### Server Architecture (Modular)

- **Routes**: HTTP endpoint handlers (`mobile.ts`, `mcp_api.ts`, `access_logs.ts`)
- **Models**: Database access layer (`user.ts`, `location.ts`, `auth.ts`, `access_log.ts`)
- **MCP**: Isolated MCP server implementation (`mcp/index.ts`)
- **Database**: PostgreSQL with PostGIS extension

---

## Technology Stack

### iOS Application

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Language | Swift 5+ | Native iOS development |
| UI Framework | SwiftUI | Declarative UI |
| Location | CoreLocation | Background tracking |
| Networking | URLSession | HTTP client (async/await) |
| Storage | FileManager + JSON | Local location cache |
| Secure Storage | Keychain | API key storage |
| Maps | MapKit | Interactive map visualization |
| Testing | XCTest | Unit tests |

### Backend Server

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Runtime | Node.js 20+ | JavaScript runtime |
| Language | TypeScript 5.3+ | Type-safe development |
| Framework | Fastify 5.6.2 | High-performance HTTP server |
| Database | PostgreSQL 15+ | Relational database |
| Geospatial | PostGIS 3.4+ | Geographic queries |
| Validation | Zod 4.1+ | Schema validation |
| MCP | @modelcontextprotocol/sdk 1.24.3 | MCP protocol implementation |

### Additional Libraries

**Server:**
- `@fastify/cors`: CORS support
- `@fastify/rate-limit`: Rate limiting
- `@fastify/static`: Static file serving
- `fastify-request-id`: Request tracking
- `pg`: PostgreSQL client
- `dotenv`: Environment configuration

---

## Directory Structure

```
fletcher/
├── ios/Fletcher/Fletcher/           # iOS Application
│   ├── FletcherApp.swift           # App entry point
│   ├── Models/                     # Data models
│   │   ├── LocationPoint.swift     # Core location data
│   │   ├── MCPToken.swift          # MCP token metadata
│   │   └── MCPRequest.swift        # MCP request history
│   ├── Services/
│   │   └── APIClient.swift         # HTTP client (434 lines)
│   ├── Location/
│   │   └── BackgroundLocationService.swift  # Location tracking
│   ├── Storage/
│   │   └── LocationStore.swift     # Local JSON persistence
│   ├── UI/                         # SwiftUI views
│   │   ├── MainView.swift          # Tab navigation
│   │   ├── MapView.swift           # Interactive map
│   │   ├── MCPConnectionView.swift # Token management
│   │   ├── MCPRequestHistoryView.swift  # Request logs
│   │   ├── MCPRequestDetailView.swift   # Request details
│   │   ├── HistoryView.swift       # Location history list
│   │   ├── HistoryMapView.swift    # History map visualization
│   │   ├── SettingsView.swift      # App settings
│   │   ├── SyncStatusView.swift    # Sync diagnostics
│   │   └── SplashScreen.swift      # Launch screen
│   ├── Utilities/
│   │   ├── KeychainManager.swift   # Secure storage
│   │   ├── AppConstants.swift      # Configuration
│   │   ├── Bundle+Version.swift    # Version info
│   │   └── ISO8601DateFormatter+Fletcher.swift
│   ├── Assets.xcassets/            # App icons & colors
│   └── Info.plist                  # App configuration
│
├── server/                          # Backend Server
│   ├── src/
│   │   ├── index.ts                # Main server entry (167 lines)
│   │   ├── cron.ts                 # Cleanup jobs
│   │   ├── db/
│   │   │   ├── index.ts            # PostgreSQL connection
│   │   │   └── schema.sql          # Database schema
│   │   ├── models/                 # Data access layer
│   │   │   ├── user.ts             # User management
│   │   │   ├── location.ts         # Location queries
│   │   │   ├── auth.ts             # Token validation
│   │   │   └── access_log.ts       # Access logging
│   │   ├── routes/                 # HTTP endpoints
│   │   │   ├── mobile.ts           # Mobile app API
│   │   │   ├── mcp_api.ts          # MCP token management
│   │   │   ├── access_logs.ts      # Access log API
│   │   │   └── locations.ts        # Location endpoints
│   │   ├── mcp/
│   │   │   └── index.ts            # MCP server (386 lines)
│   │   ├── utils/
│   │   │   └── crypto.ts           # Token generation
│   │   └── types/
│   │       └── fastify-request-id.d.ts
│   ├── public/                     # Static files
│   │   ├── index.html              # Landing page
│   │   ├── privacy.html            # Privacy policy
│   │   ├── terms.html              # Terms of service
│   │   └── css/                    # Styling
│   ├── package.json                # Dependencies
│   ├── tsconfig.json               # TypeScript config
│   └── .env.example                # Environment template
│
├── artifacts/                       # Documentation
│   ├── changelog.md                # Version history (CRITICAL!)
│   ├── prd-fletcher-ios-app.md     # Product requirements
│   ├── tdd-fletcher-ios-app.md     # iOS technical design
│   ├── tdd-fletcher-server.md      # Server technical design
│   ├── Fletcher_MVP_Scope.md       # MVP scope
│   └── walkthrough_server_v2.md    # Server walkthrough
│
├── .agent/workflows/                # Agent workflows
│   ├── bump_version.md             # Version bump protocol
│   └── update_and_push.md          # Git commit protocol
│
├── README.md                        # Project overview
├── DEPLOYMENT.md                    # Deployment guide
└── CLAUDE.md                        # This file
```

---

## Development Workflows

### Git Commit Convention

Fletcher uses **Conventional Commits** format:

```
<type>(<scope>): <description>

Examples:
- feat(ios): add tappable detail view for MCP requests
- fix(security): validate MCP token on every request
- docs: update TDDs and PRD for MCP request history feature
- chore: bump version to v1.5.1
- refactor(ios): move Request History to Assistants tab
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `chore`: Maintenance tasks
- `refactor`: Code restructuring
- `config`: Configuration changes

**Scopes:**
- `ios`: iOS app changes
- `server`: Backend server changes
- `mcp`: MCP-related changes
- `security`: Security improvements
- `ui`: UI/UX changes

### Branch Naming

When working on features or fixes, use branches starting with `claude/`:

```
claude/add-feature-name-<sessionId>
claude/fix-bug-description-<sessionId>
```

**CRITICAL:** The branch MUST start with `claude/` and end with the matching session ID, otherwise push will fail with 403.

### Version Bumping

Follow the protocol in `.agent/workflows/bump_version.md`:

1. **Determine New Version**: Use semantic versioning (e.g., `v1.5.1` → `v1.5.2`)
2. **Update Source Code**:
   - iOS: `ios/Fletcher/Fletcher/Info.plist` → Update `CFBundleShortVersionString` and `CFBundleVersion`
   - Server: `server/package.json` → Update `version` field
3. **Update Documentation**:
   - **CRITICAL**: `artifacts/changelog.md` → Create new section, move Unreleased items
4. **Verification**:
   - Run app, check Splash Screen shows new version
   - Check Settings footer shows new version
5. **Commit**: `git commit -m "chore: bump version to vX.Y.Z"`

### Update and Push Protocol

**ALWAYS** follow this checklist from `.agent/workflows/update_and_push.md`:

1. **Documentation Review** (CRITICAL):
   - ✅ **Update `artifacts/changelog.md`** with your changes (include timestamp!)
   - ✅ Update `README.md` if new features were added
   - ✅ Update walkthrough docs if visual changes occurred

2. **Code Check**:
   - ✅ Remove temporary debug `print()` statements
   - ✅ Verify build passes

3. **Git Operations**:
   - ✅ `git add .`
   - ✅ `git commit -m "type(scope): description"`
   - ✅ `git push -u origin <branch-name>`

> **IMPORTANT:** Never skip the Changelog update. Users rely on it to know what changed.

### Git Push Retry Logic

**For git push:**
- Always use: `git push -u origin <branch-name>`
- CRITICAL: Branch must start with `claude/` and end with session ID
- If push fails due to network errors, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s)

**For git fetch/pull:**
- Prefer: `git fetch origin <branch-name>`
- If network failures occur, retry up to 4 times with exponential backoff
- For pulls: `git pull origin <branch-name>`

---

## Code Conventions

### Swift (iOS)

**File Organization:**
```swift
// 1. Imports
import SwiftUI
import CoreLocation

// 2. Main struct/class
struct LocationPoint: Codable, Identifiable {
    // 3. Properties
    let id: UUID
    let latitude: Double

    // 4. Methods
    func distance(to other: LocationPoint) -> Double {
        // Implementation
    }
}
```

**Naming Conventions:**
- **Types**: `PascalCase` (e.g., `LocationPoint`, `APIClient`)
- **Variables/Functions**: `camelCase` (e.g., `syncLocations`, `retentionDays`)
- **Constants**: `camelCase` (e.g., `defaultRetentionDays`)
- **Enums**: `PascalCase` with `camelCase` cases

**State Management:**
- Use `@StateObject` for owned state (created in view)
- Use `@EnvironmentObject` for shared state (injected from parent)
- Use `@Published` in ObservableObjects for reactive properties
- Use `@AppStorage` for UserDefaults persistence

**Async/Await:**
- Prefer `async/await` over completion handlers
- Use `Task {}` for async work in SwiftUI views
- Handle errors with `do-catch` blocks

**Example:**
```swift
Task {
    do {
        try await apiClient.syncLocations()
    } catch {
        print("Sync failed: \(error)")
    }
}
```

### TypeScript (Server)

**File Organization:**
```typescript
// 1. Imports
import { FastifyRequest, FastifyReply } from 'fastify';
import { z } from 'zod';

// 2. Type definitions
interface LocationData {
    latitude: number;
    longitude: number;
}

// 3. Validation schemas
const locationSchema = z.object({
    latitude: z.number(),
    longitude: z.number(),
});

// 4. Route handlers
export default async function routes(fastify: FastifyInstance) {
    // Implementation
}
```

**Naming Conventions:**
- **Files**: `snake_case.ts` (e.g., `mcp_api.ts`, `access_log.ts`)
- **Types/Interfaces**: `PascalCase` (e.g., `LocationData`, `UserInfo`)
- **Variables/Functions**: `camelCase` (e.g., `getUserById`, `mcpToken`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `MAX_BATCH_SIZE`)

**Error Handling:**
- Use Zod for input validation
- Return appropriate HTTP status codes (400, 401, 404, 500)
- Log errors with request context
- Provide helpful error messages

**Database Queries:**
- Use parameterized queries (prevent SQL injection)
- Handle connection errors gracefully
- Use transactions for multi-step operations
- Always close connections

---

## Key Patterns & Practices

### iOS Patterns

**1. Singleton Services**
```swift
class LocationStore: ObservableObject {
    static let shared = LocationStore()
    @Published var locations: [LocationPoint] = []

    private init() {
        loadLocations()
    }
}
```

**2. Keychain Storage**
```swift
// ALWAYS use Keychain for API keys, NEVER UserDefaults
KeychainManager.save(key: "apiKey", value: apiKey)
let apiKey = KeychainManager.load(key: "apiKey")
```

**3. Background Location Tracking**
```swift
locationManager.allowsBackgroundLocationUpdates = true
locationManager.pausesLocationUpdatesAutomatically = true
locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
locationManager.distanceFilter = 100
```

**4. Sync Strategy**
```swift
// Batch sync to avoid timeouts
let batchSize = 50
let unsynced = locations.filter { !$0.synced }
for batch in unsynced.chunked(into: batchSize) {
    try await apiClient.uploadLocations(batch)
    locationStore.markSynced(ids: batch.map { $0.id })
}
```

**5. Error Recovery**
```swift
// Auto-register on 401 errors
if statusCode == 401 {
    KeychainManager.delete(key: "apiKey")
    // Trigger re-registration
}
```

### Server Patterns

**1. Authentication Middleware**
```typescript
// Validate API key on every request
const apiKey = request.headers.authorization?.replace('Bearer ', '');
const user = await validateApiKey(apiKey);
if (!user) {
    return reply.code(401).send({ error: 'Invalid API key' });
}
```

**2. MCP Token Validation**
```typescript
// Validate on EVERY request, not just connection
const { userId, assistantType } = await validateMCPToken(token);
// Log every access
await logAccess(userId, assistantType, endpoint, queryParams);
```

**3. Batch Operations**
```typescript
// Insert locations in batches
const values = locations.map((loc, i) =>
    `($${i*4+1}, ST_SetSRID(ST_MakePoint($${i*4+2}, $${i*4+3}), 4326), $${i*4+4})`
).join(',');
await query(`INSERT INTO locations (user_id, point, accuracy, timestamp) VALUES ${values}`, params);
```

**4. Access Logging**
```typescript
// Log ALL MCP requests with details
await query(
    `INSERT INTO access_logs (user_id, assistant_type, endpoint, location_count, query_params, response_time_ms)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [userId, assistantType, endpoint, count, JSON.stringify(params), responseTime]
);
```

**5. Retention Cleanup**
```typescript
// Daily cron job
if (retentionDays === -1) {
    // Indefinite retention, skip
} else {
    await query(
        `DELETE FROM locations WHERE user_id = $1 AND timestamp < NOW() - INTERVAL '${retentionDays} days'`,
        [userId]
    );
}
```

### Data Flow Patterns

**1. Location Upload Flow**
```
iOS App:
1. BackgroundLocationService receives CLLocation
2. Creates LocationPoint with synced=false
3. LocationStore.addLocation() saves to JSON
4. Timer triggers APIClient.syncLocations()
5. Upload batch (max 100 items)
6. On success, mark synced=true

Server:
1. Validate API key
2. Validate schema with Zod
3. Batch insert to PostgreSQL
4. Return 200 OK
```

**2. MCP Connection Flow**
```
iOS App:
1. User taps "Generate Token" in Assistants tab
2. POST /api/mcp/generate-token with assistant_type
3. Display token ONCE (never stored on client)
4. User copies to Claude Desktop config

Claude:
1. Connects to /sse with Bearer token
2. Server validates token on every request
3. Logs all access to access_logs table
4. Returns location data per MCP protocol

iOS App:
1. Polls /api/access-logs to show request history
2. Displays in MCPRequestHistoryView
3. Tap for details in MCPRequestDetailView
```

---

## Common Tasks

### Adding a New iOS View

1. Create file in `ios/Fletcher/Fletcher/UI/`
2. Import SwiftUI and required dependencies
3. Use `@EnvironmentObject` for shared state
4. Add to navigation in `MainView.swift` if needed
5. Test on device (Simulator has limited location features)

### Adding a New Server Endpoint

1. Create schema validation with Zod
2. Add route handler in `server/src/routes/`
3. Import in `server/src/index.ts`
4. Register with `server.register()`
5. Update TDD documentation
6. Update changelog

### Adding a New Database Column

1. Update `server/src/db/schema.sql`
2. Create migration script if data exists
3. Update TypeScript types
4. Update model functions
5. Test locally before deploying

### Debugging Sync Issues

1. Check `SyncStatusView` in iOS app
2. Review `lastSyncError` message
3. Check server logs for validation errors
4. Verify API key in Keychain
5. Check network connectivity
6. Try "Resync All Data" if server was wiped

### Debugging MCP Connection

1. Check token expiry in `MCPConnectionView`
2. Verify token format starts with `mcp_`
3. Check server logs for validation errors
4. Test `/sse` endpoint manually with curl
5. Review `access_logs` table for failed requests
6. Check Claude Desktop logs

---

## Testing

### iOS Testing

**Framework:** XCTest

**Test Files:**
- `ios/Fletcher/FletcherTests/LocationStoreTests.swift`

**Running Tests:**
```bash
# Via Xcode
xcodebuild test -scheme Fletcher

# Or use Xcode UI: Cmd+U
```

**Test Coverage:**
- ✅ Retention cleanup logic
- ✅ Indefinite retention (-1 days)
- ✅ Date calculation and filtering
- ⚠️ Limited coverage (expand recommended)

### Server Testing

**Status:** No automated tests currently

**Manual Testing:**
```bash
# Health check
curl http://localhost:3000/health

# Register device
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{"user_id": "test-uuid"}'

# Upload location
curl -X POST http://localhost:3000/api/locations \
  -H "Authorization: Bearer fletch_sk_..." \
  -H "Content-Type: application/json" \
  -d '{"locations": [...]}'
```

**Test Scripts:**
- `server/debug_token.ts` - Token debugging
- `server/test_models.ts` - Model testing
- `server/migrate_types.ts` - Migration utilities

---

## Deployment

### Server Deployment (Render.com)

See `DEPLOYMENT.md` for full details.

**Quick Steps:**

1. **Push to GitHub**
   ```bash
   git push origin main
   ```

2. **Create Web Service on Render**
   - Name: `fletcher-server`
   - Root Directory: `server`
   - Environment: Node
   - Build Command: `npm install && npm run build`
   - Start Command: `npm start`

3. **Create PostgreSQL Database**
   - Name: `fletcher-db`
   - Region: Same as web service
   - Copy Internal Database URL

4. **Configure Environment Variables**
   ```
   DATABASE_URL=postgres://...
   API_SECRET_KEY=<random-string>
   NODE_ENV=production
   PORT=3000
   ```

5. **Initialize Database**
   ```bash
   psql "EXTERNAL_URL" -f src/db/schema.sql
   ```

6. **Verify Deployment**
   ```bash
   curl https://<your-app>.onrender.com/health
   # Should return: {"status":"ok"}
   ```

7. **Update iOS App**
   - Settings → Advanced → Server URL
   - Enter: `https://<your-app>.onrender.com`

### iOS Deployment (App Store)

1. **Update Version** (see Version Bumping workflow)
2. **Archive Build** in Xcode
3. **Upload to App Store Connect**
4. **Submit for Review**

---

## Important Constraints

### What to AVOID

**iOS:**
- ❌ NEVER store API keys in UserDefaults (use Keychain)
- ❌ NEVER commit with debug `print()` statements
- ❌ NEVER skip changelog updates
- ❌ NEVER test location features only in Simulator (use device)
- ❌ NEVER force-unwrap optionals (`!`) without good reason
- ❌ NEVER block the main thread with heavy operations

**Server:**
- ❌ NEVER skip MCP token validation on requests
- ❌ NEVER expose sensitive data in logs
- ❌ NEVER use string interpolation in SQL queries (use parameters)
- ❌ NEVER skip input validation with Zod
- ❌ NEVER commit `.env` files (use `.env.example`)
- ❌ NEVER drop tables in production schema

**Git:**
- ❌ NEVER push to `main` without PR review
- ❌ NEVER skip changelog updates before pushing
- ❌ NEVER use non-descriptive commit messages
- ❌ NEVER push branches without `claude/` prefix (will fail)

### Security Best Practices

**Authentication:**
- API keys: `fletch_sk_<random>` format (hashed in DB)
- MCP tokens: `mcp_<random>` format (expires in 90 days)
- All tokens generated with crypto.randomBytes(32)

**Rate Limiting:**
- Enabled on all routes
- Default: 100 requests per minute per IP

**CORS:**
- Configured via `CORS_ORIGIN` environment variable
- Default: Allow all origins in development

**Data Minimization:**
- Only store: latitude, longitude, accuracy, timestamp
- No PII collected (no names, emails, phone numbers)

**Transport Security:**
- HTTPS enforced in production
- `NSAllowsArbitraryLoads` only for local development

---

## Troubleshooting

### Common Issues

**iOS: "Sync Failed: Invalid API Key"**
- Solution: App will auto-register on next launch
- Check: Keychain contains valid `apiKey`
- Verify: Server URL is correct

**iOS: "No Location Updates"**
- Solution: Check location permissions (Settings → Privacy → Location)
- Verify: Background Location is enabled
- Check: Device has good GPS signal (not indoors)

**Server: "Database connection failed"**
- Solution: Verify `DATABASE_URL` in `.env`
- Check: PostgreSQL service is running
- Verify: PostGIS extension is enabled

**Server: "MCP connection timeout"**
- Solution: Check token validity (not expired/revoked)
- Verify: SSE endpoint is accessible
- Check: CORS configuration

**Build: "Multiple commands produce Info.plist"**
- Solution: Check Xcode build settings
- Verify: Only one `Info.plist` target membership

### Debugging Tools

**iOS:**
- Xcode Console: View `print()` statements
- Instruments: Profile performance and memory
- Network Link Conditioner: Test offline behavior
- Xcode Debugger: Breakpoints and variable inspection

**Server:**
- Fastify Logger: Set `LOG_LEVEL=debug` in `.env`
- PostgreSQL Logs: Check database logs for query errors
- curl: Test endpoints manually
- Render Logs: View production logs in dashboard

### Log Locations

**iOS:**
- Xcode Console (Cmd+Shift+C)
- Device Console (via Devices & Simulators)

**Server:**
- Development: stdout (terminal)
- Production: Render logs dashboard
- Database: PostgreSQL logs

---

## Quick Reference

### Key Files

| File | Purpose | Lines |
|------|---------|-------|
| `ios/Fletcher/Fletcher/Services/APIClient.swift` | HTTP client | 434 |
| `server/src/mcp/index.ts` | MCP server | 386 |
| `server/src/routes/mobile.ts` | Mobile API | 190 |
| `server/src/index.ts` | Server entry | 167 |
| `ios/Fletcher/Fletcher/UI/MCPConnectionView.swift` | Token management | 232 |
| `server/src/models/location.ts` | Location queries | 215 |

### Key Constants

**iOS (`AppConstants.swift`):**
- `Sync.batchSize`: 50 locations
- `Sync.timerInterval`: 300 seconds (5 minutes)
- `defaultRetentionDays`: 30 days

**Server:**
- `MAX_BATCH_SIZE`: 100 locations
- `MAX_LOCATIONS_LIMIT`: 10,000 locations
- `MCP_TOKEN_EXPIRY`: 90 days
- `TOKEN_CLEANUP_DAYS`: 30 days (soft delete)

### Environment Variables

**Server `.env`:**
```bash
PORT=3000
DATABASE_URL=postgres://user:password@localhost:5432/fletcher
API_SECRET_KEY=your-secret-key-here
NODE_ENV=development
BASE_URL=http://localhost:3000
CORS_ORIGIN=http://localhost:3000
LOG_LEVEL=info
```

### API Endpoints Summary

**Mobile App API:**
- `POST /api/register` - Register device
- `POST /api/locations` - Upload locations
- `GET /api/locations` - Fetch history
- `GET /api/privacy-settings` - Get settings
- `PATCH /api/privacy-settings` - Update settings
- `DELETE /api/locations/:id` - Delete location

**MCP Management API:**
- `POST /api/mcp/generate-token` - Generate MCP token
- `GET /api/mcp/tokens` - List tokens
- `DELETE /api/mcp/tokens/:id` - Revoke token
- `GET /api/access-logs` - Get request history

**MCP Server:**
- `GET /sse` - SSE connection
- `POST /messages` - MCP messages

**Health & Status:**
- `GET /health` - Health check
- `GET /status/` - Statistics

### MCP Resources & Tools

**Resources:**
- `fletcher://location/current` - Current location GeoJSON
- `fletcher://location/history` - 24h history FeatureCollection

**Tools:**
- `get_current_location()` - Current position
- `get_location_history(start_date, end_date, limit, offset, center_lat, center_lon, radius_meters)` - Advanced queries
- `get_recent_trajectory(limit)` - Movement path
- `get_frequent_locations(limit, days)` - Visit clusters

---

## Documentation References

**Primary Docs:**
- `README.md` - Project overview
- `DEPLOYMENT.md` - Deployment guide
- `artifacts/changelog.md` - **CRITICAL** - Version history
- `artifacts/tdd-fletcher-ios-app.md` - iOS technical design
- `artifacts/tdd-fletcher-server.md` - Server technical design
- `artifacts/prd-fletcher-ios-app.md` - Product requirements

**Workflows:**
- `.agent/workflows/bump_version.md` - Version protocol
- `.agent/workflows/update_and_push.md` - Git commit protocol

**Schema:**
- `server/src/db/schema.sql` - Database schema

---

## Final Notes for AI Assistants

1. **Always update `artifacts/changelog.md`** - This is the most important file to keep current
2. **Follow Conventional Commits** - Makes git history readable
3. **Test on real devices** - Simulator has limited location capabilities
4. **Never skip security** - API keys in Keychain, tokens validated, SQL parameterized
5. **Log all MCP requests** - Transparency is a core feature
6. **Use branches with `claude/` prefix** - Required for push to succeed
7. **Read TDD docs before major changes** - Understand architectural patterns
8. **Check existing patterns** - Don't reinvent, follow established conventions
9. **Document as you go** - Update relevant docs when making changes
10. **Ask before breaking changes** - Discuss architecture changes with user

---

**Remember:** Fletcher is about privacy and transparency. Every decision should align with these core values.

**Questions?** Check the TDD documents in `artifacts/` or ask the user for clarification.

---

*This document is maintained by AI assistants working on the Fletcher project. Keep it updated as the codebase evolves.*
