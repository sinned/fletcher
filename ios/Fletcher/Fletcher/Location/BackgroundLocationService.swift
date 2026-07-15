import Foundation
import CoreLocation
import Combine

class BackgroundLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var currentLocation: LocationPoint?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking: Bool = false
    
    private let store = LocationStore.shared
    private let api = APIClient.shared
    
    private var syncTimer: Timer?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters // Medium precision
        // Fletcher uses significant-change + visit monitoring (see startTracking),
        // which relaunch the app in the background on their own. They do NOT need
        // the `location` UIBackgroundMode, and setting allowsBackgroundLocationUpdates
        // without that mode throws — so it's intentionally not set here.
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.distanceFilter = 100 // Update every 100 meters

        setupSyncTimer()
    }
    
    private func setupSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.Sync.intervalSeconds, repeats: true) { [weak self] _ in
            self?.api.syncLocations()
        }
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startTracking() {
        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits() // Battery optimization: Visit Monitoring
        isTracking = true
    }
    
    func stopTracking() {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        isTracking = false
    }
    
    func manuallyLogLocation() {
        guard let current = currentLocation else { return }
        
        let newPoint = LocationPoint(
            latitude: current.latitude,
            longitude: current.longitude,
            accuracy: current.accuracy,
            timestamp: Date()
        )
        
        store.addLocation(newPoint)
        api.syncLocations() // Explicit manual sync is fine
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
        
        // Sync handles by Timer
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Create a LocationPoint for the arrival
        if visit.arrivalDate != Date.distantPast {
            let arrivalPoint = LocationPoint(
                latitude: visit.coordinate.latitude,
                longitude: visit.coordinate.longitude,
                accuracy: visit.horizontalAccuracy,
                timestamp: visit.arrivalDate
            )
            store.addLocation(arrivalPoint)
        }
        
        // Create a LocationPoint for the departure
        if visit.departureDate != Date.distantFuture {
            let departurePoint = LocationPoint(
                latitude: visit.coordinate.latitude,
                longitude: visit.coordinate.longitude,
                accuracy: visit.horizontalAccuracy,
                timestamp: visit.departureDate
            )
            store.addLocation(departurePoint)
        }
        
        // Visits are rare/significant, so maybe we trigger sync here immediately?
        // Or stick to timer to be consistent?
        // Let's trigger sync for visits as they are important
        api.syncLocations()
    }
}
