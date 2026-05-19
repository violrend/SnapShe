import SwiftUI

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MainTabView: View {
    @State private var pendingImage: IdentifiableImage? = nil
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Home
            HomeView(onVisualSearch: { image in
                pendingImage = IdentifiableImage(image: image)
            })
            .tabItem {
                Label("Feed", systemImage: "house.fill")
            }
            .tag(0)

            // MARK: Discover
            DiscoverView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Discover", systemImage: "play.rectangle.fill")
                }
                .tag(1)
        }
        .tint(Color.snapshePurple)
        .sheet(item: $pendingImage) { wrapper in
            VisualSearchView(initialImage: wrapper.image)
                .onDisappear {
                    NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                }
        }
    }
}
