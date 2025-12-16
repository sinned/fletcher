import Foundation

struct MCPToken: Codable, Identifiable {
    let id: UUID
    let assistant_type: String
    let token_name: String?
    let connected_at: Date
    let last_used_at: Date?
    let expires_at: Date
    let token_preview: String?
}

struct MCPTokenResponse: Codable {
    let token: String
    let sse_url: String
    let expires_at: Date
    let instructions: String
}
