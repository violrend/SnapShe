import SwiftUI

@MainActor
class CollectionsViewModel: ObservableObject {
    @Published var collections: [SnapCollection] = []
    @Published var isLoading = false
    @Published var showCreateSheet = false
    @Published var newCollectionTitle = ""

    func load(token: String) async {
        isLoading = true
        if let r = try? await APIService.shared.fetchCollections(token: token) {
            collections = r.collections ?? []
        }
        isLoading = false
    }

    func create(token: String) async {
        guard !newCollectionTitle.isEmpty else { return }
        if let r = try? await APIService.shared.createCollection(title: newCollectionTitle, token: token),
           r.ok, let c = r.collection {
            collections.insert(c, at: 0)
        }
        newCollectionTitle = ""; showCreateSheet = false
    }
}

struct CollectionsView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = CollectionsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header (matches .collections-head)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My Collections")
                            .font(.system(size: 28, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Saved products from your visual searches.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                    Spacer()
                    Button {
                        vm.showCreateSheet = true
                    } label: {
                        Label("Create", systemImage: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                if vm.isLoading && vm.collections.isEmpty {
                    Spacer()
                    ProgressView().tint(Color.snapshePurple)
                    Spacer()
                } else if vm.collections.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "heart.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(hex: "#ddd"))
                        Text("No collections yet")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Create your first collection and save products from visual search.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: "#888"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 20) {
                            ForEach(vm.collections) { c in
                                CollectionBoardCard(collection: c)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
            .background(Color.white)
        }
        .task { if vm.collections.isEmpty { await vm.load(token: auth.token) } }
        .sheet(isPresented: $vm.showCreateSheet) {
            NavigationStack {
                VStack(spacing: 20) {
                    SnapSheTextField(placeholder: "Collection name", text: $vm.newCollectionTitle, icon: "folder")
                    SnapShePrimaryButton(title: "Create") {
                        Task { await vm.create(token: auth.token) }
                    }
                    .disabled(vm.newCollectionTitle.isEmpty)
                    Spacer()
                }
                .padding(24)
                .background(Color.white)
                .navigationTitle("New Collection")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { vm.showCreateSheet = false } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color(hex: "#ccc"))
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// Matches .board-card
struct CollectionBoardCard: View {
    let collection: SnapCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(collection.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.snapsheBlack)
                Spacer()
                Text("\(collection.products.count) saved products")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#aaa"))
            }

            if collection.products.isEmpty {
                Text("No products saved yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#bbb"))
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(collection.products) { p in
                            SavedProductTile(product: p)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.snapsheBlack.opacity(0.07), radius: 10, y: 2)
    }
}

struct SavedProductTile: View {
    let product: SavedProduct

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AsyncImage(url: product.imageURL) { phase in
                if case .success(let img) = phase { img.resizable().scaledToFill() }
                else { Color.snapsheGray }
            }
            .frame(width: 100, height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(product.price)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.snapsheBlack)
            Text(product.title)
                .font(.system(size: 11))
                .foregroundStyle(Color(hex: "#888"))
                .lineLimit(2).frame(width: 100)
        }
        .onTapGesture { if let url = APIService.affiliateURL(for: product.link) { UIApplication.shared.open(url) } }
    }
}
