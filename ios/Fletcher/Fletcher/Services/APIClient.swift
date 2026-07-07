import Foundation
import Combine

class APIClient: ObservableObject {
    static let shared = APIClient()
    
    @Published var isSyncing = false
    @Published var lastSyncAttempt: Date?
    @Published var lastSyncError: String?
    
    private var baseURL: URL {
        let defaultURL = URL(string: "\(AppConstants.Server.defaultURL)/api")!
        let stored = UserDefaults.standard.string(forKey: "serverURL") ?? AppConstants.Server.defaultURL
        let clean = stored.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(clean)/api") ?? defaultURL
    }
    
    func syncLocations() {
        Task {
            await syncAllLocations()
        }
    }
    
    private func syncAllLocations() async {
        guard !isSyncing else { return }
        
        await MainActor.run {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        
        defer {
            Task { @MainActor in
                self.isSyncing = false
                self.lastSyncAttempt = Date()
            }
        }
        
        while true {
            let unsynced = LocationStore.shared.getUnsynced()
            if unsynced.isEmpty { break }
            
            let batchSize = AppConstants.Sync.batchSize
            let batch = Array(unsynced.prefix(batchSize))
            
            do {
                try await syncBatch(batch)
                // Mark as synced
                let ids = batch.map { $0.id }
                await MainActor.run {
                    LocationStore.shared.markSynced(ids)
                }
                print("Synced batch of \(ids.count)")
            } catch {
                print("Sync failed: \(error)")
                await MainActor.run {
                    self.lastSyncError = error.localizedDescription
                }
                // Stop on error to prevent loop
                return 
            }
        }
    }

    private func syncBatch(_ batch: [LocationPoint]) async throws {
        let url = baseURL.appendingPathComponent("locations")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let currentKey = apiKey
        let currentUserId = UserDefaults.standard.string(forKey: "userId")
        
        if currentKey == nil && currentUserId != nil {
            print("Sync Aborted: UserID exists but API Key is inaccessible (likely locked).")
            throw NSError(domain: "APIClient", code: -999, userInfo: [NSLocalizedDescriptionKey: "Keychain unavailable (locked)"])
        }
        
        if let key = currentKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        struct LocationDTO: Encodable {
            let latitude: Double
            let longitude: Double
            let accuracy: Double
            let timestamp: Date
        }
        
        let payload = batch.map { loc in
            LocationDTO(
                latitude: loc.latitude,
                longitude: loc.longitude,
                accuracy: max(loc.accuracy, 1.0),
                timestamp: loc.timestamp
            )
        }
        
        let body = ["locations": payload]
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return
            } else if httpResponse.statusCode == 401 {
                print("401 Unauthorized. Clearing key.")
                KeychainManager.delete(key: "apiKey")
                await MainActor.run {
                    self.lastSyncError = "Auth invalid. Re-registering..."
                }
                // Attempt to re-register immediately to fix the state
                await registerDevice()
                
                throw URLError(.userAuthenticationRequired)
            } else {
                let errorMsg = String(data: data, encoding: .utf8) ?? String(describing: response)
                throw NSError(domain: "SyncError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
            }
        }
    }
    
