import Foundation
import CoreLocation
import Combine

class BackgroundLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: LocationPoint?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let store = LocationStore.shared
    private let api = APIClient.shared
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Medium precision
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.distanceFilter = 100 // Update every 100 meters
        // In iOS 16+, strictly explicit about background
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        
        let newPoint = LocationPoint(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy,
            timestamp: loc.timestamp
        )
        
        DispatchQueue.main.async {
            self.currentLocation = newPoint
        }
        
        // Save to store
        store.addLocation(newPoint)
        
        // Trigger sync if needed (naive approach: sync every few updates or timer)
        // For MVP, simplistic sync check
        api.syncLocations()
    }
}
