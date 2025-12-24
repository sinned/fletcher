# Technical Design Document (TDD) - Fletcher iOS App

**Version:** 1.5
**Date:** 2025-12-24
**Status:** IMPLEMENTED/LIVE

## 1. Introduction

### 1.1 Purpose
The purpose of this document is to detail the technical implementation of the Fletcher iOS application. It serves as a comprehensive guide for developers to understand the system architecture, data flow, component design, and integration points.

### 1.2 Scope
This document covers the iOS client side of the Fletcher system. It includes:
- Application Architecture (MVVM)
- Background Location Tracking Implementation
- Data Persistence and Synchronization
- User Interface Components
- Networking Layer
- MCP (Model Context Protocol) Integration

It does *not* cover the backend implementation in detail, except where necessary to explain client-server interactions.

## 2. System Overview

Fletcher is a native iOS application built with **Swift** and **SwiftUI**. Its primary function is to collect geospatial data in the background and synchronize it with a self-hosted Model Context Protocol (MCP) server.

### 2.1 High-Level Architecture
The app follows a **Model-View-ViewModel (MVVM)** architectural pattern, utilizing Swift's Combine framework and SwiftUI's state management (`@StateObject`, `@EnvironmentObject`).

- **View**: SwiftUI Views (Declarative UI).
- **ViewModel**: Manages state for views (e.g., `MCPConnectionView`).
- **Model**: Data structures (`LocationPoint`, `MCPToken`).
- **Services/Stores**: Singleton managers for logic and data (`BackgroundLocationService`, `LocationStore`, `APIClient`).

## 3. Architecture components

### 3.1 BackgroundLocationService
**Role**: Manages the `CLLocationManager` to receive location updates even when the app is suspended.

- **Key Responsibilities**:
  - Request Always Authorization.
  - Configure `allowsBackgroundLocationUpdates = true`.
  - Handle `didUpdateLocations` delegate method.
  - Handle `didVisit` for `CLVisit` monitoring (Battery Optimization).
  - Broadcast updates to the `LocationStore`.
  - Trigger Manual Logs via UI.

- **Configuration**:
  - `desiredAccuracy`: `kCLLocationAccuracyHundredMeters` (Balanced Power/Accuracy).
  - `distanceFilter`: 100 meters.
  - `pausesLocationUpdatesAutomatically`: `true` (Allowed for battery saving; system resumes on significant change).
  - `activityType`: `fitness` or `other`.

### 3.2 LocationStore (Persistence Layer)
**Role**: The central source of truth for location data. It handles in-memory state and persistent storage to disk.

- **Storage Handling**:
  - **Format**: JSON (`locations.json` in App Documents Directory).
  - **Thread Safety**: Uses a Background Global Queue for file writes.
  - **Strategy**: Appends new points to the in-memory array and saves to disk.

- **Key Methods**:
  - `addLocation(_ location: LocationPoint)`: Appends and saves.
  - `loadLocations()`: Reads `locations.json` on startup.
  - `cleanup()`: Enforces retention policy based on `UserDefaults` (default 30 days). If retention is <= 0 or -1, data is kept indefinitely.
  - `markSynced(ids: [UUID])`: Updates `synced = true` for successfully uploaded points.
  - `mergeLocations(_ locations: [LocationPoint])`: Deduplicates and merges points downloaded from server.

### 3.3 APIClient (Networking Layer)
**Role**: Handles HTTP communication with the backend.

- **Technology**: native `URLSession` with `async/await`.
- **Authentication**: Uses `API Key` stored securely in **Keychain**.
- **Endpoints**:
  - `POST /api/locations`: Sends batch of `LocationPoint` objects.
  - `GET /api/locations`: Fetches history.
  - `GET /health`: Checks server connectivity.
  - `POST /api/register`: Registers device and obtains API Key.
  - `PATCH /api/privacy-settings`: Updates server-side retention policy.
  - **MCP Endpoints**:
    - `POST /api/mcp/generate-token`
    - `GET /api/mcp/tokens`
    - `DELETE /api/mcp/tokens/{id}`
    - `GET /api/access-logs`: Fetches MCP request history with pagination and filtering

