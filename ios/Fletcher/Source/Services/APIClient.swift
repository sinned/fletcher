import Foundation

class APIClient {
    static let shared = APIClient()
    
    private var baseURL: URL {
        let defaultURL = URL(string: "http://localhost:3000/api")!
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:3000"
        let clean = stored.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(clean)/api") ?? defaultURL
    }
    
    func syncLocations() {
        let unsynced = LocationStore.shared.getUnsynced()
        guard !unsynced.isEmpty else { return }
        
        let url = baseURL.appendingPathComponent("locations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Wrap in object
        let body = ["locations": unsynced]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            print("Encoding error: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Sync failed: \(error)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Mark as synced
                let ids = unsynced.map { $0.id }
                DispatchQueue.main.async {
                    LocationStore.shared.markSynced(ids)
                }
                print("Synced \(ids.count) locations")
            } else {
                print("Sync server error: \(String(describing: response))")
            }
        }.resume()
    }
}
