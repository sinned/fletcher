# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fletcher is a privacy-first location tracking system that lets AI assistants access location data via MCP:
- **iOS App** (`ios/`, SwiftUI): Background location tracking, local JSON storage, cloud sync
- **Node.js Server** (`server/`, Fastify + PostgreSQL/PostGIS): REST API for the app + MCP server (SSE) for AI assistants

Version sources of truth: iOS = `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/Fletcher/Fletcher.xcodeproj/project.pbxproj`; Server = `version` in `server/package.json`.

## Build & Run Commands

### Server (in `server/` directory)
```bash
npm install          # Install dependencies
npm run build        # tsc + copies schema.sql into dist/db/
npm run dev          # Development with hot reload (nodemon + ts-node)
npm start            # Production: node dist/index.js
```
There are **no automated server tests** (`npm test` is a stub). Verify manually, e.g. `curl http://localhost:3000/health`.

### iOS
- Open `ios/Fletcher/Fletcher.xcodeproj` in Xcode; build Cmd+B, run Cmd+R
- **Test location features on a real device** — Simulator has poor "Always" location support
- Tests (XCTest, one suite: `FletcherTests/LocationStoreTests.swift`):
```bash
xcodebuild test -scheme Fletcher -destination 'platform=iOS Simulator,name=iPhone 16'
# Single test:
xcodebuild test -scheme Fletcher -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FletcherTests/LocationStoreTests/testName
```

### Database Setup
```bash
createdb fletcher
psql fletcher -c "CREATE EXTENSION postgis;"
psql fletcher < server/src/db/schema.sql
```
Schema changes go in `server/src/db/schema.sql` (plus a migration script if data exists). Never drop tables in production schema.

## Architecture

```
iOS App (SwiftUI) ──HTTPS/REST──▶ Fastify Server ◀──MCP over SSE── AI Assistants
                                       │
                                       ▼
                                PostgreSQL + PostGIS
```

### Server (`server/src/`)
- `index.ts` — entry point; registers CORS, rate limiting, static files, routes, and the MCP server
- `routes/` — HTTP handlers: `mobile.ts` (app API), `mcp_api.ts` (token management), `access_logs.ts`, `locations.ts`
- `models/` — data access layer (`user.ts`, `location.ts`, `auth.ts`, `access_log.ts`); routes never query the DB directly
- `mcp/index.ts` — MCP server: `GET /sse` opens the SSE transport, `POST /messages` receives MCP messages; sessions tracked in-memory per token. Tools: `get_latest_location`, `get_location_history`, `get_recent_trajectory`, `get_frequent_locations` — all accept an optional `timezone` param (Luxon, default `America/Los_Angeles`)
- `cron.ts` — daily retention cleanup (per-user `retention_days`; `-1` = keep forever)

### Two-tier auth (both formats generated in `utils/crypto.ts`, hashed in DB)
1. **Device API keys** (`fletch_sk_...`): iOS app auth via `Authorization: Bearer`. App auto-registers and stores the key in Keychain; on a 401 it deletes the key and re-registers.
2. **MCP tokens** (`mcp_...`, 90-day expiry): generated in the app, shown once, pasted into the AI assistant config. **Validated on every MCP request**, not just at connection, and **every access is logged** to `access_logs` — the app polls this to show users a request history (transparency is a core product feature).

### iOS (`ios/Fletcher/Fletcher/`) — MVVM with singleton services
- `Location/BackgroundLocationService.swift` — CoreLocation background tracking
- `Storage/LocationStore.swift` (`LocationStore.shared`) — local JSON persistence; points carry a `synced` flag
- `Services/APIClient.swift` (`APIClient.shared`) — HTTP client + batch sync (timer-driven, batches of 50; server accepts max 100)
- `UI/` — SwiftUI views; `MainView.swift` owns tab navigation
- `Utilities/KeychainManager.swift` — the only place API keys are stored; `AppConstants.swift` — sync/retention constants

Data flow: CLLocation → LocationPoint (`synced=false`) → LocationStore JSON → timer fires → APIClient uploads batch → mark synced. Server validates the API key, validates the body with Zod, batch-inserts into PostGIS.

## Git Workflow

**Branch naming**: `claude/<description>-<sessionId>` — enforced; pushes without this prefix + matching session ID fail with 403.

**Commit format**: Conventional Commits — types `feat|fix|docs|chore|refactor|config`, scopes `ios|server|mcp|security|ui`:
```
feat(ios): add new feature
fix(server): fix bug
chore: bump version to vX.Y.Z
```

**Version bumps** (see `.agent/workflows/bump_version.md`): update `project.pbxproj` (iOS) or `package.json` (server), add a changelog section, verify the splash screen and Settings footer show the new version.

## Critical Requirements

1. **Always update the root `CHANGELOG.md`** with timestamps when making changes (canonical since "chore: move changelog to root"; `artifacts/changelog.md` and some workflow docs still reference the old location)
2. **Keychain for API keys** (iOS) — never UserDefaults
3. **Parameterized SQL** — never string interpolation; validate all input with Zod
4. **Validate MCP tokens on every request** and log every MCP access to `access_logs`
5. **Remove debug `print()` statements** before committing
6. Never commit `.env` (use `server/.env.example` as the template)

## Environment Variables (Server `.env`)

```bash
PORT=3000
DATABASE_URL=postgres://user:password@localhost:5432/fletcher
NODE_ENV=development
BASE_URL=http://localhost:3000
CORS_ORIGIN=http://localhost:3000
LOG_LEVEL=info
```

## For Detailed Information

- **AGENTS.md** — full endpoint/tool listings, code conventions, troubleshooting (some details are stale; trust the code over the doc)
- **`.agent/workflows/`** — version bump and commit/push protocols
- **`artifacts/`** — PRD, technical design docs (iOS + server), server walkthrough
- **DEPLOYMENT.md** — Render.com deployment guide