- **Sync Strategy**: 
  - `syncLocations()`: Iteratively syncs unsynced points in batches of 50 (`AppConstants.Sync.batchSize`) to avoid timeouts.
  - **Failover**:
    - **401 Unauthorized**: Automatically clears stored API key and prepares for re-registration.
    - **Error Handling**: Captures and exposes `lastSyncError` for UI display.

### 3.4 Key Utilities
- **KeychainManager**: Wrapper around `Security` framework for saving/loading the API Key (`apiKey`).
- **Bundle+Version**: Extensions to expose `appVersion` and `buildNumber` for display in Settings and Splash Screen.

## 4. Data Design

### 4.1 Data Models

#### LocationPoint
The core data entity representing a single geospatial event.

```swift
struct LocationPoint: Codable, Identifiable {
    var id: UUID = UUID()
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    var synced: Bool = false
}
```

- **id**: Unique identifier (UUID).
- **synced**: Local-only flag to track upload status.

#### MCPToken
Represents an authorized connection for an MCP client (e.g., Claude).
```swift
struct MCPToken: Decodable, Identifiable {
    let id: UUID
    let token_name: String?
    let assistant_type: String
    let connected_at: Date
    let token_preview: String?
}
```

#### MCPRequest
Represents a logged MCP request for transparency.
```swift
struct MCPRequest: Codable, Identifiable {
    let id: UUID
    let assistantType: String
    let endpoint: String
    let timestamp: Date
    let locationCount: Int
    let queryParams: [String: AnyCodable]?
    let responseTimeMs: Int?
}
```

#### AppSettings (UserDefaults)
Lightweight user preferences.
- `serverURL`: String (Default: `https://fletcher-server.onrender.com`)
- `retentionDays`: Int (Default: 30).
- `userId`: String (UUID of the registered device).

## 5. User Interface (UI) Design

### 5.1 Navigation Structure
The app uses a `TabView` in `MainView`.

- **Tabs**:
  - **Map**: Real-time map with `MapPolyline` history and current location.
  - **History**: List of logs and stats.
  - **Settings**: Configuration, MCP Connections, and Debug tools.

### 5.2 Key Views
- **MCPConnectionView**: Manages MCP tokens in the Assistants tab. Allows generating new tokens (displayed once) and revoking existing ones. Provides direct navigation to Request History.
- **MCPRequestHistoryView**: Displays all MCP requests grouped by date with pull-to-refresh and pagination. Tappable rows navigate to detailed view.
- **MCPRequestDetailView**: Shows comprehensive request information including endpoint, assistant type, timestamp, location count, query parameters (formatted JSON), response time (color-coded), and request UUID.
- **SplashScreen**: Shows on first launch or if API Key is missing, handling Device Registration. Displays App Version.
- **Map View**: Uses `MapKit` (SwiftUI). Features a custom "Recenter" button that also triggers manual logging.

## 6. Security and Privacy

### 6.1 Data Minimization
- Only Latitude, Longitude, Accuracy, and Timestamp are stored.
- No PII (Personally Identifiable Information) beyond location is collected.

### 6.2 Secure Storage
- **API Key**: Stored in iOS Keychain (not UserDefaults).
- **Location Data**: Stored in app sandbox (unencrypted JSON).

### 6.3 Configuration
- **Export Compliance**: `ITSAppUsesNonExemptEncryption` set to `NO` in `Info.plist` to bypass App Store export compliance steps for standard encryption usage (HTTPS).
- **Transport Security**: `NSAllowsArbitraryLoads` enabled to support local development/self-hosted HTTP servers, though HTTPS is default.

## 7. Future Considerations
- **CoreData Migration**: As the dataset grows, JSON parsing will become a bottleneck. Migration to CoreData or SQLite is recommended for >10k points.
- **Offline Queuing**: A more robust queue system for uploads rather than batching "all unsynced" every time.
