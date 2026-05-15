import SwiftUI
import Combine

extension Notification.Name {
    static let feedNeedsRefresh = Notification.Name("feedNeedsRefresh")
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var photos: [FeedPhoto] = []
    @Published var isLoading = false
    @Published var error: String? = nil

    private var refreshTask: Task<Void, Never>? = nil

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

    /// VisualSearchView kapanınca bu çağrılır, feed'i sessizce günceller
    func silentRefresh(token: String) {
        refreshTask?.cancel()
        refreshTask = Task {
            guard let response = try? await APIService.shared.fetchFeed(token: token),
                  response.ok else { return }
            guard !Task.isCancelled else { return }
            photos = response.photos ?? []
        }
    }
}
