import Foundation

class APIClient {
    static let shared = APIClient()
    
    private let baseURL = URL(string: "http://localhost:3000/api")! // Configurable
    
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
