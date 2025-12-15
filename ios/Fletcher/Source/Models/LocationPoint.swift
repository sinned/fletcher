import Foundation

struct LocationPoint: Codable, Identifiable {
    var id: UUID = UUID()
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    var synced: Bool = false
}
