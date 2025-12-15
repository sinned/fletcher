import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var locationStore: LocationStore
    
    var body: some View {
        NavigationView {
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
                                Image(systemName: "checkmark.cloud.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "cloud.fill")
                                    .foregroundColor(.gray)
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
            .navigationTitle("Location History")
        }
    }
}
