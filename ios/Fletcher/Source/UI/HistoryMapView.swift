import SwiftUI
import MapKit

struct HistoryMapView: View {
    let locations: [LocationPoint]
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: locations) { location in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
            }
        }
        .onAppear {
            if let last = locations.first { // Sorted by desc timestamp usually
                region.center = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            }
        }
    }
}
