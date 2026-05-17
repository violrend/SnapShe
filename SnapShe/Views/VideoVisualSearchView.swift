import SwiftUI
import AVKit

/// Video yükleyip belirli bir frame'den visual search yapan view.
/// Snapshot'taki openVideoWorkspace + captureVideoFrameFile mantığını iOS'a taşır.
struct VideoVisualSearchView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = VisualSearchViewModel()

    /// Yerel veya uzak video URL'i
    let videoURL: URL
    /// Feed'deki videolar için sunucu path'i (örn. uploads/vid_xxx.mp4)
    let serverVideoPath: String?

    @State private var player: AVPlayer? = nil
    @State private var cropRect = CGRect(x: 0.12, y: 0.08, width: 0.76, height: 0.52)
    @State private var keyword = ""
    @State private var showSaveModal = false
    @State private var productToSave: Product? = nil
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any? = nil
    @State private var videoSize: CGSize = .zero
    @State private var statusMessage = "Video yükleniyor..."

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── TOOLBAR ──────────────────────────────────────
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
                        Text("Video Search")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                        Text(vm.isSearching ? "Searching…" : statusMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        Task { await captureAndSearch() }
                    } label: {
                        Text("Search")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(vm.isSearching || duration == 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.snapsheBorder).frame(height: 1)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // ── VIDEO FRAME + CROP ────────────────────
                        VideoCropView(
                            player: $player,
                            cropRect: $cropRect,
                            videoSize: $videoSize,
                            onCropChanged: { newCrop in
                                // auto-search tetiklenir
                                if duration > 0 {
                                    Task { await captureAndSearch(auto: true) }
                                }
                            }
                        )
                        .frame(height: UIScreen.main.bounds.width * 1.05)
                        .overlay(alignment: .bottom) {
                            Text("Drag or resize selected area")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(Color.snapsheBlack.opacity(0.82))
                                .clipShape(Capsule())
                                .padding(.bottom, 14)
                        }

                        // ── VIDEO TIMELINE ────────────────────────
                        if duration > 0 {
                            videoTimeline
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color(hex: "#111"))
                        }

                        // ── UPLOAD STATUS ─────────────────────────
                        if vm.isUploadingVideo {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white).scaleEffect(0.8)
                                Text("Uploading video to server…")
                                    .font(.system(size: 13)).foregroundStyle(Color(hex: "#aaa"))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(hex: "#1a1a1a"))
                        }
                        if let vErr = vm.videoUploadError {
                            SnapSheErrorBox(message: vErr)
                                .padding(.horizontal, 16).padding(.top, 8)
                        }

                        // ── SHOP SIMILAR PANEL ────────────────────
                        VStack(alignment: .leading, spacing: 0) {
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
                                        Task { await captureAndSearch() }
                                    }
                                    .onChange(of: keyword) { _, _ in
                                        Task { await captureAndSearch(auto: true, delay: 1.0) }
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
                                    Text("Pause on a frame, select the area, then press Search")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(hex: "#aaa"))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }

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
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .sheet(isPresented: $showSaveModal) {
            if let product = productToSave { SaveToCollectionView(product: product) }
        }
    }

    // MARK: - Video Timeline
    var videoTimeline: some View {
        HStack(spacing: 10) {
            Button {
                guard let p = player else { return }
                if isPlaying { p.pause(); isPlaying = false }
                else { p.play(); isPlaying = true }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
            }

            Text(formatTime(currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#aaa"))

            Slider(value: $currentTime, in: 0...max(duration, 0.01), step: 0.01) { editing in
                if !editing {
                    player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                    if isPlaying { player?.pause(); isPlaying = false }
                }
            }
            .tint(Color.snapshePurple)

            Text(formatTime(duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "#aaa"))
        }
    }

    // MARK: - Player setup
    func setupPlayer() {
        // Eğer remote URL ise önce local'e indir, sonra oynat
        if videoURL.scheme == "https" || videoURL.scheme == "http" {
            statusMessage = "Video downloading…"
            Task { await downloadAndPlay() }
        } else {
            setupLocalPlayer(url: videoURL)
        }

        // serverVideoPath varsa (feed'den açılan veya Instagram) upload etme
        if serverVideoPath != nil {
            vm.serverVideoPath = serverVideoPath ?? ""
        }
    }

    func downloadAndPlay() async {
        do {
            let (localURL, _) = try await URLSession.shared.download(from: videoURL)
            // Temp klasörüne taşı (uzantı ekle)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            try FileManager.default.moveItem(at: localURL, to: dest)
            await MainActor.run {
                statusMessage = "Video ready."
                setupLocalPlayer(url: dest)
                // serverVideoPath yoksa upload et
                if serverVideoPath == nil {
                    Task { await vm.uploadVideo(videoURL: dest, token: auth.token) }
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = "Video could not be downloaded: \(error.localizedDescription)"
            }
        }
    }

    func setupLocalPlayer(url: URL) {
        let p = AVPlayer(url: url)
        player = p

        // Observe current time
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
        }

        // Get duration
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let secs = p.currentItem?.duration.seconds ?? 0
                if secs.isFinite && secs > 0 {
                    await MainActor.run {
                        duration = secs
                        statusMessage = secs > 31
                            ? "Select a video with a maximum length of 30 seconds."
                            : "Pause on a frame, select the area, then press Search."
                    }
                    return
                }
            }
            // Son deneme: asset'ten yükle
            if let asset = p.currentItem?.asset,
               let dur = try? await asset.load(.duration),
               dur.seconds.isFinite && dur.seconds > 0 {
                await MainActor.run { duration = dur.seconds }
            }
        }

        // Local video ise upload et
        if serverVideoPath == nil && (url.scheme == "file" || url.isFileURL) {
            Task { await vm.uploadVideo(videoURL: url, token: auth.token) }
        }
    }

    func teardownPlayer() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
        player?.pause()
        player = nil
    }

    // MARK: - Capture frame + search
    func captureAndSearch(auto: Bool = false, delay: Double = 0) async {
        guard let p = player, duration > 0 else { return }

        // Pause during capture
        let wasPlaying = isPlaying
        p.pause(); isPlaying = false

        guard let frameImage = await captureFrame(from: p) else {
            statusMessage = "Frame not captured. Please try again."
            return
        }

        guard let frameData = frameImage.jpegData(compressionQuality: 0.92) else { return }

        if auto {
            vm.scheduleVideoSearch(frameData: frameData, crop: cropRect, keyword: keyword, token: auth.token, delay: delay)
        } else {
            await vm.performVideoSearch(frameData: frameData, crop: cropRect, keyword: keyword, token: auth.token)
        }

        if wasPlaying { p.play(); isPlaying = true }
    }

    func captureFrame(from player: AVPlayer) async -> UIImage? {
        guard let asset = player.currentItem?.asset else { return nil }
        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        return await withCheckedContinuation { cont in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
                if result == .succeeded, let cg = cgImage {
                    cont.resume(returning: UIImage(cgImage: cg))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    func formatTime(_ s: Double) -> String {
        let s = max(0, s)
        let m = Int(s) / 60
        let sec = Int(s) % 60
        return "\(m):\(String(format: "%02d", sec))"
    }
}

// MARK: - Video Crop View (video + crop overlay üst üste)
struct VideoCropView: View {
    @Binding var player: AVPlayer?
    @Binding var cropRect: CGRect
    @Binding var videoSize: CGSize
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
                // Video
                if let p = player {
                    VideoPlayerLayer(player: p)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Color.black
                }

                // Dim overlay
                dimOverlay(in: size)

                // Crop box
                let box = cropPx(in: size)
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)

                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: max(0, box.width - 4), height: max(0, box.height - 4))
                    .position(x: box.midX, y: box.midY)

                // Corners
                cornerHandle(at: CGPoint(x: box.minX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.minY))
                cornerHandle(at: CGPoint(x: box.minX, y: box.maxY))
                cornerHandle(at: CGPoint(x: box.maxX, y: box.maxY))

                // Gesture
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
        case .none:
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

// MARK: - AVPlayer UIKit bridge for SwiftUI
struct VideoPlayerLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
