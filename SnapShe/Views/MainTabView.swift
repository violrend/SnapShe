import SwiftUI

// Wrapper: UIImage'ı Identifiable yapıyoruz ki sheet(item:) kullanabilelim
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MainTabView: View {
    @State private var pendingImage: IdentifiableImage? = nil
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {

            // MARK: Ana Sayfa
            HomeView(onVisualSearch: { image in
                pendingImage = IdentifiableImage(image: image)
            })
            .tabItem {
                Label("Ana Sayfa", systemImage: "house.fill")
            }
            .tag(0)

            // MARK: Keşfet
            DiscoverView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Keşfet", systemImage: "play.rectangle.fill")
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
