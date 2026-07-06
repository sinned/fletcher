import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var locationStore: LocationStore
    @State private var viewMode: ViewMode = {
#if DEBUG
        if ProcessInfo.processInfo.environment["FLETCHER_HISTORY_MODE"] == "map" { return .map }
#endif
        return .list
    }()
    @State private var showSyncStatus = false
    @State private var serverStatus: ServerStatus = .checking
    @State private var unsyncedCount: Int = 0
    
    enum ServerStatus {
        case checking, online, offline
    }
    
    enum ViewMode {
        case list, map
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("View Mode", selection: $viewMode) {
                    Text("List").tag(ViewMode.list)
                    Text("Map").tag(ViewMode.map)
                }
                .pickerStyle(SegmentedPickerStyle())
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Server Status & Sync
                Button(action: { showSyncStatus = true }) {
                    HStack {
                        if serverStatus == .checking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Circle()
                                .fill(serverStatus == .online ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                        }
                        
                        Text(serverStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if unsyncedCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync \(unsyncedCount)")
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 8)
                .sheet(isPresented: $showSyncStatus) {
                    SyncStatusView()
                        .environmentObject(locationStore)
                }
                .task {
                    await checkServer()
                }
                .onAppear {
                    refreshUnsynced()
                }
                
                if viewMode == .list {
                    List {
                        ForEach(locationStore.locations.sorted(by: { $0.timestamp > $1.timestamp })) { location in
                            VStack(alignment: .leading) {
                                Text("\(location.timestamp, style: .date) \(location.timestamp, style: .time)")
                                    .font(.headline)
                                HStack {
                                    Text(String(format: "Lat: %.4f, Lon: %.4f", location.latitude, location.longitude))
                                        .font(.subheadline)
                                    Spacer()
                                    if location.synced {
                                        Image(systemName: "icloud.and.arrow.up")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "icloud.slash")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    locationStore.deleteLocation(id: location.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } else {
                    HistoryMapView(locations: locationStore.locations)
                }
            }
            .navigationTitle("History (\(locationStore.locations.count))")
        }
    }
    
    var serverStatusText: String {
        switch serverStatus {
        case .checking: return "Checking..."
        case .online: return "Server Online"
        case .offline: return "Server Offline"
        }
    }
    
    private func checkServer() async {
        serverStatus = .checking
        let isAlive = await APIClient.shared.checkHealth()
        serverStatus = isAlive ? .online : .offline
    }
    
    private func refreshUnsynced() {
        unsyncedCount = LocationStore.shared.getUnsynced().count
    }
}
