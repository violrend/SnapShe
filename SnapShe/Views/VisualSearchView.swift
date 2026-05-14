import SwiftUI

struct VisualSearchView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = VisualSearchViewModel()

    var feedPhotoURL: String? = nil
    var initialImage: UIImage? = nil

    @State private var keyword = ""
    @State private var cropRect = CGRect(x: 0.12, y: 0.08, width: 0.76, height: 0.52)
    @State private var showSaveModal = false
    @State private var productToSave: Product? = nil

    var imageData: Data? { initialImage?.jpegData(compressionQuality: 0.85) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── TOOLBAR (matches .lens-toolbar) ──────────────
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle().fill(Color.snapsheGray).frame(width: 36, height: 36)
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                        }
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Visual Search")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                        Text(vm.isSearching ? "Searching…" : "Photo ready. Drag the selection box.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                    }

                    Spacer()

                    Button {
                        Task {
                            await vm.performSearch(
                                imageData: imageData, feedURL: feedPhotoURL,
                                crop: cropRect, keyword: keyword, token: auth.token
                            )
                        }
                    } label: {
                        Text("Search")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.snapsheBorder).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── IMAGE + CROP (matches .left-lens / .image-frame) ──
                        ImageCropView(
                            image: initialImage,
                            imageURL: feedPhotoURL.flatMap(URL.init),
                            cropRect: $cropRect,
                            onCropChanged: { newCrop in
                                vm.scheduleSearch(
                                    imageData: imageData, feedURL: feedPhotoURL,
                                    crop: newCrop, keyword: keyword, token: auth.token, delay: 0.7
                                )
                            }
                        )
                        .frame(height: UIScreen.main.bounds.width * 1.05)
                        .overlay(alignment: .bottom) {
                            // "Drag or resize selected area" hint (matches site)
                            Text("Drag or resize selected area")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(Color.snapsheBlack.opacity(0.82))
                                .clipShape(Capsule())
                                .padding(.bottom, 14)
                        }

                        // ── SHOP SIMILAR PANEL ────────────────────
                        VStack(alignment: .leading, spacing: 0) {

                            // Panel title (matches .panel-title)
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shop similar")
                                        .font(.system(size: 22, weight: .black))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Text("Products update automatically when you change the selected area.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(hex: "#888"))
                                }
                                Spacer()
                                if vm.isSearching {
                                    ProgressView().tint(Color.snapshePurple).scaleEffect(0.9)
                                } else if !vm.products.isEmpty {
                                    Text("\(vm.products.count)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(hex: "#888"))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 12)

                            // Keyword bar
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(hex: "#999"))
                                TextField("Refine search (optional)", text: $keyword)
                                    .font(.system(size: 15))
                                    .onSubmit {
                                        Task { await vm.performSearch(imageData: imageData, feedURL: feedPhotoURL, crop: cropRect, keyword: keyword, token: auth.token) }
                                    }
                                    .onChange(of: keyword) { _, _ in
                                        vm.scheduleSearch(imageData: imageData, feedURL: feedPhotoURL, crop: cropRect, keyword: keyword, token: auth.token, delay: 1.0)
                                    }
                            }
                            .padding(13)
                            .background(Color.snapsheGray)
                            .clipShape(Capsule())
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)

                            if let error = vm.error {
                                SnapSheErrorBox(message: error).padding(.horizontal, 16).padding(.bottom, 12)
                            }

                            if vm.products.isEmpty && !vm.isSearching && vm.error == nil {
                                VStack(spacing: 14) {
                                    Image(systemName: "sparkle.magnifyingglass")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color(hex: "#ccc"))
                                    Text("Results will appear here")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(hex: "#aaa"))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }

                            // Product grid (matches .masonry-grid)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(vm.products) { product in
                                    ProductCard(product: product) {
                                        productToSave = product
                                        showSaveModal = true
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 32)
                        }
                        .background(Color.white)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
        .task {
            await vm.performSearch(imageData: imageData, feedURL: feedPhotoURL, crop: cropRect, keyword: "", token: auth.token)
        }
        .sheet(isPresented: $showSaveModal) {
            if let product = productToSave { SaveToCollectionView(product: product) }
        }
    }
}

// MARK: - Interactive Crop View (matches site's drag-and-resize crop)
struct ImageCropView: View {
    let image: UIImage?
    let imageURL: URL?
    @Binding var cropRect: CGRect
    let onCropChanged: (CGRect) -> Void

    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var cropStart: CGRect = .zero
    @State private var activeCorner: CropCorner? = nil

