import SwiftUI

// Wrapper: UIImage'ı Identifiable yapıyoruz ki sheet(item:) kullanabilelim
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MainTabView: View {
    @State private var pendingImage: IdentifiableImage? = nil

    var body: some View {
        HomeView(onVisualSearch: { image in
            pendingImage = IdentifiableImage(image: image)
        })
        .sheet(item: $pendingImage) { wrapper in
            VisualSearchView(initialImage: wrapper.image)
                .onDisappear {
                    NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                }
        }
    }
}
