# Changelog

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
