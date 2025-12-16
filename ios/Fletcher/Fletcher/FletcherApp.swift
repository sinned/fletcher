import SwiftUI

@main
struct FletcherApp: App {
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var locationService = BackgroundLocationService()

    init() {
        // Migration: If serverURL is stuck on localhost default, update it to Render
        let stored = UserDefaults.standard.string(forKey: "serverURL")
        if stored == "http://localhost:3000" {
            UserDefaults.standard.set("https://fletcher-server.onrender.com", forKey: "serverURL")
        }
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
