# Changelog

## [Unreleased]

## [1.6.8] - 2026-07-06
### Changed
- **iOS**: Default server domain is now `https://fletcher.to`. Existing installs on the legacy `fletcher-server.onrender.com` host are migrated automatically on launch (same backend/database, so stored credentials keep working). Centralized the server URL in `AppConstants.Server` (2026-07-06)
- **iOS/Security**: Scoped down App Transport Security — replaced the global `NSAllowsArbitraryLoads` with a localhost exception plus `NSAllowsLocalNetworking`, so public servers must use HTTPS while local/self-hosted dev over HTTP still works (2026-07-06)

### Fixed
- **iOS**: Fixed a data race in `LocationStore.save()` — the locations array was encoded on a background queue while the main thread mutated it, which could crash or corrupt `locations.json`. The array is now snapshotted on the calling thread before encoding (2026-07-06)

## [Server 2.1.0] - 2026-07-06 — Security hardening
Addresses the open findings in `artifacts/code_review_2026-07-03.md` before the repo goes public.

### Security
- **MCP tokens are now hashed at rest** (sha256). A one-time, idempotent, non-destructive migration in `schema.sql` hashes the existing tokens in place and backfills a display-only `token_preview` column — users' current tokens keep working. The plaintext token is shown once at creation and never stored.
- **Stopped leaking credentials in logs**: removed the debug query/log in `validateMCPToken` that printed token + expiry on every failed validation, and the request logger now redacts a `?token=` query param from URLs.
- **Global rate limiting** on all routes (120/min/IP), with a stricter 10 per 15 min on MCP token generation. Previously only the MCP management routes were limited — `register`, `locations`, and `/sse` had none.
- **CORS fails closed in production** when `CORS_ORIGIN` is unset (was reflecting any origin with credentials).
- **`/status/` no longer exposes aggregate user/location counts.**
- Removed the unused `API_SECRET_KEY` from `.env.example`.

### Privacy
- The MCP tools now **enforce `history_access_days`** (assistants can't read further back than the user's window) and **honor the `enabled` switch** (a disabled account shares nothing, at connect and per request).
- Privacy settings are **re-fetched on every request** instead of snapshotted at connection, so tightening precision/history or disabling access takes effect mid-session.

### Fixed
- `get_location_history`: validate the IANA timezone and date inputs (invalid values now return a tool error instead of crashing into SQL), treat a bare `end_date` as end-of-day (same-day ranges work), and clamp `limit`/`offset` to sane bounds.
- `/api/register` auth exemption now matches on path only, so a query string can't turn it into a 401.

## [Repo & Web] - 2026-07-06 — open-source prep
### Changed
- **Server**: MCP connection instructions now use `https://fletcher.to` as the production SSE base URL fallback (was a stale `mcp.fletcher.app`); still overridable via the `BASE_URL` env var (2026-07-06)
- **Web**: Added a source-code link (footer + self-host callout) to the landing page ahead of open-sourcing the repo (2026-07-06)

### Removed
- **Server**: Deleted `src/routes/locations.ts` — unregistered but unauthenticated route that trusted a client-supplied `X-User-Id`; removed ahead of making the repo public (2026-07-06)
- **Repo**: Removed committed dev scratch (runtime log, `debug_token.ts` with a hardcoded token, ad-hoc `verify_*.sh`/`migrate_*`/`clean_db.sql` scripts); added `*.log` to `.gitignore`

### Added
- **Repo**: MIT `LICENSE`; README links (site, TestFlight, license), deduped iOS setup steps, corrected API endpoint list (2026-07-06)

## [Server 2.0.1] - 2026-07-06
### Changed
- **Web**: Rewrote landing-page privacy copy to explain the actual mechanism (anonymous ID, per-token assistant access with precision control, access log, retention) and corrected the sync card's "your personal server" overclaim; added a "How your privacy actually works" section (2026-07-06)
- **Web**: Corrected the privacy policy — removed the false altitude/speed collection claim, documented the anonymous device ID, assistant token flow, access logging, hosted-vs-self-hosted data location, retention/deletion, and security posture (2026-07-06)

