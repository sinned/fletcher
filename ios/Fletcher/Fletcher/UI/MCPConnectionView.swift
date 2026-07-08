import SwiftUI

struct MCPConnectionView: View {
    @State private var tokens: [MCPToken] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Generate Token State
    @State private var showGenerateSheet = false
    @State private var newTokenName = "My Device"
    @State private var newAssistantType = "Claude"
    @State private var generatedToken: MCPTokenResponse?

    // Capability showcase
    @State private var insights: MCPInsights?
    @State private var copiedPrompt: String?

    let assistantTypes = ["Claude", "ChatGPT", "Cursor", "Other"]
    
    @AppStorage("serverURL") private var serverURL: String = AppConstants.Server.defaultURL
    
    var body: some View {
        List {

            Section {
                Button(action: { showGenerateSheet = true }) {
                    Label("Connect New Assistant", systemImage: "plus")
                }
                
                NavigationLink(destination: MCPRequestHistoryView()) {
                    Label("Request History", systemImage: "clock.arrow.circlepath")
                }
            }

            Section {
                if let ins = insights {
                    HStack(spacing: 0) {
                        statPill(value: "\(ins.total_points)", label: "points")
                        Divider().frame(height: 34)
                        statPill(value: String(format: "%.1f", ins.distanceLast7DaysKm), label: "km · 7d")
                        Divider().frame(height: 34)
                        statPill(value: "\(ins.frequent_place_count)", label: "top places")
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text("What your assistant can see")
            } footer: {
                Text("Live, from your own data. A connected assistant sees this at the precision you choose in Settings.")
            }

            Section {
                ForEach(capabilities) { cap in
                    Button {
                        UIPasteboard.general.string = cap.prompt
                        copiedPrompt = cap.prompt
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedPrompt == cap.prompt { copiedPrompt = nil }
                        }
                    } label: {
                        CapabilityRow(capability: cap, copied: copiedPrompt == cap.prompt)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Try asking")
            } footer: {
                Text("Tap an example to copy it, then paste it to your connected assistant.")
            }

            Section(header: Text("Active Connections")) {
                if tokens.isEmpty && !isLoading {
                    Button(action: { showGenerateSheet = true }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No assistants connected")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Connect this device to your own AI assistant to let it access your location data securely.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Tap here to connect")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                ForEach(tokens) { token in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(token.token_name ?? "Assistant")
                                .font(.headline)
                            Spacer()
                            Text(token.assistant_type.capitalized)
                                .font(.caption)
                                .padding(4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                        
                        Text("Connected: \(token.connected_at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let preview = token.token_preview {
                            Text(preview)
                                .font(.caption2)
                                .fontDesign(.monospaced)
                                .foregroundColor(.gray)
                        }
                    }
                    .swipeActions {
                        Button("Revoke", role: .destructive) {
                            revokeToken(id: token.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Assistants")
        .onAppear {
            loadTokens()
            loadInsights()
        }
        .sheet(isPresented: $showGenerateSheet) {
            NavigationView {
                Form {
                    if let generated = generatedToken {
                        Section(header: Text("Success!")) {
                            Text("Copy this URL to your Assistant Settings. This token will only be shown once.")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading) {
                                Text("MCP Server URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text(constructMCPURL(token: generated.token))
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button(action: {
                                        UIPasteboard.general.string = constructMCPURL(token: generated.token)
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            
                            Text(generated.instructions)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Section {
                            Button(action: {
                                showGenerateSheet = false
                                generatedToken = nil
                                loadTokens()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Done")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .listRowBackground(Color.blue)
                            .foregroundColor(.white)
                        }
                    } else {
                        Section(header: Text("New Connection")) {
                            TextField("Device Name (e.g. MacBook)", text: $newTokenName)
                            
                            Picker("Assistant Type", selection: $newAssistantType) {
                                ForEach(assistantTypes, id: \.self) { type in
                                    Text(type).tag(type)
                                }
                            }
                        }
                        
                        Section {
                            Button(action: {
                                generateToken()
                            }) {
                                HStack {
                                    Spacer()
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text("Generate Token")
                                            .fontWeight(.semibold)
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(newTokenName.isEmpty || isLoading)
                            .listRowBackground(newTokenName.isEmpty || isLoading ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                        }
                    }
                }
                .navigationTitle("Connect Assistant")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        // Only show cancel if token hasn't been generated yet
                        if generatedToken == nil {
                            Button("Cancel") {
                                showGenerateSheet = false
                                generatedToken = nil
                            }
                        }
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
    }
    
    private func loadTokens() {
        isLoading = true
        Task {
            do {
                tokens = try await APIClient.shared.getMCPTokens()
            } catch {
                errorMessage = "Failed to load tokens: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func loadInsights() {
        Task {
            insights = try? await APIClient.shared.fetchInsights()
        }
    }

    @ViewBuilder
    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundColor(.purple)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // Capabilities map 1:1 to the MCP server's tools, annotated with a live
    // value from the user's own data where one applies.
    private var capabilities: [Capability] {
        [
            Capability(icon: "location.fill", title: "Current location",
                       prompt: "Where am I right now?", live: latestLive),
            Capability(icon: "clock.fill", title: "A point in time",
                       prompt: "Where was I at 3pm yesterday?", live: nil),
            Capability(icon: "ruler.fill", title: "Distance traveled",
                       prompt: "How far did I travel this week?",
                       live: insights.map { "\(String(format: "%.1f", $0.distanceLast7DaysKm)) km in the last 7 days" }),
            Capability(icon: "star.fill", title: "Frequent places",
                       prompt: "What places do I visit most often?",
                       live: insights.map { $0.frequent_place_count > 0 ? "\($0.frequent_place_count) frequent places found" : "No clusters yet" }),
            Capability(icon: "mappin.and.ellipse", title: "Visits to a place",
                       prompt: "How often did I go to the gym this month?", live: nil),
            Capability(icon: "map.fill", title: "Recent route",
                       prompt: "Trace my route over the last few hours.",
                       live: insights.map { "\($0.total_points) points tracked" }),
            Capability(icon: "sun.max.fill", title: "Day summary",
                       prompt: "Summarize my day yesterday.", live: nil),
            Capability(icon: "house.fill", title: "Home & work",
                       prompt: "Where are my home and work?", live: nil),
            Capability(icon: "arrow.triangle.turn.up.right.diamond.fill", title: "Trips",
                       prompt: "What trips did I take today?", live: nil)
        ]
    }

    private var latestLive: String? {
        guard let ts = insights?.latest?.timestamp,
              let date = ISO8601DateFormatter.fletcherFormatter.date(from: ts) else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Last point \(f.localizedString(for: date, relativeTo: Date()))"
    }
    
    private func generateToken() {
        isLoading = true
        Task {
            do {
                generatedToken = try await APIClient.shared.generateMCPToken(name: newTokenName, assistantType: newAssistantType)
            } catch {
                errorMessage = "Failed to generate: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func revokeToken(id: UUID) {
        Task {
            do {
                try await APIClient.shared.revokeMCPToken(id: id)
                loadTokens()
            } catch {
                errorMessage = "Failed to revoke: \(error.localizedDescription)"
            }
        }
    }
    private func constructMCPURL(token: String) -> String {
        let cleanURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(cleanURL)/sse?token=\(token)"
    }

}

private struct Capability: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let prompt: String
    let live: String?
}

private struct CapabilityRow: View {
    let capability: Capability
    let copied: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: capability.icon)
                .foregroundColor(.purple)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(capability.title)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("\u{201C}\(capability.prompt)\u{201D}")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let live = capability.live {
                    Text(live)
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
            }
            Spacer()
            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.caption)
                .foregroundColor(copied ? .green : .secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}
