import SwiftUI

@main
struct FletcherApp: App {
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var locationService = BackgroundLocationService()

    init() {
        // Migration: move older installs off the localhost dev default and the
        // legacy onrender host onto the current domain. Both point at the same
        // backend/database, so a stored API key keeps working across the switch.
        let stored = UserDefaults.standard.string(forKey: "serverURL")
        if stored == "http://localhost:3000" || stored == AppConstants.Server.legacyURL {
            UserDefaults.standard.set(AppConstants.Server.defaultURL, forKey: "serverURL")
        }
#if DEBUG
        if ProcessInfo.processInfo.environment["FLETCHER_DEMO_DATA"] == "1" {
            DemoData.seedIfNeeded()
        }
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreen()
                .environmentObject(locationStore)
                .environmentObject(locationService)
                .task {
                    await APIClient.shared.registerDevice()
                }
                .onAppear {
                    locationService.requestPermissions()
                }
        }
    }
}

#if DEBUG
// Screenshot/demo support, active only when launched with FLETCHER_DEMO_DATA=1
// (e.g. `SIMCTL_CHILD_FLETCHER_DEMO_DATA=1 simctl launch ...`). Never runs in Release.
enum DemoData {
    static func seedIfNeeded() {
        let store = LocationStore.shared
        guard store.locations.count < 50 else { return }

        // A few days of wandering around San Francisco
        let route: [(lat: Double, lon: Double)] = [
            (37.7599, -122.4148), // Mission
            (37.7648, -122.4194),
            (37.7694, -122.4269), // Castro
            (37.7702, -122.4469),
            (37.7694, -122.4762), // Golden Gate Park
            (37.7715, -122.4832),
            (37.7756, -122.4522),
            (37.7793, -122.4192), // Civic Center
            (37.7879, -122.4074), // Union Square
            (37.7952, -122.3934), // Ferry Building
            (37.8024, -122.4058), // North Beach
            (37.8078, -122.4177), // Aquatic Park
        ]

        var points: [LocationPoint] = []
        for dayOffset in 0..<3 {
            let dayBase = Date().addingTimeInterval(Double(-dayOffset) * 86_400 - 10 * 3_600)
            for (i, waypoint) in route.enumerated() {
                for sample in 0..<4 {
                    points.append(LocationPoint(
                        latitude: waypoint.lat + Double.random(in: -0.0008...0.0008),
                        longitude: waypoint.lon + Double.random(in: -0.0008...0.0008),
                        accuracy: Double.random(in: 8...35),
                        timestamp: dayBase.addingTimeInterval(Double(i) * 2_800 + Double(sample) * 400),
                        synced: true
                    ))
                }
            }
        }
        store.mergeLocations(points)
    }
}
#endif
