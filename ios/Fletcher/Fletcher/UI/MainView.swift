import SwiftUI
import MapKit

struct MainView: View {
    @EnvironmentObject var locationService: BackgroundLocationService
    
    @State private var selection = 0
    
    var body: some View {
        // Main Content (Map/Tabs)
        TabView(selection: $selection) {
            MapView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(0)
            
            NavigationView {
                MCPConnectionView()
            }
            .tabItem {
                Label("Assistants", systemImage: "sparkles")
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
    }
}

struct MapView: View {
    @EnvironmentObject var locationService: BackgroundLocationService
    
    // Default to User Location
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    
    @State private var showPulse = false
    
    // Interaction States
    @State private var wiggleTrigger = 0
    @State private var overlayPulseTrigger = false
    
    // Track the visible region to support zooming after user interaction
    @State private var visibleRegion: MKCoordinateRegion?

    // Zoom state helper
    private let zoomFactor = 2.0
    
    var body: some View {
        ZStack(alignment: .top) {
            // 1. Map Layer
            Map(position: $position) {
                UserAnnotation()
            }
            .onMapCameraChange { context in
                visibleRegion = context.region
            }
            .onAppear {
                if locationService.authorizationStatus == .authorizedAlways || locationService.authorizationStatus == .authorizedWhenInUse {
                    // Force a snap if we are authorized
                   position = .userLocation(fallback: .automatic)
                }
            }
            .mapControls {
                // Disable default controls
            }
            .edgesIgnoringSafeArea(.top)
            .saturation(locationService.isTracking ? 1.0 : 0.0)
            
            // 2. Tracking Off Overlay
            if !locationService.isTracking {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .edgesIgnoringSafeArea(.top)
                        .allowsHitTesting(false)
                        
                    Text("TRACKING OFF")
                        .font(.largeTitle)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(12)
                        // Overlay Pulse Animation
                        .scaleEffect(overlayPulseTrigger ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.3), value: overlayPulseTrigger)
                }
            }
            
            // 3. User Location Pulse (Blue Dot extension)
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
            
            // 4. Custom Top Bar (Floating Overlay)
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
            // Wiggle Animation
            .keyframeAnimator(initialValue: 0, trigger: wiggleTrigger) { content, value in
                content.rotationEffect(.degrees(Double(value)))
                    .offset(x: Double(value) * 1.5) // Slight x offset with rotation
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(0, duration: 0.0)
                    CubicKeyframe(-3, duration: 0.05)
                    CubicKeyframe(3, duration: 0.05)
                    CubicKeyframe(-3, duration: 0.05)
                    CubicKeyframe(3, duration: 0.05)
                    CubicKeyframe(0, duration: 0.05)
                }
            }
            
            // 5. Action Buttons (Zoom / Location)
            VStack(spacing: 12) {
                // Zoom In Button
                Button(action: {
                   zoomIn()
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .frame(width: 24, height: 24)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                // Zoom Out Button
                Button(action: {
                    zoomOut()
                }) {
                    Image(systemName: "minus")
                        .font(.title2)
                        .frame(width: 24, height: 24)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                // Location Button (Recenter/Log)
                Button(action: {
                    handleLocationTap()
                }) {
                    Image(systemName: "location.fill")
                        .font(.title2)
                        .frame(width: 24, height: 24)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding()
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
    
    private func handleLocationTap() {
        if !locationService.isTracking {
            // Trigger feedback animations
            wiggleTrigger += 1
            overlayPulseTrigger = true
            
            // Reset overlay pulse after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                overlayPulseTrigger = false
            }
            return
        }
        
        // Normal Behavior
        locationService.manuallyLogLocation() // Log entry on tap
        
        // Trigger Pulse
        withAnimation(.easeOut(duration: 0.8)) {
            showPulse = true
        }
        
        if let _ = locationService.currentLocation {
             withAnimation {
                 // Snap to user location and start following
                 position = .userLocation(fallback: .automatic)
             }
        }
    }
    
    private func zoomIn() {
        zoom(by: 1.0 / zoomFactor)
    }
    
    private func zoomOut() {
        zoom(by: zoomFactor)
    }
    
    private func zoom(by factor: Double) {
        let currentRegion = getCurrentRegion()
        
        var newSpan = currentRegion.span
        newSpan.latitudeDelta *= factor
        newSpan.longitudeDelta *= factor
        
        withAnimation {
            position = .region(MKCoordinateRegion(center: currentRegion.center, span: newSpan))
        }
    }
    
    private func getCurrentRegion() -> MKCoordinateRegion {
        visibleRegion ?? position.region ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    }
}
