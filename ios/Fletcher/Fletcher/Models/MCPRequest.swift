import Foundation

struct MCPRequest: Identifiable, Codable {
    let id: UUID
    let assistantType: String
    let endpoint: String
    let timestamp: Date
    let locationCount: Int
    let queryParams: [String: AnyCodable]?
    let responseTimeMs: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case assistantType = "assistant_type"
        case endpoint
        case timestamp
        case locationCount = "location_count"
        case queryParams = "query_params"
        case responseTimeMs = "response_time_ms"
    }
    
    var formattedEndpoint: String {
        endpoint.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "get ", with: "")
            .capitalized
    }
    
    var assistantIcon: String {
        switch assistantType.lowercased() {
        case "claude":
            return "brain"
        case "chatgpt":
            return "bubble.left.and.bubble.right"
        case "cursor":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "sparkles"
        }
    }
    
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// Helper to decode Any type in JSON
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

struct MCPRequestsResponse: Codable {
    let logs: [MCPRequest]
    let metadata: Metadata
    
    struct Metadata: Codable {
        let totalCount: Int
        let returnedCount: Int
        let hasMore: Bool
        let limit: Int
        let offset: Int
        
        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case returnedCount = "returned_count"
            case hasMore = "has_more"
            case limit
            case offset
        }
    }
}
