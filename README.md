# Fletcher

**Website:** [fletcher.to](https://fletcher.to) · **Beta:** [TestFlight](https://testflight.apple.com/join/b68RvuHg) · **License:** [MIT](LICENSE)

## Overview
Fletcher is a privacy-first location tracking app that enables AI assistants to provide location-aware assistance through the Model Context Protocol (MCP). Your history is anonymous (no account, just a random device ID), every AI request is logged for you to audit, and you can run the sync server yourself.

## Features
- **Background Tracking**: Efficiently tracks location in the background with "Always" permission.
- **Privacy Control**: Manual "Tracking" toggle to strictly control when location is recorded.
- **Visual Feedback**: Clear "TRACKING OFF" overlay, grayscale map, and haptic/visual warnings when disabled.
- **Interactive Map**:
    - **Live Snap**: Automatically follows user location on startup and when centered.
    - **Zoom Controls**: Manual +/- buttons for precise navigation.
    - **History Map**: View historical location points on a map.
- **Data Management**:
    - **Local History**: View logs in List or Map format.
    - **Delete History**: Securely clear all local data with confirmation.
- **Web Interface**:
    - **Landing Page**: Modern landing page ("Travel Assistant" theme) at root.
    - **Legal**: Privacy Policy (`/privacy.html`) and Terms of Service (`/terms.html`).
    - **Status**: Server statistics available at `/status/`.
- **MCP Integration**: Fully functional Model Context Protocol server for Claude integration. Supports advanced location queries (radius, trajectory, frequency) with full **Timezone Support**.
- **Synchronization**:
    - **Cloud Sync**: Securely uploads location history to your private server.
    - **Status View**: Detailed sync diagnostics and manual sync controls.
    - **Resync**: Tooling to heal sync state if server data is lost.
- **Privacy First**: Complete control over what data is sent and stored.

## Project Structure
- `ios/`: iOS Application (SwiftUI)
- `server/`: MCP Server (Node.js/Fastify)

## Getting Started

### Server Setup
1. Navigate to `server/`:
   ```bash
   cd server
   npm install
   ```
2. Setup PostgreSQL database:
   - Create a database (e.g., `fletcher`).
   - Enable PostGIS: `CREATE EXTENSION postgis;`
   - Initial schema: `src/db/schema.sql`.
3. Configure environment:
   - Copy `.env.example` to `.env` and update `DATABASE_URL`.
4. Run server:
   ```bash
   npm run build
   npm start
   ```

### iOS Setup
1. Open `ios/Fletcher/Fletcher.xcodeproj`.
2. Ensure the "Fletcher" target is selected.
3. Verify Signing & Capabilities for your team.
4. Add `Info.plist` keys (already configured):
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `NSLocationWhenInUseUsageDescription`
   - `UIBackgroundModes`: select `location` and `fetch`.
5. Build and run on a device (Simulator doesn't support "Always" location well).

## API Endpoints
- `GET /health`: Health check (DB + PostGIS)
- `GET /status/`: Server statistics (Users, Locations)
- `POST /api/locations`: Upload location history
- `GET /api/locations`: Get location history (paginated)
- `POST /api/mcp/generate-token`: Generate MCP connection token
- `GET /sse`: MCP Server-Sent Events endpoint (Bearer token auth)

## Deployment
See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions on deploying the MCP Server to Render.

## Verification
- Visit `http://localhost:3000/status/` to check stats.
- Visit `http://localhost:3000/` to verify the Landing Page.

## License
Fletcher is open source under the [MIT License](LICENSE).
