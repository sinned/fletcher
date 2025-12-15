import SwiftUI

@main
struct FletcherApp: App {
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var locationService = BackgroundLocationService()
    
    init() {
        print("DEBUG: FletcherApp Init")
    }

    var body: some Scene {
        WindowGroup {
            SplashScreen()
                .environmentObject(locationStore)
                .environmentObject(locationService)
                .onAppear {
                    locationService.requestPermissions()
                }
        }
    }
}
