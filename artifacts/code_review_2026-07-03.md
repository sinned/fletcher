# Fletcher Code Review — Full-Stack Correctness & Security Pass

**Date:** 2026-07-03
**Scope:** Entire server (`server/src/`) and iOS app core (`Services`, `Storage`, `Location`, `Utilities`), schema, repo hygiene.
**Relation to prior review:** `code_review_2026-02-22.md` covered maintainability (auth duplication, dynamic imports, error taxonomy, comment debt). All of those findings remain open and are not repeated in detail here. This review focuses on correctness, privacy enforcement, and security.

## Status (updated 2026-07-06)

**Resolved** in server 2.0.1 / 2.1.0 and PR #10:
- #1 MCP privacy-settings bug (2.0.1) · #2 history_access_days enforced · #3 `enabled` flag honored · #4 per-request settings fetch (no more connect-time snapshot)
- #5 MCP tokens hashed at rest (+ non-destructive migration) · #6 `?token=` redacted from logs · #7 `routes/locations.ts` deleted · #8 credential-leaking debug log removed · #9 global rate limiting
- #13 date/timezone validation · #15 register route match · #16 dev junk removed · #17 `API_SECRET_KEY` dropped · #19 CORS fail-closed · #20 `/status` counts removed

**Still open** (need an iOS release or larger refactor): #10 duplicate-location constraint, #11 LocationStore data race, #12 token-expiry doc mismatch, #14 409 re-register orphaning, #18 ATS scope, #21 mobile GET bypasses models, #22 auth-hook duplication / dynamic imports, #23 test suite.

---

## P0 — Privacy features that don't actually work

### 1. Privacy settings are silently ignored by the MCP server
`mcp/index.ts:60-61` reads `privacy?.privacy_settings?.precision_level`, but `getPrivacySettings()` (`models/user.ts:75-86`) returns a **flattened** object (`{...row.privacy_settings, retention_days}`). `privacy.privacy_settings` is always `undefined`, so:
- `precision_level` is always `'medium'` — a user who chose `low` (~1km) shares ~100m coordinates; a user who chose `high` gets silently degraded.
- `historyDays` is always 7 regardless of setting.

**Fix:** read `privacy?.precision_level` / `privacy?.history_access_days` directly. Add a regression test.

### 2. `history_access_days` is not enforced for MCP tools
Only the `fletcher://location/history` *resource* clamps its range. `get_location_history` passes arbitrary `start_date`/`end_date` straight to SQL — the "history access" privacy limit does not restrict tool queries at all (the code even notes "Privacy policy checks can be applied here if needed"). **Fix:** clamp `start` to `NOW() - history_access_days` in the tool handler (and in radius queries).

### 3. `privacy_settings.enabled` is never checked
The flag is settable via `PATCH /api/privacy-settings` and shown in the app, but no server code reads it. Disabling assistant access does nothing. **Fix:** check it in the `/sse` handler and in `validateTokenForRequest()`.

