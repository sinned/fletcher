# AGENTS.md - AI Assistant Guide for Fletcher

**Last Updated:** 2026-07-03
**Repository:** Fletcher - Privacy-first location tracking app with MCP integration

Version sources of truth (do not trust docs for versions):
- iOS: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/Fletcher/Fletcher.xcodeproj/project.pbxproj`
- Server: `version` in `server/package.json`

---

## Project Overview

Fletcher is a **privacy-first location tracking system** that enables AI assistants to provide location-aware assistance through the Model Context Protocol (MCP):

- **iOS Client**: Native SwiftUI app for background location tracking and data visualization
- **Backend Server**: Node.js/Fastify server with PostgreSQL/PostGIS for geospatial storage and MCP integration
- **MCP Integration**: Server-Sent Events (SSE) transport for AI assistant access

### Core Principles

1. **Privacy First**: User data is isolated, access is logged, deletion is immediate
2. **Transparency**: All AI assistant requests are logged and visible to users
3. **Simplicity**: MVP-focused, defer complexity, clear separation of concerns
4. **Security by Default**: API keys, token validation, encrypted storage

---

## Architecture

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│   iOS App   │────────▶│  Fletcher Server │◀────────│ AI Assistant│
│  (Client)   │  HTTPS  │  REST + MCP/SSE  │   SSE   │             │
└─────────────┘         └──────────────────┘         └─────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │   PostgreSQL    │
                        │   + PostGIS     │
                        └─────────────────┘
```

### iOS (MVVM with singleton services)

- **Views**: SwiftUI, in `UI/`; `MainView.swift` owns tab navigation
- **Services**: singletons — `LocationStore.shared` (local JSON persistence), `APIClient.shared` (HTTP + sync), `BackgroundLocationService` (CoreLocation)
- **Models**: `LocationPoint`, `MCPToken`, `MCPRequest`
- Tracking uses **significant-location-change + visit monitoring** (battery-optimized), not continuous updates

### Server (modular Fastify plugins)

- `routes/` — HTTP endpoint handlers; each plugin carries its own auth hook (Fastify hooks are encapsulated per plugin)
- `models/` — data access layer; routes should not query the DB directly (one exception currently in `mobile.ts` GET /locations)
- `mcp/index.ts` — MCP server; a new `McpServer` instance is created per SSE connection, sessions tracked in an in-memory `Map` keyed by sessionId
- `cron.ts` — daily retention cleanup + expired-token cleanup (in-process `setInterval`, not a system cron)
- `db/index.ts` — pg `Pool`; `initDb()` re-applies `schema.sql` on every boot (idempotent `IF NOT EXISTS` DDL)

### Authentication (two tiers, both generated in `utils/crypto.ts`)

1. **Device API keys** (`fletch_sk_<base64url>`): SHA-256 **hashed** in `users.api_key`. Returned in plaintext exactly once at `POST /api/register`. iOS stores it in Keychain; on 401 it deletes the key and auto-re-registers.
2. **MCP tokens** (`mcp_<base64url>`): stored **in plaintext** in `assistant_connections.mcp_token` (known gap — see review artifacts). Expiry is **1 year** in code (`models/auth.ts`), despite older docs saying 90 days. Validated on **every** MCP request (connection, message, and inside each tool/resource handler); revocation takes effect mid-session. Every access is logged to `access_logs` — the app polls this for the user-facing request history. This transparency is a core product feature, not incidental.

---

## Directory Structure

```
fletcher/
├── ios/Fletcher/
│   ├── Fletcher/
│   │   ├── FletcherApp.swift
│   │   ├── Models/          LocationPoint, MCPToken, MCPRequest
│   │   ├── Services/        APIClient.swift
│   │   ├── Location/        BackgroundLocationService.swift
│   │   ├── Storage/         LocationStore.swift
│   │   ├── UI/              MainView, HistoryView, HistoryMapView, MCPConnectionView,
│   │   │                    MCPRequestHistoryView, MCPRequestDetailView, SettingsView,
│   │   │                    SyncStatusView, SplashScreen
│   │   ├── Utilities/       KeychainManager, AppConstants, Bundle+Version,
│   │   │                    ISO8601DateFormatter+Fletcher
│   │   └── Info.plist
│   └── FletcherTests/       LocationStoreTests.swift (only test suite)
│
├── server/
│   ├── src/
│   │   ├── index.ts         Server entry: CORS, static, route registration, /health, /status/
│   │   ├── cron.ts          Retention + token cleanup jobs
│   │   ├── db/              index.ts (pool), schema.sql
│   │   ├── models/          user.ts, location.ts, auth.ts, access_log.ts
│   │   ├── routes/          mobile.ts, mcp_api.ts, access_logs.ts,
│   │   │                    locations.ts (UNREGISTERED dead code — do not register; it has no auth)
│   │   ├── mcp/index.ts     MCP server (SSE at /sse, messages at /messages)
│   │   └── utils/crypto.ts  Key/token generation + hashing
│   ├── public/              Landing page, privacy.html, terms.html
│   └── (root)               Assorted debug/verify scripts (debug_token.ts, verify_*.sh, ...) — dev-only
│
├── artifacts/               PRD, TDDs, walkthroughs, code review reports
├── .agent/workflows/        bump_version.md, update_and_push.md
├── CHANGELOG.md             ← canonical changelog (root). artifacts/changelog.md is a stale duplicate.
├── README.md, DEPLOYMENT.md, CLAUDE.md
```

