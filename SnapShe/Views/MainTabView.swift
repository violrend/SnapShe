import SwiftUI

struct MainTabView: View {
    @State private var showVisualSearch = false
    @State private var pendingImage: UIImage? = nil

    var body: some View {
        HomeView(onVisualSearch: { image in
            pendingImage = image
            showVisualSearch = true
        })
        .sheet(isPresented: $showVisualSearch) {
            if let img = pendingImage {
                VisualSearchView(initialImage: img)
            }
        }
    }
}