### Fixed
- **MCP/Privacy**: The MCP server now actually applies the user's `precision_level` and `history_access_days` settings. It previously read them through a non-existent nested field (`privacy_settings.precision_level` on an already-flattened object), so every session ran with precision "medium" and a 7-day history window regardless of the user's choice (2026-07-06)

## [1.6.6] - 2026-07-05
### Changed
- **Platform**: App Store target is now iPhone-only (`TARGETED_DEVICE_FAMILY = 1`); the iPad split-view layout was not presentable and iPad support will return once the UI is adapted (2026-07-05)

### Added
- **Dev**: DEBUG-only screenshot hooks — env vars `FLETCHER_DEMO_DATA`, `FLETCHER_START_TAB`, `FLETCHER_HISTORY_MODE`, `FLETCHER_MAP_FIT` seed demo history and preselect tabs for simulator screenshot automation; compiled out of Release (2026-07-05)

## [1.6.5] - 2026-07-03
### Fixed
- **History Map**: Fixed multi-second hang when opening the Map view with large histories (6k+ points). Points are now thinned to at most one per visible-region grid cell (recomputed when the camera settles) instead of rendering one annotation view per raw point; Start/End markers now picked by timestamp instead of array position, which flipped depending on sync order (2026-07-03)

## [1.6.4] - 2026-07-03
### Added
- **Docs**: Added `artifacts/code_review_2026-07-03.md` — full-stack correctness/security review; key findings: MCP server ignores privacy settings (flattened-object bug), plaintext MCP tokens, unregistered-but-unauthenticated `routes/locations.ts`, iOS LocationStore data race, sync duplication (2026-07-03)

### Changed
- **Version**: Bumped iOS version to 1.6.4 (build 5) to verify the local build-and-install pipeline (2026-07-03)
- **Docs**: Refreshed AGENTS.md against the actual code — corrected token expiry (1 year), rate-limit scope (/api/mcp only), sync batch size (100), removed nonexistent files/claims, documented verified endpoints and constants (2026-07-03)
- **Docs**: Rewrote CLAUDE.md — corrected stale version pins, changelog location, iOS version source (project.pbxproj), and added auth/data-flow architecture notes and test commands (2026-07-03)
- **Docs**: Renamed CLAUDE.md to AGENTS.md and generalized for all AI coding assistants (2025-12-24 01:23)

## [1.6.3] - 2026-02-21
### Fixed
- **History**: Fixed background location history saving failing when the device is locked by updating file protection level.
- **Settings**: Fixed UserDefaults extraction bug for retentionDays that could cause location history to default back to 30 days unexpectedly.
- **Server**: Synced `history_access_days` with user `retention_days` updates so that MCP tools can access full history instead of defaulting to 7 days.

## [Server 2.0.0] - 2026-01-04
### Added
- **MCP**: Added timezone support to all location tools. Tools now accept an optional `timezone` parameter (default `America/Los_Angeles`).
- **MCP**: Timestamps are now returned in ISO 8601 format with the correct timezone offset.
- **MCP**: `get_location_history`, `get_latest_location`, `get_recent_trajectory`, and `get_frequent_locations` now return localized times.
- **Dependencies**: Added `luxon` for robust timezone handling.

### Changed
- **MCP**: Updated response metadata to include `timezone` and `timezone_offset`.

## [Server 1.4.1] - 2026-01-04
### Changed
- **MCP**: Renamed tool `get_current_location` to `get_latest_location` to clarify that it returns the latest synced location rather than a real-time fix.
- **Web**: Updated marketing homepage to reflect full feature set (Privacy, MCP, Transparency).
- **Web**: Updated copyright dates to 2026.

