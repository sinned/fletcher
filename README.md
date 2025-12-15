# Fletcher MVP

## Overview
Fletcher is a privacy-first location tracking app that enables AI assistants to provide location-aware assistance through Model Context Protocol (MCP).

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
1. Open `ios/` folder.
2. Create a new Xcode project named "Fletcher" using the "App" template.
3. Replace the generated content with the files in `ios/Fletcher/Source/`.
   - Ensure you add the files to the app target.
4. Add `Info.plist` keys:
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `NSLocationWhenInUseUsageDescription`
   - `UIBackgroundModes`: select `location` and `fetch`.
5. Build and run on a device (Simulator doesn't support "Always" location well).

## API Endpoints
- `GET /health`: Health check
- `POST /api/locations`: Upload location history
- `GET /mcp/sse`: MCP Server-Sent Events endpoint
- `POST /auth/oauth/authorize`: OAuth2 Authorization

## Verification
- Visit `http://localhost:3000/health` to check if server is running.
