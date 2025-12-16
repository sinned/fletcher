import SwiftUI
import MapKit

struct MainView: View {
    @EnvironmentObject var locationService: BackgroundLocationService
    
    @State private var selection = 0
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main Content (Map/Tabs)
            TabView(selection: $selection) {
                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map")
                    }
                    .tag(0)
                
                LogsView()
                    .tabItem {
                        Label("Logs", systemImage: "list.bullet")
                    }
                    .tag(1)
                
                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(2)
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(3)
            }
            .accentColor(.purple)
            .edgesIgnoringSafeArea(.top) // Allow map to go under status bar/header
            
            // Custom Top Bar (Floating Overlay) - Only show on Map (Tag 0)
            if selection == 0 {
                HStack {
                    Image(systemName: "location.north.fill")
                        .foregroundColor(.purple)
                    Text("Fletcher")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { locationService.isTracking },
                        set: { isTracking in
                            if isTracking {
                                locationService.startTracking()
                            } else {
                                locationService.stopTracking()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .purple))
                }
                .padding()
                .padding(.top, 44) // Status bar spacing
                .background(Color.white.opacity(0.01))
                .allowsHitTesting(false)
            }
        }
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
    @State private var showPulse = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Map(coordinateRegion: $region,
                    showsUserLocation: true,
                    userTrackingMode: $trackingMode)
                    .edgesIgnoringSafeArea(.top)
                
                if showPulse {
                    Circle()
                        .stroke(Color.purple, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .scaleEffect(4) // Scale up 4x
                        .opacity(0)     // Fade out
                        .onAppear {
                            // Reset state after animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.showPulse = false
                            }
                        }
                }
            }
            
            Button(action: {
                trackingMode = .follow
                locationService.manuallyLogLocation() // Log entry on tap
                
                // Trigger Pulse
                withAnimation(.easeOut(duration: 0.8)) {
                    showPulse = true
                }
                
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
