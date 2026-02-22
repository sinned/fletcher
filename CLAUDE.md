# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fletcher is a privacy-first location tracking system with:
- **iOS App** (SwiftUI): Background location tracking, local storage, cloud sync
- **Node.js Server** (Fastify + PostgreSQL/PostGIS): REST API + MCP server for AI assistant integration

Current versions: iOS v1.6.2 | Server v2.0.0

## Build & Run Commands

### Server (in `server/` directory)
```bash
npm install          # Install dependencies
npm run build        # Compile TypeScript to dist/
npm run dev          # Development with hot reload (nodemon)
npm start            # Production: node dist/index.js
```

### iOS
- Open `ios/Fletcher/Fletcher.xcodeproj` in Xcode
- Build: Cmd+B, Run: Cmd+R (use real device for location features)
- Test: `xcodebuild test -scheme Fletcher` or Cmd+U in Xcode

### Database Setup
```bash
createdb fletcher
psql fletcher -c "CREATE EXTENSION postgis;"
psql fletcher < server/src/db/schema.sql
```

## Architecture

```
iOS App (SwiftUI) ──HTTPS──▶ Fastify Server ◀──MCP/SSE── AI Assistants
                                   │
                                   ▼
                            PostgreSQL + PostGIS
```

**iOS**: MVVM pattern with singleton services (`LocationStore.shared`, `APIClient.shared`)
**Server**: Modular routes (`routes/`), data access layer (`models/`), isolated MCP server (`mcp/`)

## Key Files

| File | Purpose |
|------|---------|
| `server/src/mcp/index.ts` | MCP server implementation (SSE protocol) |
| `server/src/routes/mobile.ts` | Mobile app REST API |
| `ios/.../Services/APIClient.swift` | HTTP client + sync logic |
| `ios/.../Storage/LocationStore.swift` | Local JSON persistence |
| `server/src/db/schema.sql` | Database schema |

## Git Workflow

**Branch naming**: `claude/<description>-<sessionId>` (enforced, will fail without this prefix)

**Commit format**: Conventional Commits
```
feat(ios): add new feature
fix(server): fix bug
chore: bump version
```

**Scopes**: ios, server, mcp, security, ui

## Critical Requirements

1. **Always update `CHANGELOG.md`** with timestamps when making changes
2. **Use Keychain for API keys** (iOS) - never UserDefaults
3. **Parameterized SQL queries** - never string interpolation
4. **Validate MCP tokens on every request**
5. **Test location features on real devices** - Simulator has limited support
6. **Remove debug print statements** before committing

## Environment Variables (Server)

```bash
PORT=3000
DATABASE_URL=postgres://user:password@localhost:5432/fletcher
API_SECRET_KEY=<secret>
NODE_ENV=development
```

## For Detailed Information

See **AGENTS.md** for comprehensive documentation including:
- Complete directory structure with line counts
- All API endpoints and MCP tools
- Version bumping workflow (`.agent/workflows/bump_version.md`)
- Commit/push protocol (`.agent/workflows/update_and_push.md`)
- Troubleshooting guide
- Security best practices

See **artifacts/** for technical design documents and changelog history.