## [1.6.2] - 2026-01-04
### Fixed
- **Config**: Added `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` to `Info.plist` to resolve Simulator errors and support future media features.
- **Dev**: Fixed Xcode logging timeout by adding `IDEPreferLogStreaming=YES` to shared scheme.


## [1.6.1] - 2026-01-01
### Fixed
- **Sync**: Fixed critical bug where broken authentication (401) would not auto-recover.
- **Sync**: Added conflict handling (409) to automatically heal stuck user registrations by generating new IDs.
- **History**: "Download History" now recursively fetches ALL history from the server, fixing truncation issues.
- **Config**: Added missing Location Usage Descriptions to `Info.plist` to fix permission crashes.

## [Server 1.3.1] - 2025-12-24
### Changed
- **Web**: Updated Privacy Policy to clarify server storage and debug access.
- **Web**: Refined landing page aesthetics and moved navigation to footer.
- **Web**: Updated "Join the Beta" link to TestFlight.

## [1.5.2] - 2025-12-24
### Added
- **Settings**: Added link to Privacy Policy in the Privacy section.

## [Server 1.3.0] - 2025-12-24
### Added
- **MCP**: Enhanced request logging to capture accurate assistant type (Claude, Cursor, ChatGPT, etc.)
- **MCP**: Added response time tracking for all MCP tool and resource calls
- **API**: New endpoint `GET /api/access-logs` for fetching MCP request history with pagination and filtering
- **Transparency**: Centralized logging function with full query parameter capture

### Changed
- **Auth**: `validateMCPToken` now returns both userId and assistantType for proper tracking

## [1.5.0] - 2025-12-24
### Added
- **MCP**: New "Request History" view showing all AI assistant requests by date (00:51)
- **MCP**: Expandable request details showing query parameters and response times
- **MCP**: Added "Manage Tokens" link in Settings for better discoverability
- **UI**: Pull-to-refresh and pagination support in request history
- **Transparency**: Full visibility into what AI assistants are requesting

## [1.5.1] - 2025-12-24
### Added
- **MCP**: Tappable detail view for individual requests with full information (00:58)
- **MCP**: Color-coded response times for performance monitoring (green < 100ms, orange < 500ms, red > 500ms)
- **UI**: Request ID display for debugging

### Changed
- **UX**: Moved "Request History" from Settings to Assistants tab for better discoverability
- **UI**: Simplified request list rows - now tap to see full details instead of inline expansion
- **UI**: Shows assistant icon, location count, and response time in compact format

## [Server 1.2.0] - 2025-12-23
### Added
- **Web**: Added Landing Page, Privacy Policy, and Terms of Service using `@fastify/static`.
- **API**: Moved status check from root `/` to `/status/`.
- **Config**: Added `public/` directory for static assets.

### Documentation
- Updated `tdd-fletcher-server.md` to reflect current implementation. (23:48)

## [1.4.0] - 2025-12-24
### Added
- **UI**: Added new "Assistants" tab to replace "Logs".
- **MCP**: Added support for multiple assistant types (Claude, ChatGPT, Cursor, Other).
- **UX**: Added connection instructions tailored to each assistant type.
- **Config**: Updated server to allow flexible assistant types.

## [1.4.1] - 2025-12-24
### Changed
- **UX**: Moved Server URL configuration to Settings > Advanced.
- **UX**: Added "Reset to Default" button for Server URL.
- **Error Handling**: Improved error messages for invalid API keys/authentication failures.

## [1.4.2] - 2025-12-24
### Fixed
- **Critical**: Fixed bug where user ID was regenerated on every app build, causing loss of connection to existing tokens and location history.

## [1.3.0] - 2025-12-23
### Added
- **Security**: Implemented Keychain for secure API key storage.
- **Maintenance**: Centralized version management in `Info.plist` and `Bundle+Version`.
- **UX**: Added URL validation in MCP Connection settings.
- **Config**: Added `ITSAppUsesNonExemptEncryption` to `Info.plist` to bypass export compliance.

