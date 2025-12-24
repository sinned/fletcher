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
            // Check if ID exists OR if same timestamp (fuzzy check?)
            // Server locations have IDs. Local might have different IDs if not synced?
            // Actually, if we fetch from server, they have server-assigned IDs or client-assigned IDs sent earlier.
            // If client generated UUID, and server kept it, then ID match works.
            // If server generated UUID (no, schema says users send locs, usually with client ID or server gen?
            // Schema has `id UUID PRIMARY KEY DEFAULT gen_random_uuid()`. 
            // Client sends `(latitude, longitude...)` in POST /locations.
            // Server Generates IDs!
            // So if we pull from server, they have Server IDs. 
            // Local locations have Client IDs.
            // If we blindly merge, we might duplicate if we have local copy that *was* synced but app forgot it was synced?
            // Or if we have local copy, it has `synced=true`.
            // Ideally we match by timestamp + lat/lon.
            
            // Simple dupe check: ID match OR Timestamp match
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
        let retentionDays: Int
        
        if defaults.object(forKey: "retentionDays") == nil {
            retentionDays = 30 // Default matches SettingsView
        } else {
            retentionDays = defaults.integer(forKey: "retentionDays")
        }
        
        // -1 or 0 means indefinite (treating 0 as such for safety, though -1 is the new option)
        guard retentionDays > 0 else { return }
        
        // Calculate cutoff date
        if let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) {
            locations.removeAll { $0.timestamp < cutoffDate }
        }
    }
}
