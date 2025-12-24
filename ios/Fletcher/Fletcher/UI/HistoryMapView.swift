import SwiftUI
import MapKit

struct HistoryMapView: View {
    let locations: [LocationPoint]
    
    @State private var position: MapCameraPosition = .automatic
    @State private var hasSetInitialPosition = false
    @State private var visibleRegion: MKCoordinateRegion?
    
    // Zoom state helper
    private let zoomFactor = 2.0
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                if !locations.isEmpty {
                    // Show all locations as dots
                    ForEach(locations) { location in
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        }
                        .annotationTitles(.hidden)
                    }
                    
                    // Highlight oldest point (green)
                    if let start = locations.last { 
                        Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                        .annotationTitles(.hidden)
                    }
                    
                    // Highlight newest point (red)
                    if let end = locations.first {
                        Annotation("End", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .onMapCameraChange { context in
                visibleRegion = context.region
            }
            .onAppear {
                if !hasSetInitialPosition, let last = locations.first { // Sorted by desc timestamp usually
                    position = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))
                    hasSetInitialPosition = true
                }
            }
            
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
            }
            .padding()
            .padding(.bottom, 20)
        }
    }
    
    private func zoomIn() {
        let currentRegion = visibleRegion ?? position.region ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        var newSpan = currentRegion.span
        newSpan.latitudeDelta /= zoomFactor
        newSpan.longitudeDelta /= zoomFactor
        
        withAnimation {
            position = .region(MKCoordinateRegion(center: currentRegion.center, span: newSpan))
        }
    }
    
    private func zoomOut() {
        let currentRegion = visibleRegion ?? position.region ?? MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )

        var newSpan = currentRegion.span
        newSpan.latitudeDelta *= zoomFactor
        newSpan.longitudeDelta *= zoomFactor
        
        withAnimation {
            position = .region(MKCoordinateRegion(center: currentRegion.center, span: newSpan))
        }
    }
}
