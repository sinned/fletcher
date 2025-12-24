import SwiftUI

struct SettingsView: View {

    @AppStorage("locationPrecision") private var precision: Double = 1.0
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("serverURL") private var serverURL: String = "https://fletcher-server.onrender.com"
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {

                Section(header: Text("Privacy")) {
                    VStack(alignment: .leading) {
                        Text("Location Precision")
                        Slider(value: $precision, in: 0...2, step: 1)
                        Text(precisionLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("Retention Period", selection: $retentionDays) {
                        Text("7 Days").tag(7)
                        Text("14 Days").tag(14)
                        Text("30 Days").tag(30)
                        Text("90 Days").tag(90)
                        Text("Indefinite").tag(-1)
                    }
                    .onChange(of: retentionDays) { _, newValue in
                        APIClient.shared.updatePrivacySettings(retentionDays: newValue)
                    }
                }
                
                Section {
                    Button("Delete All History", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .alert("Delete All History", isPresented: $showDeleteConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Delete", role: .destructive) {
                            LocationStore.shared.clearAll()
                        }
                    } message: {
                        Text("Are you sure you want to delete all location history? This action cannot be undone.")
                    }
                }
                
                Section(header: Text("MCP")) {
                    NavigationLink(destination: MCPConnectionView()) {
                        Label("Manage Tokens", systemImage: "key.fill")
                    }
                    
                    NavigationLink(destination: MCPRequestHistoryView()) {
                        Label("Request History", systemImage: "clock.arrow.circlepath")
                    }
                }
                
                Section(header: Text("Advanced")) {
                    VStack(alignment: .leading) {
                        Text("Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Server URL", text: $serverURL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                    }
                    
                    Button("Reset to Default") {
                        serverURL = "https://fletcher-server.onrender.com"
                    }
                    .disabled(serverURL == "https://fletcher-server.onrender.com")
                }
                
                Section {
                    HStack {
                        Spacer()
                        Text("Fletcher \(Bundle.main.fullVersion)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
        }
    }
    
    var precisionLabel: String {
        switch precision {
        case 0: return "Low (~1km)"
        case 1: return "Medium (~100m)"
        case 2: return "High (~10m)"
        default: return "Medium"
        }
    }
}
