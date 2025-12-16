import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var locationStore: LocationStore
    @State private var viewMode: ViewMode = .list
    
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
                .padding()
                
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
            .navigationTitle("Location History")
        }
    }
}
