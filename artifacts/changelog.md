# Changelog

## [1.2.6] - 2025-12-23
### Added
- **Settings**: Updated retention policy options to support "Indefinite".
- **Fix**: Retention settings are now strictly enforced locally (previously ignored).
- **Sync**: Retention settings changes are now synced to the server instantly.

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