### Documentation
- Updated `tdd-fletcher-ios-app.md` to reflect current implementation. (23:48)

### Changed
- **Performance**: Refactored sync logic to use iterative batching with a 5-minute timer, preventing stack overflows and battery drain.
- **Code Quality**: Reduced code duplication in Map View zoom logic.

### Fixed
- **Retention**: Corrected retention logic to support "Indefinite" (-1) and fixed 0-day bugs.

## [1.2.13] - 2025-12-23
### Fixed
- **Performance**: Resolved memory crash in History View by replacing individual annotations with optimized `MapPolyline` rendering.

## [1.2.12] - 2025-12-23
### Fixed
- **Sync**: Improved error handling to log server error details when history fetch fails.

## [Server 1.1.9] - 2025-12-23
### Added
- **MCP**: Enhanced `get_location_history` with pagination (`limit`, `offset`), date filtering (`start_date`, `end_date`), and radius search (`center_lat`, `center_lon`, `radius_meters`).
- **MCP**: Added new tools: `get_current_location`, `get_recent_trajectory`, `get_frequent_locations`.
- **Performance**: Optimized batch inserts for location storage.
- **Security**: Added Rate Limiting, CORS support, and Request ID logging.
- **Monitoring**: Enhanced `/health` check to verify PostGIS connectivity.
- **Stability**: Added graceful shutdown for SIGTERM/SIGINT.
- **Schema**: Added schema versioning table and performance indexes.

### Fixed
- **Stability**: Server now exits properly if database initialization fails.
- **Config**: Corrected `.env.example` and dynamic SSE URL generation based on environment.
- **Maintenance**: Improved cleanup cron jobs for tokens and retention policies.

## [1.2.12] - 2025-12-23
### Changed
- **Sync**: Increased default history download limit to 5000 items to ensure complete restoration.

## [Server 1.1.8] - 2025-12-23
### Changed
- **API**: Increased maximum limit for `GET /api/locations` from 1000 to 10000.

## [1.2.10] - 2025-12-23
### Changed
- **UI**: Added total location count to the History View title.
- **Config**: Added missing Location Usage Descriptions to `Info.plist`.

## [1.2.9] - 2025-12-23
### Added
- **Sync**: Added "Download History" button in Sync Status screen to fetch historical data from server.
- **Sync**: Implemented efficient history merging to prevent duplicates.

## [Server 1.1.7] - 2025-12-23
### Added
- **API**: Added `GET /api/locations` endpoint to allow mobile clients to fetch location history.

## [1.2.8] - 2025-12-23
### Changed
- **Config**: Enabled support for all interface orientations (Portrait, Landscape Left/Right) on iPhone and iPad.

## [1.2.7] - 2025-12-23
### Fixed
- **Settings**: Updated `onChange` to use the new two-parameter syntax, resolving an iOS 17 deprecation warning.

## [1.2.6] - 2025-12-23
### Added
- **Settings**: Updated retention policy options to support "Indefinite".
- **Fix**: Retention settings are now strictly enforced locally (previously ignored).
- **Sync**: Retention settings changes are now synced to the server instantly.
- **Sync**: Implemented batch uploading (100 items per request) to respect server limits.

## [Server 1.1.6] - 2025-12-23
### Added
- **Auth**: Added detailed server-side logging for MCP token validation failures to aid debugging.

## [Server 1.1.5] - 2025-12-23
### Fixed
- **MCP SSE**: Fixed an issue where the connection would hang by properly hijacking the Fastify response stream.
- **Imports**: Fixed dynamic import syntax for `getRecentLocations` tool fallback.

## [Server 1.1.4] - 2025-12-23
### Fixed
- **Data Persistence**: Fixed an issue where the database was wiped on every server restart by removing `DROP TABLE` statements from the schema.
- **Retention**: Implemented a daily cron job to enforce retention policies and delete old data, while respecting the "Indefinite" setting.
- **API**: Updated `PATCH /api/privacy-settings` to accept and persist `retention_days`.

