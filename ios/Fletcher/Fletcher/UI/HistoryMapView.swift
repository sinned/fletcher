import SwiftUI
import MapKit

struct HistoryMapView: View {
    let locations: [LocationPoint]

    @State private var position: MapCameraPosition = .automatic
    @State private var hasSetInitialPosition = false
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var displayedLocations: [LocationPoint] = []

    // Zoom state helper
    private let zoomFactor = 2.0

    // Rendering an Annotation view per raw point hangs the map once history grows
    // (each Annotation is a full SwiftUI view). Points are thinned to at most one
    // per grid cell of the visible region, so the on-screen picture is unchanged
    // but the view count stays bounded regardless of history size.
    private let gridDivisions = 56.0
    private let maxDisplayedPoints = 1000

    // Newest/oldest by timestamp: the store's array order varies (addLocation
    // appends newest-last, mergeLocations sorts newest-first), so positional
    // first/last is not reliable.
    private var newestLocation: LocationPoint? {
        locations.max(by: { $0.timestamp < $1.timestamp })
    }

    private var oldestLocation: LocationPoint? {
        locations.min(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $position) {
                // Show thinned locations as dots
                ForEach(displayedLocations) { location in
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    }
                    .annotationTitles(.hidden)
                }

                // Highlight oldest point (green)
                if let start = oldestLocation {
                    Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }

                // Highlight newest point (red)
                if let end = newestLocation {
                    Annotation("End", coordinate: CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                updateDisplayedLocations(for: context.region)
            }
            .onAppear {
#if DEBUG
                // Screenshot support: frame the whole history instead of the newest point
                if ProcessInfo.processInfo.environment["FLETCHER_MAP_FIT"] == "1", !locations.isEmpty {
                    let lats = locations.map(\.latitude)
                    let lons = locations.map(\.longitude)
                    let region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                                       longitude: (lons.min()! + lons.max()!) / 2),
                        span: MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.01),
                                               longitudeDelta: max((lons.max()! - lons.min()!) * 1.3, 0.01))
                    )
                    position = .region(region)
                    hasSetInitialPosition = true
                    updateDisplayedLocations(for: region)
                    return
                }
#endif
                if !hasSetInitialPosition, let newest = newestLocation {
                    let region = MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: newest.latitude, longitude: newest.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                    position = .region(region)
                    hasSetInitialPosition = true
                    updateDisplayedLocations(for: region)
                }
            }
            .onChange(of: locations.count) { _, _ in
                if let region = visibleRegion {
                    updateDisplayedLocations(for: region)
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

    private func updateDisplayedLocations(for region: MKCoordinateRegion) {
        // Pad to 2x the visible span so small pans don't pop points in at the edges
        let latSpan = max(region.span.latitudeDelta, 0.0001)
        let lonSpan = max(region.span.longitudeDelta, 0.0001)
        let latMin = region.center.latitude - latSpan
        let latMax = region.center.latitude + latSpan
        let lonMin = region.center.longitude - lonSpan
        let lonMax = region.center.longitude + lonSpan

        let cellLat = (latMax - latMin) / gridDivisions
        let cellLon = (lonMax - lonMin) / gridDivisions

        var firstPointPerCell: [Int: LocationPoint] = [:]
        firstPointPerCell.reserveCapacity(Int(gridDivisions * gridDivisions) / 4)
        for point in locations {
            guard point.latitude >= latMin, point.latitude <= latMax,
                  point.longitude >= lonMin, point.longitude <= lonMax else { continue }
            let row = Int((point.latitude - latMin) / cellLat)
            let col = Int((point.longitude - lonMin) / cellLon)
            let key = row * 128 + col
            if firstPointPerCell[key] == nil {
                firstPointPerCell[key] = point
            }
        }

        var thinned = Array(firstPointPerCell.values)
        if thinned.count > maxDisplayedPoints {
            let step = Double(thinned.count) / Double(maxDisplayedPoints)
            thinned = (0..<maxDisplayedPoints).map { thinned[Int(Double($0) * step)] }
        }
        displayedLocations = thinned
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
