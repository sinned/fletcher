import SwiftUI

struct SettingsView: View {

    @AppStorage("locationPrecision") private var precision: Double = 1.0
    @AppStorage("retentionDays") private var retentionDays: Int = 30
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
                
                Section(header: Text("Assistants")) {
                    NavigationLink("Manage Connections") {
                        MCPConnectionView()
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
                
                Section {
                    HStack {
                        Spacer()
                        Text("Fletcher v1.2.13")
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