### 4. Settings are snapshotted at SSE connection time
`precision`/`historyDays` are captured once when the assistant connects. Long-lived sessions keep stale settings after the user tightens privacy (token *revocation* is correctly rechecked per request; settings are not). **Fix:** re-fetch settings inside each tool handler (they're one indexed-PK query).

## P0 — Security

### 5. MCP tokens stored in plaintext
`assistant_connections.mcp_token` holds the raw token (`models/auth.ts` inserts and compares raw; `listMCPTokens` builds previews from it). API keys are correctly SHA-256-hashed; MCP tokens — which grant live location access — are not. A DB leak exposes every active token. **Fix:** store `sha256(token)`, look up by hash (constant-time equality via unique index), keep a stored `token_preview` column for the UI list.

### 6. Token accepted via URL query parameter on `/sse`
`?token=mcp_...` ends up in access logs, proxy logs, and browser history. If some MCP clients can't send headers, at minimum note the risk; otherwise remove the query-param path.

### 7. `routes/locations.ts` is an unauthenticated auth-bypass waiting to be registered
It trusts a client-supplied `X-User-Id` header with no API key check. It is currently dead code (never registered in `index.ts`), but one `server.register(locationRoutes)` away from letting anyone write/delete any user's locations. **Fix: delete the file.**

### 8. Credential leakage in logs
- `models/auth.ts:50-56`: on every failed validation, runs an extra debug query and logs token prefix + expiry details — remove the debug block (it also doubles DB load on invalid-token storms).
- iOS `APIClient.swift:302`: `print("Registered with API Key: \(res.api_key)")` writes the credential to the device console. Remove. (~20 `print()` calls remain in the app despite the repo rule.)

### 9. No rate limiting where it matters
`@fastify/rate-limit` is applied only to `/api/mcp/*` (10 / 15 min). `POST /api/register` (unauthenticated account creation), `POST /api/locations`, `/sse` (expensive: DB lookups + per-connection McpServer), and `/messages` have none. Older docs claimed a global 100/min limiter that does not exist. **Fix:** register the limiter globally with sensible per-route overrides.

## P1 — Correctness

### 10. Duplicate location rows are unavoidable by design
No unique constraint on `(user_id, timestamp)` and no idempotency:
- iOS `syncAllLocations()`'s `isSyncing` guard is racy (checked before the `MainActor` write), and sync is triggered concurrently by timer, visit events, and manual buttons → same batch can upload twice.
- "Resync All Data" (`markAllAsUnsynced`) re-uploads everything.
- Client-side dedup on download (`mergeLocations`, 1ms tolerance) can't work: upload uses `JSONEncoder.dateEncodingStrategy = .iso8601`, which **truncates milliseconds**, so a downloaded point differs from its local original by up to 999ms → resync also duplicates points locally.

**Fix:** add `UNIQUE (user_id, timestamp)` (or upload the client UUID and make it the PK) with `ON CONFLICT DO NOTHING`; widen the client merge tolerance to ≥1s; make the `isSyncing` guard actor-safe.

### 11. iOS `LocationStore` has a data race
`save()` encodes `self.locations` on a background queue while the main thread mutates the same array (`addLocation`/`markSynced`/`mergeLocations`). Swift arrays are not thread-safe: possible crash or corrupt `locations.json` (the single source of local truth). **Fix:** snapshot first (`let snapshot = locations` on the caller's thread, encode the snapshot), or serialize all access through one queue/actor.

### 12. MCP token expiry: code says 1 year, docs/UI say 90 days
`createMCPToken` sets `expiresAt.setFullYear(+1)` (`models/auth.ts:7`). Decide which is intended and align code + docs + app copy.

### 13. `get_location_history` date-range bugs
- `end_date: "2026-01-04"` parses to start-of-day, so the end day is excluded; `start_date == end_date` returns nothing. Fix: `endOf('day')` when the input is date-only.
- No timezone validation: an invalid IANA name yields a Luxon invalid DateTime → `Invalid Date` → Postgres error. Validate with `IANAZone.isValidZone` and return a clean tool error.
- `limit` is clamped high (`>1000`) but not low — a negative limit reaches SQL and errors.

### 14. Auto-re-register on 409 orphans server data
If the Keychain key is lost but `userId` survives, registration 409s and the app generates a **new UUID**. All prior server rows belong to an ID nobody controls: unreachable, undeletable by the user, and retained forever if `retention_days = -1`. For a privacy-first product this is the worst failure mode — data the user can no longer see or delete. **Fix (minimum):** an authenticated re-key endpoint is impossible without the old key, so consider deleting orphaned users after N days of no valid-key activity, and surface the identity change in the app.

### 15. `/api/register` exemption matches on exact URL
`mobile.ts:13` compares `request.url === '/api/register'` — a query string (`/api/register?src=x`) breaks registration with a 401. The `startsWith('/auth')`/`startsWith('/mcp')` branches are dead (URLs here always start with `/api`). Use `req.routeOptions.url` or match the path only.

## P2 — Hygiene / operational

16. **Committed dev junk in `server/`**: `server_v2_1.log` (a runtime log — no secrets found, but logs must not be tracked; `.gitignore` only covers `npm-debug.log`), `debug_token.ts`, `repro_tokens.sh`, `test_models.ts`, `test-access-logs.js`, `migrate_*.ts`, `verify_*.sh`, `clean_db.sql`. Move to `server/scripts/` or delete; add `*.log` to `.gitignore`.
17. **`API_SECRET_KEY`** in `.env.example` and docs is read nowhere. Remove it (or implement whatever it was meant for).
18. **`NSAllowsArbitraryLoads = true`** globally in `Info.plist` disables ATS for all connections and invites App Store review questions. Scope it to `NSExceptionDomains` for `localhost`.
19. **CORS default** is `origin: true` + `credentials: true` (reflects any origin) when `CORS_ORIGIN` is unset. Fail closed in production.
20. **`/status/`** publicly exposes user and location counts. Gate it or drop the counts.
21. **`GET /api/locations`** query in `mobile.ts` bypasses the models layer (the only route that does) — move to `models/location.ts`.
22. Prior review items still open: auth hook duplicated in 3 plugins with per-request `await import(...)`; broad `400` catch blocks hiding 5xx; conversational LLM comment debt in `mcp_api.ts`, `auth.ts`, `mcp/index.ts`, `index.ts` (incl. the dynamic-import shutdown hack — export a `closeDb()`).
23. **No server tests, no CI.** Highest-value first tests: privacy-setting enforcement in MCP handlers (would have caught #1–#3), auth hooks, and register/409 flow.

---

## Suggested order of attack

1. **Privacy enforcement batch (#1–#4)** — small diffs, big product-integrity impact; add tests.
2. **Token security batch (#5, #6, #8)** — hash MCP tokens (needs a one-time migration invalidating existing tokens; acceptable pre-scale), strip debug logging.
3. **Delete `routes/locations.ts` and repo junk (#7, #16, #17).**
4. **Sync integrity (#10, #11)** — DB unique constraint + iOS threading fix.
5. **Polish (#9, #12–#15, #18–#21)** alongside the still-open 2026-02-22 refactors.
