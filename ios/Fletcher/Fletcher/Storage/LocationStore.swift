import Foundation
import Combine

class LocationStore: ObservableObject {
    static let shared = LocationStore()
    
    @Published var locations: [LocationPoint] = []
    
    private let fileURL: URL
    
    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = documents.appendingPathComponent("locations.json")
        load()
    }
    
    func addLocation(_ point: LocationPoint) {
        locations.append(point)
        cleanup()
        save()
    }
    
    func mergeLocations(_ newLocations: [LocationPoint]) {
        var addedCount = 0
        for loc in newLocations {
            // Deduplication logic: Match by ID or timestamp (within 1ms tolerance).
            // Server generates new UUIDs, so we rely on timestamp matching for local->server reconciliation.
            if !locations.contains(where: { $0.id == loc.id || abs($0.timestamp.timeIntervalSince(loc.timestamp)) < 0.001 }) {
                locations.append(loc)
                addedCount += 1
            }
        }
        
        if addedCount > 0 {
            locations.sort(by: { $0.timestamp > $1.timestamp })
            save()
            print("Merged \(addedCount) locations from server")
        }
    }
    
    func deleteLocation(id: UUID) {
        locations.removeAll { $0.id == id }
        save()
    }
    
    func clearAll() {
        locations.removeAll()
        save()
    }
    
    func markSynced(_ ids: [UUID]) {
        // Update synced status
        // For simple JSON, acts as read-modify-write
        // Optimization: In real app, use CoreData/DB
        for i in 0..<locations.count {
            if ids.contains(locations[i].id) {
                locations[i].synced = true
            }
        }
        save()
    }
    
    func getUnsynced() -> [LocationPoint] {
        return locations.filter { !$0.synced }
    }
    
    func markAllAsUnsynced() {
        for i in 0..<locations.count {
            locations[i].synced = false
        }
        save()
    }
    
    private func save() {
        // Dispatch to background to avoid blocking main thread
        DispatchQueue.global(qos: .background).async {
            do {
                let data = try JSONEncoder().encode(self.locations)
                try data.write(to: self.fileURL, options: [.atomic, .completeFileProtection])
            } catch {
                print("Failed to save locations: \(error)")
            }
        }
    }
    
    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            locations = try JSONDecoder().decode([LocationPoint].self, from: data)
            cleanup()
        } catch {
            print("Failed to load locations (or empty): \(error)")
        }
    }
    
    private func cleanup() {
        let defaults = UserDefaults.standard
        // -1 means indefinite, so check for explicit -1 or use default
        let retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? AppConstants.Defaults.retentionDays
        
        // retentionDays <= 0 means indefinite retention
        guard retentionDays > 0 else { return }
        
        // Calculate cutoff date
        if let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) {
            locations.removeAll { $0.timestamp < cutoffDate }
        }
    }
}
