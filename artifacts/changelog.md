# Changelog

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
