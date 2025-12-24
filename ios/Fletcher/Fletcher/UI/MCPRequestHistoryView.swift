import SwiftUI

struct MCPRequestHistoryView: View {
    @StateObject private var viewModel = MCPRequestHistoryViewModel()
    
    var body: some View {
        List {
            if viewModel.isLoading && viewModel.requests.isEmpty {
                ProgressView("Loading request history...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.requests.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No MCP Requests Yet")
                        .font(.headline)
                    Text("When your AI assistant uses Fletcher, requests will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowBackground(Color.clear)
            } else {
                ForEach(groupedRequests.keys.sorted(by: >), id: \.self) { date in
                    Section(header: Text(formatSectionDate(date))) {
                        ForEach(groupedRequests[date] ?? []) { request in
                            MCPRequestRow(request: request)
                        }
                    }
                }
                
                if viewModel.hasMore {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load More") {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Request History")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refresh()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }
    
    private var groupedRequests: [String: [MCPRequest]] {
        Dictionary(grouping: viewModel.requests) { request in
            Calendar.current.startOfDay(for: request.timestamp).ISO8601Format()
        }
    }
    
    private func formatSectionDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

struct MCPRequestRow: View {
    let request: MCPRequest
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: request.assistantIcon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.formattedEndpoint)
                        .font(.headline)
                    Text(request.assistantType.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(request.formattedTimestamp)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if request.locationCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption2)
                            Text("\(request.locationCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            
            if let params = request.queryParams, !params.isEmpty {
                Button(action: {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(isExpanded ? "Hide Details" : "Show Details")
                            .font(.caption)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                }
                
                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(params.keys.sorted()), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text("\(key):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(String(describing: params[key]?.value ?? ""))")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        if let responseTime = request.responseTimeMs {
                            HStack {
                                Text("Response time:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(responseTime)ms")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 30)
                }
            } else if let responseTime = request.responseTimeMs {
                Text("Response: \(responseTime)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
class MCPRequestHistoryViewModel: ObservableObject {
    @Published var requests: [MCPRequest] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMore = false
    
    private var currentOffset = 0
    private let pageSize = 50
    
    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        currentOffset = 0
        
        do {
            let response = try await APIClient.shared.fetchMCPRequestHistory(
                limit: pageSize,
                offset: 0
            )
            requests = response.logs
            hasMore = response.metadata.hasMore
            currentOffset = pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        
        do {
            let response = try await APIClient.shared.fetchMCPRequestHistory(
                limit: pageSize,
                offset: currentOffset
            )
            requests.append(contentsOf: response.logs)
            hasMore = response.metadata.hasMore
            currentOffset += pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoadingMore = false
    }
    
    func refresh() async {
        await loadInitial()
    }
}

#Preview {
    NavigationView {
        MCPRequestHistoryView()
    }
}