---

## Development Workflows

### Build & Run

**Server** (in `server/`): `npm install`, `npm run dev` (nodemon), `npm run build` (tsc + copies schema.sql to dist/db/), `npm start`. **There are no automated server tests** — `npm test` is a stub. Verify manually (`curl localhost:3000/health`).

**iOS**: open `ios/Fletcher/Fletcher.xcodeproj`. Test location features on a **real device** — Simulator handles "Always" authorization and background updates poorly.

```bash
xcodebuild test -scheme Fletcher -destination 'platform=iOS Simulator,name=iPhone 16'
```

**Database**: `createdb fletcher && psql fletcher -c "CREATE EXTENSION postgis;" && psql fletcher < server/src/db/schema.sql`

### Git Commit Convention

Conventional Commits: types `feat|fix|docs|chore|refactor|config`, scopes `ios|server|mcp|security|ui`.

```
feat(ios): add tappable detail view for MCP requests
fix(security): validate MCP token on every request
chore: bump version to v1.6.3
```

### Branch Naming

Branches MUST start with `claude/` and end with the matching session ID (`claude/<description>-<sessionId>`), otherwise push fails with 403. This applies to all AI coding assistants regardless of platform.

### Version Bumping (`.agent/workflows/bump_version.md`)

1. iOS: update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.pbxproj` (both build configs). Server: `package.json`.
2. Add a section to the root `CHANGELOG.md`, moving Unreleased items under it.
3. Verify: Splash screen and Settings footer show the new version.
4. `git commit -m "chore: bump version to vX.Y.Z"`

### Before Every Push (`.agent/workflows/update_and_push.md`)

1. Update root `CHANGELOG.md` with a timestamp — never skip this
2. Remove temporary debug `print()` statements; verify the build passes
3. `git add . && git commit && git push -u origin <branch>` (retry network failures with backoff)

---

## Key Behaviors & Constants (verified against code)

**iOS (`AppConstants.swift` and call sites):**
- Sync batch size: **100** (matches server max); sync timer: **300s**; default retention: 30 days
- Local persistence: single `locations.json` in Documents, written with `.completeFileProtectionUntilFirstUserAuthentication` (works when device is locked after first unlock)
- Keychain items use `kSecAttrAccessibleAfterFirstUnlock` so background sync can read the API key
- Local retention cleanup runs on load/add via `LocationStore.cleanup()`, driven by `@AppStorage("retentionDays")`; `-1` = keep forever
- Sync loop: `getUnsynced()` → POST batches of 100 → `markSynced()`; stops on first error. On 401: delete key, re-register, throw
- Re-registration on 409 generates a **new user UUID** — server-side data under the old ID becomes orphaned (known gap)

**Server:**
- `POST /api/locations` accepts max **100** points per request (Zod `.max(100)`); batch INSERT in a transaction
- `GET /api/locations` limit 1–10000, `before` cursor pagination
- MCP `get_location_history` limit capped at 1000; access-log queries capped at 500
- MCP token expiry: **1 year**; expired tokens hard-deleted by cron; revoked rows deleted 30 days after revocation
- Rate limiting exists **only** on `/api/mcp/*` (10 req / 15 min / IP). No global limiter (docs previously claiming 100/min were wrong)
- Retention cleanup: daily `DELETE ... WHERE timestamp < NOW() - retention_days`; `retention_days = -1` means keep forever; `0` is rejected
- `privacy_settings` JSONB on `users`: `precision_level` (high/medium/low → full/~100m/~1km rounding), `history_access_days`, `enabled`. **Caution:** enforcement of these in the MCP path is currently buggy/incomplete — see `artifacts/code_review_2026-07-03.md` before relying on it
- `updatePrivacySettings` auto-syncs `history_access_days` when `retention_days` changes

---

## API Endpoints (verified)

**Mobile app API (`/api`, device API key auth):**
- `POST /api/register` — register device (no auth), returns api_key once; 409 if user_id exists
- `POST /api/locations` — upload batch
- `GET /api/locations` — history (`limit`, `before`)
- `DELETE /api/locations` — delete ALL user locations
- `DELETE /api/locations/:id` — delete one
- `GET|PATCH /api/privacy-settings`

**MCP management (`/api/mcp`, device API key auth, rate-limited):**
- `POST /api/mcp/generate-token` — body: `assistant_type` (claude|chatgpt|cursor|other), optional `token_name`
- `GET /api/mcp/tokens` — list (returns `token_preview`, never full token)
- `DELETE /api/mcp/tokens/:id` — revoke (soft: sets `revoked_at`)

**Access logs (`/api/access-logs`, device API key auth):**
- `GET /` — `limit`, `offset`, `assistant_type`, `start_date`, `end_date`; returns logs + pagination metadata

**MCP server (MCP token auth, via `Authorization: Bearer` or `?token=` query param):**
- `GET /sse` — SSE connection; `POST /messages?sessionId=...` — MCP messages

**Public:** `GET /health`, `GET /status/` (user/location counts), static landing/privacy/terms pages

## MCP Resources & Tools

Resources (UTC, no timezone param): `fletcher://location/current`, `fletcher://location/history` (≤24h)

Tools (all take optional `timezone`, IANA name, default `America/Los_Angeles`; timestamps returned in both local and UTC ISO 8601):
- `get_latest_location(timezone)`
- `get_location_history(start_date, end_date, timezone, limit, offset, center_lat, center_lon, radius_meters)`
- `get_recent_trajectory(limit, timezone)`
- `get_frequent_locations(limit, days, timezone)` — grid-snap clustering (~111m cells)

---

## Important Constraints

**iOS:**
- API keys go in Keychain via `KeychainManager` — NEVER UserDefaults
- No debug `print()` in commits (and never print credentials)
- Don't block the main thread; prefer async/await over completion handlers
- File naming/state management: `@StateObject` for owned state, `@EnvironmentObject` for shared, `@AppStorage` for simple prefs

**Server:**
- Parameterized SQL only — never string interpolation of values
- Validate every payload with Zod
- Validate MCP tokens on every request AND log every MCP access (transparency requirement)
- Never commit `.env`; `server/.env.example` is the template
- Never register `routes/locations.ts` — it is legacy, unauthenticated code kept only in history; prefer deleting it
- File naming: `snake_case.ts`; types `PascalCase`; constants `UPPER_SNAKE_CASE`

**Git:**
- Never push to `main` without PR review
- Never skip the root `CHANGELOG.md` update

## Environment Variables (server `.env`)

```bash
PORT=3000
DATABASE_URL=postgres://user:password@localhost:5432/fletcher
NODE_ENV=development
BASE_URL=http://localhost:3000        # used in generate-token instructions
CORS_ORIGIN=http://localhost:3000     # default reflects any origin if unset
LOG_LEVEL=info
```

Note: `API_SECRET_KEY` appears in `.env.example` and older docs but is **not read anywhere in the code**.

---

## Deployment

Server deploys to Render.com (see `DEPLOYMENT.md`): root directory `server`, build `npm install && npm run build`, start `npm start`, plus a Render PostgreSQL instance with PostGIS. Initialize with `psql "EXTERNAL_URL" -f src/db/schema.sql`, verify `GET /health`. Default production URL baked into the iOS app: `https://fletcher-server.onrender.com` (user-overridable in Settings → Server URL).

iOS ships via Xcode Archive → App Store Connect.

---

## Troubleshooting

- **"Sync Failed: Invalid API Key"** — app auto-recovers: deletes Keychain key, re-registers. Note this creates a new user_id if the old one 409s.
- **No location updates** — check Always permission, background modes, and that tracking uses significant-change monitoring (updates are sparse by design, ~500m granularity).
- **MCP connection fails** — check token not expired/revoked (`assistant_connections`), test `/sse` with curl, inspect `access_logs`. Server logs `[MCP]`/`[Auth]` lines for validation failures.
- **DB errors on boot** — `DATABASE_URL` correct, PostgreSQL running, PostGIS extension installed. Boot exits(1) if init fails.
- **Server logs**: dev = stdout (`LOG_LEVEL=debug` for verbose); prod = Render dashboard.

---

## Documentation Map

- Root `CHANGELOG.md` — canonical version history (**always update**)
- `CLAUDE.md` — condensed guide for Claude Code
- `artifacts/tdd-fletcher-ios-app.md`, `artifacts/tdd-fletcher-server.md`, `artifacts/prd-fletcher-ios-app.md` — design docs
- `artifacts/code_review_2026-02-22.md`, `artifacts/code_review_2026-07-03.md` — open review findings; check before "fixing" something already catalogued
- `.agent/workflows/` — version bump and push protocols

**Remember:** Fletcher is about privacy and transparency. Every decision should align with these core values. When docs and code disagree, the code is the source of truth — and update the docs.
