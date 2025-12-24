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
    
    let assistantTypes = ["Claude", "ChatGPT", "Cursor", "Other"]
    
    @AppStorage("serverURL") private var serverURL: String = "https://fletcher-server.onrender.com"
    
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
        .onAppear(perform: loadTokens)
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
                        
                        Button("Done") {
                            showGenerateSheet = false
                            generatedToken = nil
                            loadTokens()
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
                        
                        Button("Generate Token") {
                            generateToken()
                        }
                        .disabled(newTokenName.isEmpty || isLoading)
                    }
                }
                .navigationTitle("Connect Assistant")
                .navigationBarItems(leading: Button("Cancel") {
                    showGenerateSheet = false
                    generatedToken = nil
                })
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