    func fetchHistory(limit: Int = 5000, before: Date? = nil) async throws -> [LocationPoint] {
        var urlComp = URLComponents(string: "\(baseURL.absoluteString)/locations")!
        var queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
        
        if let before = before {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "before", value: formatter.string(from: before)))
        }
        urlComp.queryItems = queryItems
        
        guard let url = urlComp.url else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 401 {
             await registerDevice()
             throw URLError(.userAuthenticationRequired)
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorText])
        }
        
        struct HistoryResponse: Decodable {
            struct RemoteLocation: Decodable {
                let id: UUID
                let latitude: Double
                let longitude: Double
                let accuracy: Double
                let timestamp: String
            }
            let locations: [RemoteLocation]
        }
        
        let res = try JSONDecoder().decode(HistoryResponse.self, from: data)
        
        return res.locations.compactMap { loc -> LocationPoint? in
            guard let date = ISO8601DateFormatter.fletcherFormatter.date(from: loc.timestamp) else { return nil }
            return LocationPoint(
                id: loc.id,
                latitude: loc.latitude,
                longitude: loc.longitude,
                accuracy: loc.accuracy,
                timestamp: date,
                synced: true
            )
        }
    }
    
    func fetchAllHistory(progress: ((Int) -> Void)? = nil) async throws -> [LocationPoint] {
        var allPoints: [LocationPoint] = []
        var hasMore = true
        var lastDate: Date? = nil
        let batchSize = 1000 // Smaller batch for smoother progress updates
        
        while hasMore {
            let chunk = try await fetchHistory(limit: batchSize, before: lastDate)
            if chunk.isEmpty {
                hasMore = false
            } else {
                allPoints.append(contentsOf: chunk)
                lastDate = chunk.last?.timestamp
                
                await MainActor.run {
                    progress?(allPoints.count)
                }
                
                if chunk.count < batchSize {
                    hasMore = false
                }
            }
        }
        return allPoints
    }

    // MARK: - Settings
    
    func updatePrivacySettings(retentionDays: Int) {
        guard let url = URL(string: "\(baseURL.absoluteString)/privacy-settings") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        // retention_days: -1 is valid for indefinite
        let body = ["retention_days": retentionDays]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Failed to update settings: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("Successfully updated retention to \(retentionDays) days")
                } else {
                    print("Failed to update settings: Server returned \(String(describing: response))")
                }
            }.resume()
        } catch {
            print("Encoding error: \(error)")
    }
    }

    func deleteServerHistory() async throws {
        guard let url = URL(string: "\(baseURL.absoluteString)/locations") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            print("Successfully deleted all server history")
        } else {
            throw NSError(domain: "APIClient", code: (response as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: "Failed to delete server history"])
        }
    }

    // MARK: - Registration
    
    func registerDevice(forceNew: Bool = false) async {
        if !forceNew && apiKey != nil { return } // Already registered
        
        let id: UUID
        if !forceNew, let existingId = UserDefaults.standard.string(forKey: "userId"), let uuid = UUID(uuidString: existingId) {
            id = uuid
            print("Reusing existing User ID: \(existingId)")
        } else {
            id = UUID()
            print("Generated new User ID: \(id.uuidString)")
        }
        
        guard let url = URL(string: "\(baseURL.absoluteString)/register") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["user_id": id.uuidString]
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201 {
                    struct RegisterResponse: Decodable {
                        let api_key: String
                    }
                    let res = try JSONDecoder().decode(RegisterResponse.self, from: data)
                    _ = KeychainManager.save(key: "apiKey", data: res.api_key)
                    UserDefaults.standard.set(id.uuidString, forKey: "userId") // Store ID too
                    print("Registered with API Key: \(res.api_key)")
                } else if httpResponse.statusCode == 409 {
                    print("Registration 409 Conflict. Likely existing user without key. Retrying with new ID...")
                    await registerDevice(forceNew: true)
                } else {
                    print("Registration failed: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("Registration error: \(error)")
        }
    }

    // MARK: - Auth
    
    private var apiKey: String? {
        return KeychainManager.load(key: "apiKey")
    }

    // MARK: - MCP Methods

    func generateMCPToken(name: String, assistantType: String) async throws -> MCPTokenResponse {
        guard let url = URL(string: "\(baseURL.absoluteString)/mcp/generate-token") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let body = ["assistant_type": assistantType.lowercased(), "token_name": name]
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
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 401 {
            // Auth failed, potentially clear key?
            // KeychainManager.delete(key: "apiKey") 
            // For now, just throw informative error so UI sees it
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed. Relaunch app to re-register."])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server Error \(httpResponse.statusCode): \(errorText)"])
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
    
    func fetchMCPRequestHistory(
        limit: Int = 50,
        offset: Int = 0,
        assistantType: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> MCPRequestsResponse {
        var components = URLComponents(string: "\(baseURL.absoluteString)/access-logs")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        if let assistantType = assistantType {
            queryItems.append(URLQueryItem(name: "assistant_type", value: assistantType))
        }
        
        let dateFormatter = ISO8601DateFormatter()
        if let startDate = startDate {
            queryItems.append(URLQueryItem(name: "start_date", value: dateFormatter.string(from: startDate)))
        }
        if let endDate = endDate {
            queryItems.append(URLQueryItem(name: "end_date", value: dateFormatter.string(from: endDate)))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let key = apiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 401 {
            throw NSError(domain: "APIClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication failed"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server Error \(httpResponse.statusCode): \(errorText)"])
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MCPRequestsResponse.self, from: data)
    }
    
    func checkHealth() async -> Bool {
        guard let url = URL(string: baseURL.absoluteString.replacingOccurrences(of: "/api", with: "/health")) else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5 // Short timeout for UI checks
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            return false
        }
        return false
    }
}
