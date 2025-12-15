# Product Requirements Document (PRD) - Fletcher iOS MVP

**Date:** 2025-12-14
**Status:** Implemented (MVP)

## 1. Executive Summary
Fletcher is a privacy-first location tracking application designed to provide context to AI assistants via the Model Context Protocol (MCP). The iOS app acts as the primary data producer, silently collecting location data in the background and syncing it to a self-hosted server.

## 2. System Architecture
The system consists of two main components:
-   **iOS Client**: Native SwiftUI application for data collection and visualization.
-   **Backend Server**: Node.js/Fastify server with PostgreSQL/PostGIS for geospatial storage.

### 2.1 Technology Stack
-   **iOS**: SwiftUI, CoreLocation, Combine, MapKit.
-   **Server**: Node.js, Fastify, PostGIS.
-   **Database**: PostgreSQL 17 (Geospatial extension enabled).

## 3. Implemented Features

### 3.1 Background Location Tracking
-   **Service**: `BackgroundLocationService` manages `CLLocationManager`.
-   **Precision**: Configured for medium precision (`kCLLocationAccuracyHundredMeters`) to balance battery life and utility.
-   **Mode**: Runs in background (`allowsBackgroundLocationUpdates = true`).
-   **Logic**: Updates are triggered by significant location changes or distance filters (100m).

### 3.2 Offline Data Management
-   **Store**: `LocationStore` (Singleton) handles data persistence.
-   **Persistence**: Saves location points to `locations.json` in the Documents directory.
-   **Sync Status**: Tracks `synced` boolean flag for each point to ensure no data loss during offline periods.

### 3.3 Server Synchronization
-   **Client**: `APIClient` handles network requests.
-   **Endpoint**: `POST /api/locations`.
-   **Mechanism**: Batches unsynced locations and pushes to server. On 200 OK, marks items as synced locally.
-   **Configuration**: Defaults to `localhost:3000` (configurable for device testing).

### 3.4 User Interface (UI)
-   **Assets**:
    -   **App Icon**: Custom "Arrow Maker" themed icon (Arrow on Blue/Purple gradient).
    -   **Icons**: Consistent use of `location.north.fill` (arrow) throughout the app.
-   **Splash Screen**:
    -   **Visuals**: Vibrant Blue-to-Purple gradient background with white arrow icon.
    -   Auto-transition to Main View after 2 seconds.
-   **Main View (ZStack)**:
    -   **Layout**: `ZStack` allows the Map to span the full screen, including under the header.
    -   **Top Menu Bar**: Transparent floating header with "Fletcher" branding. Allows map interaction underneath.
    -   **Map Tab**: Full-screen `MapKit` view.
        -   **Live Tracking**: Automatically centers on user location.
        -   **Manual Logging**: "Re-center" button adds a manual history entry with a "Bullseye" pulse animation for feedback.
-   **History Tab**: List view of stored location points with swipe-to-delete.
-   **Settings Tab**:
    -   **Server Configuration**: Configurable Server URL (saved in `UserDefaults`).
    -   **Privacy**: Precision and retention controls.

## 4. Specific Implementation Details

### 4.1 Data Models
**LocationPoint**:
```swift
struct LocationPoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    var synced: Bool
}
```

### 4.2 Application Entry Point (`FletcherApp.swift`)
-   Initializes `LocationStore.shared` and `BackgroundLocationService` as `StateObject`s.
-   Injects these into the environment for View access.
-   Requests location permissions on launch.
-   Routing: Splash Screen -> Main View.

## 5. Setup & Verification
1.  **Server**:
    -   `npm install` & `npm start`.
    -   PostgreSQL 17+ with PostGIS required.
2.  **iOS**:
    -   Xcode Project: "Fletcher".
    -   Capabilities: Background Modes -> Location updates.
    -   Info.plist: `NSLocationAlwaysAndWhenInUseUsageDescription`.

## 6. Future Roadmap
-   [ ] OAuth2 Authentication for Server.
-   [ ] Battery optimization (adaptive tracking).
-   [ ] MCP Server-Sent Events (SSE) for real-time AI context.
