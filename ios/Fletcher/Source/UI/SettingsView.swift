import SwiftUI

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = "http://localhost:3000"
    @State private var precision: Double = 1.0
    @State private var retentionDays: Int = 30
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server")) {
                    TextField("Server URL", text: $serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
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
                    }
                }
                
                Section(header: Text("Assistants")) {
                    NavigationLink("Manage Connections") {
                        Text("Coming Soon")
                    }
                }
                
                Section {
                    Button("Delete All History", role: .destructive) {
                        // Action
                    }
                }
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
