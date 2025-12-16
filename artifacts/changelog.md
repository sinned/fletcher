# Changelog

All notable changes to the Fletcher iOS App project will be documented in this file.

## [0.1.2] - 2025-12-15

### Changed
- **Version**: Bumped version to 0.1.2.
- **Settings**: Added version display footer to the Settings screen.
- **Settings**: Implemented "Delete All History" functionality with a confirmation popup.

## [0.1.1] - 2025-12-15

### Added
- **App Icon**: Updated app icon to new "Arrow/Fletcher" design.
- **History View**: Added specific map view for history, accessible via a new list/map toggle.
- **Tracking Control**: Added a toggle switch to the Main View top bar to manually start/stop background location tracking.
- **Visual Feedback**: Added "TRACKING OFF" overlay and greyscale map effect when tracking is disabled.
- **Zoom Controls**: Added manual Zoom In (+) and Zoom Out (-) buttons to both Main Map and History Map.
- **Interaction Feedback**: Added "Wiggle" animation to the toggle and "Pulse" animation to the overlay when attempting to log location while tracking is off.
- **Version Display**: Added "v0.1.1" label to the Splash Screen.
- **Zoom Logic**: Fixed a bug where zoom buttons became unresponsive after manually panning or zooming the map by tracking `visibleRegion`.
- **Assets**: Fixed missing `AccentColor` and `AppIcon` warnings by restoring asset catalog structure.
- **Location Snap**: Restored "Snap to user" functionality by using `.userLocation` camera mode.

### Changed
- **Map API**: Refactored `MainView` and `HistoryMapView` to use iOS 17+ MapKit APIs (`MapCameraPosition`, `MapContentBuilder`) to resolve deprecation warnings.
- **UI Improvements**: Standardized size of map control buttons (Zoom, Location).

### Fixed
- **Build System**: Resolved "Multiple commands produce Info.plist" error by removing duplicate reference in Build Phases.
- **Interactions**: Fixed an issue where the Tracking Toggle was non-interactive due to a hit-testing overlay issue in the top bar.
- **Logic**: Prevented manual location logging when tracking is explicitly turned off.
