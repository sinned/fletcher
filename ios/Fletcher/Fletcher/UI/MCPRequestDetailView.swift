import SwiftUI

struct MCPRequestDetailView: View {
    let request: MCPRequest
    
    var body: some View {
        List {
            // Overview Section
            Section(header: Text("Overview")) {
                HStack {
                    Text("Endpoint")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(request.formattedEndpoint)
                        .bold()
                }
                
                HStack {
                    Text("Assistant")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack {
                        Image(systemName: request.assistantIcon)
                        Text(request.assistantType.capitalized)
                    }
                    .bold()
                }
                
                HStack {
                    Text("Timestamp")
                        .foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(formatFullDate(request.timestamp))
                            .bold()
                        Text(request.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if request.locationCount > 0 {
                    HStack {
                        Text("Locations Accessed")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.orange)
                            Text("\(request.locationCount)")
                                .bold()
                        }
                    }
                }
                
                if let responseTime = request.responseTimeMs {
                    HStack {
                        Text("Response Time")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(responseTime)ms")
                            .bold()
                            .foregroundColor(responseTimeColor(responseTime))
                    }
                }
            }
            
            // Query Parameters Section
            if let params = request.queryParams, !params.isEmpty {
                Section(header: Text("Query Parameters")) {
                    ForEach(Array(params.keys.sorted()), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            
                            Text(formatValue(params[key]?.value))
                                .font(.body)
                                .fontDesign(.monospaced)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // Request ID Section
            Section(header: Text("Request ID")) {
                Text(request.id.uuidString)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Request Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatValue(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        
        if let dict = value as? [String: Any] {
            // Pretty print JSON
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        } else if let array = value as? [Any] {
            if let data = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        
        return String(describing: value)
    }
    
    private func responseTimeColor(_ ms: Int) -> Color {
        if ms < 100 {
            return .green
        } else if ms < 500 {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    NavigationView {
        MCPRequestDetailView(request: MCPRequest(
            id: UUID(),
            assistantType: "claude",
            endpoint: "get_location_history",
            timestamp: Date(),
            locationCount: 42,
            queryParams: [
                "limit": AnyCodable(100),
                "offset": AnyCodable(0),
                "start_date": AnyCodable("2024-01-01T00:00:00Z")
            ],
            responseTimeMs: 156
        ))
    }
}