## [1.2.3] - 2025-12-16
## [Server 1.1.3] - 2025-12-16

### Changed
- **MCP Tool**: `get_location_history` date arguments are now optional. If omitted, the server defaults to returning the last 10 location points (recent history).

## [Server 1.1.2] - 2025-12-16

### Fixed
- **MCP Stream**: Changed Content-Type Parser to pass-through mode instead of buffer mode. This ensures `req.raw` stream remains readable for the MCP SDK `handlePostMessage` call.

## [Server 1.1.1] - 2025-12-16

### Fixed
- **MCP Connection**: Fixed an issue where the server was consuming the JSON body before the MCP SDK could read it, causing connection errors in Claude. Refactored MCP routes into an isolated plugin with custom content parsing `parseAs: 'buffer'`.

## [1.2.5] - 2025-12-16

### Added
- **Debug**: Added "Resync All Data" button in Sync Status screen to force re-uploading all local data (useful if server was redeployed/wiped).

## [1.2.4] - 2025-12-16

### Fixed
- **Sync Auth**: Implemented automatic re-registration when an invalid API key (401) is detected to heal broken auth states.
- **Sync Data**: Sanitized location payload and ensured positive accuracy values to prevent server validation errors.
- **UI**: Fixed "Copy URL" button in connection screen by using borderless button style.

## [Server 1.1.0] - 2025-12-16

### Changed
- **Validation**: Exposed detailed Zod validation errors in 400 responses to aid debugging.
- **Auth**: Updated `mcp/sse` endpoint to accept `token` via query parameter for single-URL connection.

## [1.2.3] - 2025-12-16
### Added
- **Server**: Root route now returns user and location counts.
- **Server**: Health check verifies database connectivity.

## [1.2.3] - 2025-12-16

### Added
- **Sync Status UI**: New screen to view detailed sync status, last attempt time, and pending items queue.
- **Server Health**: Status indicator in Location History showing real-time server connection state.

### Fixed
- **Sync Reliability**: Fixed 400 Error during location sync by correcting date encoding format and adding missing authentication headers.

## [1.2.2] - 2025-12-16

### Changed
- **Config**: Updated default server URL to `https://fletcher-server.onrender.com`.

## [1.2.1] - 2025-12-16

### Changed
- **UI**: Generalised "Claude" to "Assistant" in MCP Connection screens.
- **UI**: Moved Server URL configuration to the Manage Connections screen.

## [1.2.0] - 2025-12-16

### Added
- **App**: MCP Token Support.
- **App**: New `MCPConnectionView` to generate and manage connection tokens.
- **App**: Automatic Device Registration on launch.
- **App**: Setting to manage Assistant Connections.

## [1.1.0] - 2025-12-16

### Added
- **Server**: Implemented TDD v2.0 Architecture.
- **Server**: API Key authentication for mobile endpoints.
- **Server**: Privacy controls (precision reduction, history limits).
- **Server**: Access Logging for all AI assistant interactions.
- **Server**: OAuth 2.0 flow for MCP integration.
- **Server**: New `mobile` routes (`/api/register`, `/api/locations`).
- **MCP**: Updated MCP server to support v2 privacy and auth requirements.

### Changed
- **Server**: Reset database schema to enforce stricter constraints.
- **Server**: Refactored `auth` routes to use `oauth_codes` table.

## [1.0.1] - 2025-12-16

### Fixed
- **App**: Corrected toggle logic to accurately reflect tracking state.
- **App**: Resolved "Multiple commands produce Info.plist" build error.
- **App**: Fixed map button sizing and added zoom controls.
- **App**: Improved menu bar transparency and layout in `MainView`.

### Added
- **App**: Visual feedback (wiggle, pulse) for interactions.
- **App**: Manual location logging with "bullseye" animation.
- **App**: Display version number on Splash Screen.
- **App**: New App Icon (Arrow Maker theme).
