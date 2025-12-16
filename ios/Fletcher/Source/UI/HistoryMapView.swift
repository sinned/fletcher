import SwiftUI
import MapKit

struct HistoryMapView: View {
    let locations: [LocationPoint]
    
    @State private var position: MapCameraPosition = .automatic
    @State private var hasSetInitialPosition = false
    
    // Zoom state helper
    private let zoomFactor = 2.0
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                ForEach(locations) { location in
                    Annotation("Loc", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }
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
        if let region = position.region {
            var newSpan = region.span
            newSpan.latitudeDelta /= zoomFactor
            newSpan.longitudeDelta /= zoomFactor
            withAnimation {
                position = .region(MKCoordinateRegion(center: region.center, span: newSpan))
            }
        }
    }
    
    private func zoomOut() {
        if let region = position.region {
            var newSpan = region.span
            newSpan.latitudeDelta *= zoomFactor
            newSpan.longitudeDelta *= zoomFactor
            withAnimation {
                position = .region(MKCoordinateRegion(center: region.center, span: newSpan))
            }
        }
    }
}
