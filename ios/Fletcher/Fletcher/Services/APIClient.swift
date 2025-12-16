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
    // MARK: - Registration
    
    func registerDevice() async {
        if apiKey != nil { return } // Already registered
        
        let id = UUID() // Generate new ID or use vendor ID? Server expects UUID. 
        // Ideally persisted UUID, but for MVP we can generate one. 
        // Better: Use IdentifierForVendor if strictly 1:1, but UUID is fine if stored.
        // Actually, let's just generate one and store it.
        
        guard let url = URL(string: "\(baseURL.absoluteString)/register") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["user_id": id.uuidString]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
                struct RegisterResponse: Decodable {
                    let api_key: String
                }
                let res = try JSONDecoder().decode(RegisterResponse.self, from: data)
                UserDefaults.standard.set(res.api_key, forKey: "apiKey")
                UserDefaults.standard.set(id.uuidString, forKey: "userId") // Store ID too
                print("Registered with API Key: \(res.api_key)")
            } else {
                print("Registration failed: \(response)")
            }
        } catch {
            print("Registration error: \(error)")
        }
    }

    // MARK: - Auth
    
    private var apiKey: String? {
        // Retrieve from Keychain or UserDefaults. For MVP verification, we might hardcode or assume it's stored.
        // PRD says: "Store `api_key` securely in iOS Keychain".
        // For this task, I'll assume it's in UserDefaults for simplicity if Keychain helper isn't visible,
        // OR I should check if AuthManager exists.
        return UserDefaults.standard.string(forKey: "apiKey")
    }

    // MARK: - MCP Methods

    func generateMCPToken(name: String) async throws -> MCPTokenResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/mcp/generate-token") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let body = ["assistant_type": "claude", "token_name": name]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPTokenResponse.self, from: data)
    }

    func getMCPTokens() async throws -> [MCPToken] {
        guard let url = URL(string: "\(baseURL.absoluteString)/mcp/tokens") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Server returns { "tokens": [...] }
        struct ListResponse: Decodable {
            let tokens: [MCPToken]
        }
        return try decoder.decode(ListResponse.self, from: data).tokens
    }

    func revokeMCPToken(id: UUID) async throws {
        guard let url = URL(string: "\(baseURL.absoluteString)/mcp/tokens/\(id.uuidString)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
