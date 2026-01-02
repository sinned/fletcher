import SwiftUI

struct SyncStatusView: View {
    @ObservedObject var api = APIClient.shared
    @EnvironmentObject var store: LocationStore
    @Environment(\.presentationMode) var presentationMode
    
    @State private var downloadingHistory = false
    @State private var downloadProgress = 0

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Connection")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        if api.isSyncing {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Syncing...")
                                .foregroundColor(.blue)
                        } else if let _ = api.lastSyncError {
                            Text("Failed")
                                .foregroundColor(.red)
                        } else {
                            Text("Idle")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let last = api.lastSyncAttempt {
                        HStack {
                            Text("Last Attempt")
                            Spacer()
                            Text(last.formatted(date: .abbreviated, time: .standard))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = api.lastSyncError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Section(header: Text("Queue")) {
                    HStack {
                        Text("Pending Items")
                        Spacer()
                        Text("\(store.getUnsynced().count)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        api.syncLocations()
                    }) {
                        HStack {
                            Spacer()
                            Text(api.isSyncing ? "Syncing..." : "Sync Now")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(api.isSyncing)
                }
                
                Section(header: Text("Debug")) {
                    Button(action: {
                        store.markAllAsUnsynced()
                        api.syncLocations()
                    }) {
                        Text("Resync All Data")
                            .foregroundColor(.orange)
                    }
                    .disabled(api.isSyncing)
                    
                    Button(action: {
                        downloadingHistory = true
                        downloadProgress = 0
                        Task {
                            do {
                                let points = try await api.fetchAllHistory { count in
                                    downloadProgress = count
                                }
                                store.mergeLocations(points)
                            } catch {
                                print("Download failed: \(error)")
                            }
                            downloadingHistory = false
                        }
                    }) {
                        if downloadingHistory {
                             HStack {
                                ProgressView()
                                Text("Downloading... \(downloadProgress)")
                                    .foregroundColor(.blue)
                             }
                        } else {
                             Text("Download History from Server")
                                .foregroundColor(.blue)
                        }
                    }
                    .disabled(api.isSyncing || downloadingHistory)
                }
                
                Section(footer: Text("Fletcher syncs automatically in the background when significant location changes are detected.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Sync Status")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
