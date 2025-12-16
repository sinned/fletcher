# Technical Design Document (TDD) - Fletcher iOS App

**Version:** 1.0
**Date:** 2025-12-15
**Status:** DRAFT

## 1. Introduction

### 1.1 Purpose
The purpose of this document is to detail the technical implementation of the Fletcher iOS application. It serves as a comprehensive guide for developers to understand the system architecture, data flow, component design, and integration points.

### 1.2 Scope
This document covers the iOS client side of the Fletcher system (MVP). It includes:
- Application Architecture (MVVM)
- Background Location Tracking Implementation
- Data Persistence and Synchronization
- User Interface Components
- Networking Layer

It does *not* cover the backend implementation in detail, except where necessary to explain client-server interactions.

## 2. System Overview

Fletcher is a native iOS application built with **Swift** and **SwiftUI**. Its primary function is to collect geospatial data in the background and synchronize it with a self-hosted Model Context Protocol (MCP) server.

### 2.1 High-Level Architecture
The app follows a **Model-View-ViewModel (MVVM)** architectural pattern, heavily utilizing Swift's Combine framework and SwiftUI's state management (`@StateObject`, `@EnvironmentObject`).

- **View**: SwiftUI Views (Declarative UI).
- **ViewModel**: Manages state for views (e.g., `LocationListViewModel` - *Implicitly handled via Store in MVP*).
- **Model**: Data structures (`LocationPoint`).
- **Services/Stores**: Singleton managers for logic and data (`BackgroundLocationService`, `LocationStore`, `APIClient`).

## 3. Architecture components

### 3.1 BackgroundLocationService
**Role**: Manages the `CLLocationManager` to receive location updates even when the app is suspended.

- **Key Responsibilities**:
  - Request Always Authorization.
  - Configure `allowsBackgroundLocationUpdates = true`.
  - Handle `didUpdateLocations` delegate method.
  - Filter updates based on accuracy and timestamp to reduce noise.
  - Broadcast updates to the `LocationStore`.

- **Configuration**:
  - `desiredAccuracy`: `kCLLocationAccuracyHundredMeters` (Balanced Power/Accuracy).
  - `distanceFilter`: 100 meters.
  - `pausesLocationUpdatesAutomatically`: `false` (Critical for continuous tracking).

### 3.2 LocationStore (Persistence Layer)
**Role**: The central source of truth for location data. It handles in-memory state and persistent storage to disk.

- **Storage Handling**:
  - **Format**: JSON (`locations.json` in App Documents Directory).
  - **Thread Safety**: Uses a Serial Dispatch Queue for file writes to prevent race conditions.
  - **Strategy**: Appends new points to the in-memory array and triggers a debounced save to disk.

- **Key Methods**:
  - `addLocation(_ location: CLLocation)`: Converts raw location to `LocationPoint` and saves.
  - `loadLocations()`: Reads and decodes the JSON file on startup.
  - `clearHistory()`: Wipes local data.
  - `markAsSynced(ids: [UUID])`: Updates the `synced` flag for specific points.

### 3.3 APIClient (Networking Layer)
**Role**: Handles HTTP communication with the backend.

- **Technology**: native `URLSession`.
- **Endpoints**:
  - `POST /api/locations`: Sends an array of `LocationPoint` objects.
  - `GET /health`: Checks server connectivity.
- **Refactoring**: `APIClient` is an `ObservableObject` exposing `@Published` properties (`isSyncing`, `lastSyncError`) for real-time UI updates.
- **Failover**:
  - **401 Unauthorized**: Automatically clears stored API key and re-registers the device to heal broken auth states.
  - **400 Bad Request**: Server validation errors are parsed and displayed to the user.
- **Resync Strategy**: `markAllAsUnsynced()` iterates through all local points and resets `synced = false`, forcing them to be re-evaluated for upload.

## 4. Data Design

### 4.1 Data Models

#### LocationPoint
The core data entity representing a single geospatial event.

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

- **id**: Unique identifier for valid deduplication.
- **synced**: Mutable flag to track synchronization status.

#### AppSettings (UserDefaults)
Lightweight user preferences stored in `UserDefaults`.
- `serverURL`: String (Default: `http://localhost:3000`)
- `trackingEnabled`: String/Bool (State needs to be restored on launch).

## 5. User Interface (UI) Design

### 5.1 Navigation Structure
The app uses a `TabView` (managed in `MainView`) but with a custom visual overlay.

- **Tabs**:
  - **Map**: Main interaction surface.
  - **History**: List of logs.
  - **Settings**: Configuration.

### 5.2 Map Strategy
- **Framework**: `MapKit` (SwiftUI `Map`).
- **Overlays**:
  - `MapPolyline`: Renders the path of history types.
  - `MapUserLocationButton`: Custom implementation to re-center.
- **Interaction**:
  - The map view sits in a `ZStack`. The header ("Fletcher") floats *above* the map, with hit testing disabled for the background of the header to allow map touches to pass through.

## 6. Security and Privacy

### 6.1 Data Minimization
- Only Latitude, Longitude, Accuracy, and Timestamp are stored.
- No PII (Personally Identifiable Information) beyond location is collected.

### 6.2 Local Storage
- Data is stored in the app's sandbox. It is not accessible to other apps.
- *Note*: JSON storage is unencrypted in the MVP. Future versions may use CoreData with encryption or Realm.

## 7. Future Considerations
- **CoreData Migration**: As the dataset grows, JSON parsing will become a bottleneck. Migration to CoreData or SQLite is recommended for >10k points.
- **Battery Optimization**: Implementing `visitMonitoring` or significant location changes API for lower power consumption during stationary periods.
- **Offline Queuing**: A more robust queue system for uploads rather than batching "all unsynced" every time.
