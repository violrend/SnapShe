import SwiftUI

struct SaveToCollectionView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let product: Product

    @State private var collections: [SnapCollection] = []
    @State private var isLoading = true
    @State private var newTitle = ""
    @State private var isSaving = false
    @State private var savedMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Product preview strip
                HStack(spacing: 14) {
                    AsyncImage(url: product.thumbnailURL) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Color.snapsheGray }
                    }
                    .frame(width: 64, height: 64).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(product.price)
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text(product.title)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#666"))
                            .lineLimit(2)
                        Text(product.source)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#aaa"))
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.snapsheGray)

                if !savedMessage.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(savedMessage).font(.system(size: 14, weight: .semibold)).foregroundStyle(.green)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.07))
                }

                List {
                    Section {
                        HStack(spacing: 12) {
                            TextField("New collection name", text: $newTitle)
                                .font(.system(size: 15))
                            Button {
                                Task { await createAndSave() }
                            } label: {
                                Text("Create & Save")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.snapsheRed)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            .disabled(newTitle.isEmpty || isSaving)
                        }
                    } header: {
                        Text("Create new").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "#aaa"))
                    }

                    Section {
                        if isLoading {
                            HStack { Spacer(); ProgressView().tint(Color.snapshePurple); Spacer() }
                        } else if collections.isEmpty {
                            Text("No collections yet.")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#bbb"))
                        } else {
                            ForEach(collections) { col in
                                Button {
                                    Task { await save(to: col) }
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle().fill(snapsheGradient).frame(width: 36, height: 36)
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(col.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Color.snapsheBlack)
                                            Text("\(col.products.count) items")
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color(hex: "#aaa"))
                                        }
                                        Spacer()
                                        if isSaving {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundStyle(Color.snapsheBlack)
                                        }
                                    }
                                }
                                .disabled(isSaving)
                            }
                        }
                    } header: {
                        Text("Save to existing").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "#aaa"))
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color.white)
            .navigationTitle("Save to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color(hex: "#ccc"))
                    }
                }
            }
        }
        .task { await loadCollections() }
    }

    func loadCollections() async {
        let r = try? await APIService.shared.fetchCollections(token: auth.token)
        collections = r?.collections ?? []
        isLoading = false
    }

    func save(to collection: SnapCollection) async {
        isSaving = true
        _ = try? await APIService.shared.saveProduct(collectionId: collection.id, product: product, token: auth.token)
        savedMessage = "Saved to \"\(collection.title)\"!"
        isSaving = false
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        dismiss()
    }

    func createAndSave() async {
        isSaving = true
        let r = try? await APIService.shared.createCollection(title: newTitle, token: auth.token)
        if let col = r?.collection {
            _ = try? await APIService.shared.saveProduct(collectionId: col.id, product: product, token: auth.token)
            savedMessage = "Saved to \"\(col.title)\"!"
        }
        newTitle = ""; isSaving = false
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        dismiss()
    }
}
