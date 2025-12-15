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
        } catch {
            print("Failed to load locations (or empty): \(error)")
        }
    }
}
