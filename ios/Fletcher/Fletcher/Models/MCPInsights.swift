import Foundation

// Summary of what an MCP assistant can derive from this account's data.
// Served by GET /api/insights and shown in the Assistants tab to demonstrate
// the MCP server's capabilities against the user's real data.
struct MCPInsights: Codable {
    let total_points: Int
    let latest: LatestPoint?
    let frequent_place_count: Int
    let distance_last_7_days_meters: Int
    let points_last_7_days: Int

    struct LatestPoint: Codable {
        let latitude: Double
        let longitude: Double
        let timestamp: String
    }

    var distanceLast7DaysKm: Double {
        (Double(distance_last_7_days_meters) / 100).rounded() / 10
    }
}
