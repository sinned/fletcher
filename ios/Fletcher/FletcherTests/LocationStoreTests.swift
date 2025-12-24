import XCTest
@testable import Fletcher

class LocationStoreTests: XCTestCase {
    func testRetentionCleanup() {
        let store = LocationStore.shared
        // Reset store for testing
        store.clearAll()
        
        // Mock retention policy via UserDefaults
        UserDefaults.standard.set(30, forKey: "retentionDays")
        
        // Add old location (31 days ago)
        let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        store.addLocation(LocationPoint(
            id: UUID(),
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10.0,
            timestamp: oldDate,
            synced: false
        ))
        
        // Add new location (today)
        store.addLocation(LocationPoint(
            id: UUID(),
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10.0,
            timestamp: Date(),
            synced: false
        ))
        
        // Cleanup is called automatically on addLocation, so old one should be gone
        
        // Wait for async file write (optional, but memory array updates immediately)
        XCTAssertEqual(store.locations.count, 1)
        XCTAssertTrue(Calendar.current.isDateInToday(store.locations.first!.timestamp))
    }
    
    func testIndefiniteRetention() {
        let store = LocationStore.shared
        store.clearAll()
        
        // Set to indefinite (-1)
        UserDefaults.standard.set(-1, forKey: "retentionDays")
        
        // Add old location
        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        store.addLocation(LocationPoint(
            id: UUID(),
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10.0,
            timestamp: oldDate,
            synced: false
        ))
        
        XCTAssertEqual(store.locations.count, 1)
    }
}