    enum CropCorner: CaseIterable { case tl, tr, bl, br }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Base image
                Group {
                    if let img = image {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else if let url = imageURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { Color.snapsheBlack }
                        }
                    } else {
                        Color.snapsheBlack
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()

                // Dim layer
                dimOverlay(in: size)

                // Crop box
                let box = cropPx(in: size)
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)

                // Dashed border inside
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: box.width - 4, height: box.height - 4)
                    .position(x: box.midX, y: box.midY)

                // Corner handles (matches .corner tl/tr/bl/br)
                cornerHandle(at: CGPoint(x: box.minX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.minX, y: box.maxY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.maxY))

                // Drag gesture layer
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { val in
                                if !isDragging {
                                    isDragging = true
                                    dragStart = val.startLocation
                                    cropStart = cropRect
                                    activeCorner = detectCorner(at: val.startLocation, in: size)
                                }
                                updateCrop(val: val, in: size)
                            }
                            .onEnded { _ in
                                isDragging = false
                                activeCorner = nil
                                onCropChanged(cropRect)
                            }
                    )
            }
        }
        .background(Color.black)
    }

    func dimOverlay(in size: CGSize) -> some View {
        let box = cropPx(in: size)
        return Color.black.opacity(0.5)
            .mask(
                Rectangle().fill(.white)
                    .overlay(
                        Rectangle()
                            .frame(width: box.width, height: box.height)
                            .position(x: box.midX, y: box.midY)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
    }

    func cornerHandle(at pos: CGPoint) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 18, height: 18)
            Circle().stroke(Color.white.opacity(0.4), lineWidth: 2).frame(width: 26, height: 26)
        }
        .position(x: pos.x, y: pos.y)
        .shadow(color: .black.opacity(0.3), radius: 4)
    }

    func cropPx(in size: CGSize) -> CGRect {
        CGRect(x: cropRect.minX * size.width, y: cropRect.minY * size.height,
               width: cropRect.width * size.width, height: cropRect.height * size.height)
    }

    func detectCorner(at pt: CGPoint, in size: CGSize) -> CropCorner? {
        let box = cropPx(in: size)
        let d: CGFloat = 34
        let pairs: [(CGPoint, CropCorner)] = [
            (CGPoint(x: box.minX, y: box.minY), .tl),
            (CGPoint(x: box.maxX, y: box.minY), .tr),
            (CGPoint(x: box.minX, y: box.maxY), .bl),
            (CGPoint(x: box.maxX, y: box.maxY), .br),
        ]
        return pairs.first { abs(pt.x - $0.0.x) < d && abs(pt.y - $0.0.y) < d }?.1
    }

    func updateCrop(val: DragGesture.Value, in size: CGSize) {
        let dx = (val.location.x - dragStart.x) / size.width
        let dy = (val.location.y - dragStart.y) / size.height
        let minSize: CGFloat = 0.1
        var r = cropStart

        switch activeCorner {
        case .none: // move
            r.origin.x = max(0, Swift.min(cropStart.minX + dx, 1 - cropStart.width))
            r.origin.y = max(0, Swift.min(cropStart.minY + dy, 1 - cropStart.height))
        case .tl:
            let nx = Swift.min(cropStart.maxX - minSize, cropStart.minX + dx)
            let ny = Swift.min(cropStart.maxY - minSize, cropStart.minY + dy)
            r = CGRect(x: max(0,nx), y: max(0,ny), width: cropStart.maxX - max(0,nx), height: cropStart.maxY - max(0,ny))
        case .tr:
            let ny = Swift.min(cropStart.maxY - minSize, cropStart.minY + dy)
            r = CGRect(x: cropStart.minX, y: max(0,ny), width: Swift.min(cropStart.width+dx, 1-cropStart.minX), height: cropStart.maxY - max(0,ny))
        case .bl:
            let nx = Swift.min(cropStart.maxX - minSize, cropStart.minX + dx)
            r = CGRect(x: max(0,nx), y: cropStart.minY, width: cropStart.maxX - max(0,nx), height: Swift.min(cropStart.height+dy, 1-cropStart.minY))
        case .br:
            r = CGRect(x: cropStart.minX, y: cropStart.minY, width: Swift.min(cropStart.width+dx, 1-cropStart.minX), height: Swift.min(cropStart.height+dy, 1-cropStart.minY))
        case .some(_):
            break
        }
        cropRect = r
    }
}
