import SwiftUI
import Combine

extension Notification.Name {
    static let feedNeedsRefresh = Notification.Name("feedNeedsRefresh")
    static let discoverPause = Notification.Name("discoverPause")
    static let discoverResume = Notification.Name("discoverResume")
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

    func silentRefresh(token: String) async {
        guard let response = try? await APIService.shared.fetchFeed(token: token),
              response.ok else { return }
        photos = response.photos ?? []
    }
}

// MARK: - Following Feed ViewModel

@MainActor
class FollowingFeedViewModel: ObservableObject {
    @Published var photos: [FeedItem] = []
    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var isEmpty = false

    func loadFeed(token: String) async {
        isLoading = true
        error = nil
        isEmpty = false
        do {
            let response = try await APIService.shared.fetchFollowingFeed(token: token)
            if response.ok {
                let items = response.photos ?? []
                photos = items
                isEmpty = items.isEmpty
            } else {
                error = response.error ?? "Failed to load feed."
            }
        } catch {
            self.error = "Network error."
        }
        isLoading = false
    }
}
