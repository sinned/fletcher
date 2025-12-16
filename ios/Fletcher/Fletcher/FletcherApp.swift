import SwiftUI

@main
struct FletcherApp: App {
    @StateObject private var locationStore = LocationStore.shared
    @StateObject private var locationService = BackgroundLocationService()
    
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
