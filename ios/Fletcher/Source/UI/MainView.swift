import SwiftUI
import MapKit

struct MainView: View {
    @EnvironmentObject var locationService: BackgroundLocationService
    
    var body: some View {
        TabView {
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
            
            LogsView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .accentColor(.purple)
    }
}

struct MapView: View {
    @EnvironmentObject var locationService: BackgroundLocationService
    
    // Default to San Francisco
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    @State private var trackingMode: MapUserTrackingMode = .follow
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                userTrackingMode: $trackingMode)
                .edgesIgnoringSafeArea(.top)
                .onReceive(locationService.$currentLocation) { loc in
                    if let loc = loc {
                        // Smoothly animate to new location
                        withAnimation {
                            region.center = CLLocationCoordinate2D(
                                latitude: loc.latitude,
                                longitude: loc.longitude
                            )
                        }
                    }
                }
            
            Button(action: {
                trackingMode = .follow
                if let loc = locationService.currentLocation {
                    withAnimation {
                        region.center = CLLocationCoordinate2D(
                            latitude: loc.latitude,
                            longitude: loc.longitude
                        )
                    }
                }
            }) {
                Image(systemName: "location.fill")
                    .padding()
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            .padding()
            .padding(.bottom, 20)
        }
    }
}
