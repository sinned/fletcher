import SwiftUI

struct LogsView: View {
    var body: some View {
        NavigationView {
            List {
                Text("No recent access logs")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Privacy Logs")
        }
    }
}
