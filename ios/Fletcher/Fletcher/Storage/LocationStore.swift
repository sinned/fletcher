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
