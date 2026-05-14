import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var photos: [FeedPhoto] = []
    @Published var isLoading = false
    @Published var error: String? = nil
    
    func loadFeed(token: String) async {
        isLoading = true
        error = nil
        do {
            let response = try await APIService.shared.fetchFeed(token: token)
            if response.ok {
                photos = response.photos ?? []
            } else {
                error = response.error ?? "Failed to load feed."
            }
        } catch {
            self.error = "Network error."
        }
        isLoading = false
    }
}
