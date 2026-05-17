import SwiftUI
import AVKit

// MARK: - DiscoverView

struct DiscoverView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = DiscoverViewModel()

    /// Binding to MainTabView's selectedTab so back button can switch to Home
    @Binding var selectedTab: Int

    @State private var currentIndex: Int = 0
    @State private var selectedFeedItem: FeedItem? = nil
    @State private var isSheetOpen = false
    @State private var isVisible = false
    @State private var autoTimer: Timer? = nil
    private let defaultInterval: TimeInterval = 6.0  // for photos
    @State private var currentItemDuration: TimeInterval? = nil  // set by SnapCard for videos

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if vm.isLoading && vm.items.isEmpty {
                loadingView
            } else if vm.items.isEmpty {
                emptyView
            } else {
                // Vertical paging with ScrollView
                GeometryReader { geo in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                                    SnapCard(
                                        item: item,
                                        isActive: currentIndex == index && isVisible && !isSheetOpen,
                                        isSheetOpen: currentIndex == index ? $isSheetOpen : .constant(false),
                                        onShop: {
                                            isSheetOpen = true
                                            stopAutoTimer()
                                            selectedFeedItem = item
                                            NotificationCenter.default.post(name: .discoverPause, object: nil)
                                        },
                                        onDurationKnown: { dur in
                                            if currentIndex == index {
                                                restartAutoTimer(duration: dur)
                                            }
                                        }
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .id(index)
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .onChange(of: currentIndex) { newIndex in
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                proxy.scrollTo(newIndex, anchor: .top)
                            }
                            // Duration will be reported by SnapCard via onDurationKnown
                            restartAutoTimer(duration: nil)
                            if newIndex >= vm.items.count - 2 {
                                Task { await vm.loadMore(token: auth.token) }
                            }
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                let dy = value.translation.height
                                let dx = value.translation.width
                                guard abs(dy) > abs(dx) else { return }
                                if dy < -50 && currentIndex < vm.items.count - 1 {
                                    currentIndex += 1
                                } else if dy > 50 && currentIndex > 0 {
                                    currentIndex -= 1
                                }
                            }
                    )
                }
                .ignoresSafeArea()
            }

            // Top bar — back button + title
            topBar
        }
        .toolbar(.hidden, for: .tabBar)
        .ignoresSafeArea(edges: .bottom)
        .task { await vm.load(token: auth.token) }
        .onAppear {
            isVisible = true
            startAutoTimer()
            NotificationCenter.default.post(name: .discoverResume, object: nil)
        }
        .onDisappear {
            isVisible = false
            stopAutoTimer()
            NotificationCenter.default.post(name: .discoverPause, object: nil)
        }
        .sheet(item: $selectedFeedItem) { item in
            if item.mediaType == .video, let url = item.mediaURL {
                VideoVisualSearchView(videoURL: url, serverVideoPath: item.video)
                    .onDisappear {
                        isSheetOpen = false
                        startAutoTimer()
                        NotificationCenter.default.post(name: .discoverResume, object: nil)
                        NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                    }
            } else {
                VisualSearchView(feedPhotoURL: item.mediaURL?.absoluteString, initialImage: nil)
                    .onDisappear {
                        isSheetOpen = false
                        startAutoTimer()
                        NotificationCenter.default.post(name: .discoverResume, object: nil)
                        NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                    }
            }
        }
    }

    // MARK: - Top Bar

    var topBar: some View {
        HStack(spacing: 12) {
            // Back to feed
            Button {
                stopAutoTimer()
                selectedTab = 0
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            Text("Discover")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            // Placeholder for symmetry
            Circle()
                .fill(Color.clear)
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.5), Color.clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Auto Timer

    func startAutoTimer() {
        stopAutoTimer()
        let interval = currentItemDuration ?? defaultInterval
        autoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                guard !vm.items.isEmpty else { return }
                withAnimation {
                    if currentIndex < vm.items.count - 1 {
                        currentIndex += 1
                    } else {
                        currentIndex = 0
                    }
                }
                // startAutoTimer will be called again via onChange(of: currentIndex) -> restartAutoTimer
            }
        }
    }

    func stopAutoTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    func restartAutoTimer(duration: TimeInterval? = nil) {
        currentItemDuration = duration
        stopAutoTimer()
        startAutoTimer()
    }

    // MARK: - Loading / Empty

    var loadingView: some View {
        VStack(spacing: 18) {
            ProgressView().tint(.white).scaleEffect(1.4)
            Text("Loading snaps…")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 52))
                .foregroundStyle(Color.white.opacity(0.3))
            Text("No snaps yet")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
            Text("Snaps shared by the community\nwill appear here.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - LoopingVideoPlayer

struct LoopingVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let isActive: Bool
    var onDurationKnown: ((TimeInterval) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: url)
        player.isMuted = false
        player.actionAtItemEnd = .none

        // Loop
        context.coordinator.loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        // Pause all players when discover hides or sheet opens
        context.coordinator.pauseObserver = NotificationCenter.default.addObserver(
            forName: .discoverPause,
            object: nil,
            queue: .main
        ) { _ in
            player.pause()
        }

        // Resume only the active player
        context.coordinator.resumeObserver = NotificationCenter.default.addObserver(
            forName: .discoverResume,
            object: nil,
            queue: .main
        ) { _ in
            if context.coordinator.isActive {
                player.play()
            }
        }

        // Report real video duration once loaded
        context.coordinator.durationObserver = player.currentItem?.observe(
            \.status, options: [.new]
        ) { [weak player] item, _ in
            guard item.status == .readyToPlay else { return }
            let dur = item.duration.seconds
            if dur.isFinite && dur > 0 {
                DispatchQueue.main.async {
                    context.coordinator.onDurationKnown?(dur)
                }
            }
        }
        context.coordinator.onDurationKnown = onDurationKnown
        context.coordinator.isActive = isActive
        context.coordinator.player = player

        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        vc.view.backgroundColor = .black
        if isActive { player.play() }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        guard let player = context.coordinator.player else { return }
        context.coordinator.isActive = isActive
        if isActive {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
            player.seek(to: .zero)
        }
    }

    class Coordinator {
        var player: AVPlayer?
        var loopObserver: Any?
        var pauseObserver: Any?
        var resumeObserver: Any?
        var durationObserver: NSKeyValueObservation?
        var onDurationKnown: ((TimeInterval) -> Void)?
        var isActive: Bool = false
        deinit {
            player?.pause()
            if let obs = loopObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = pauseObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = resumeObserver { NotificationCenter.default.removeObserver(obs) }
            durationObserver?.invalidate()
        }
    }
}

// MARK: - SnapCard

struct SnapCard: View {
    let item: FeedItem
    let isActive: Bool
    @Binding var isSheetOpen: Bool
    let onShop: () -> Void
    var onDurationKnown: ((TimeInterval) -> Void)? = nil

    @State private var showProfile = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Media
                if item.mediaType == .video, let url = item.mediaURL {
                    LoopingVideoPlayer(url: url, isActive: isActive, onDurationKnown: onDurationKnown)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else if let url = item.coverURL ?? item.mediaURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            placeholderBg.frame(width: geo.size.width, height: geo.size.height)
                        default:
                            placeholderBg.frame(width: geo.size.width, height: geo.size.height)
                                .overlay(ProgressView().tint(.white.opacity(0.5)))
                        }
                    }
                } else {
                    placeholderBg.frame(width: geo.size.width, height: geo.size.height)
                }

                // Bottom overlay
                bottomOverlay
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .sheet(isPresented: $showProfile) {
                PublicProfileView(username: item.username)
            }
        }
    }

    var placeholderBg: some View {
        Rectangle().fill(LinearGradient(
            colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }

    var bottomOverlay: some View {
        ZStack(alignment: .bottom) {
            // Gradient
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.15), Color.black.opacity(0.7)],
                startPoint: .center, endPoint: .bottom
            )
            .frame(height: 300)

            VStack(alignment: .leading, spacing: 0) {
                // User info — tappable
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.snapshePurple, Color.snapshePink],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 40, height: 40)
                        Text(String(item.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name.isEmpty ? item.username : item.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text("@\(item.username)")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: item.mediaType == .video ? "play.fill" : "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(item.mediaType == .video ? "Video" : "Photo")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(item.mediaType == .video
                        ? Color.snapshePurple.opacity(0.85)
                        : Color.snapsheBlack.opacity(0.75))
                    .clipShape(Capsule())
                }
                .contentShape(Rectangle())
                .onTapGesture { showProfile = true }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

                // Shop button
                Button(action: onShop) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                        Text("Find similar products")
                            .font(.system(size: 15, weight: .black))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - DiscoverViewModel

@MainActor
class DiscoverViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    @Published var isLoading = false
    private var didLoad = false
    private var allItems: [FeedItem] = []

    func load(token: String) async {
        guard !didLoad else { return }
        isLoading = true
        if let response = try? await APIService.shared.fetchFeed(token: token), response.ok {
            let raw = response.photos ?? []
            var seen = Set<String>()
            allItems = raw.filter { seen.insert($0.id).inserted }
            items = allItems
        }
        isLoading = false
        didLoad = true
    }

    func loadMore(token: String) async {
        // No-op: backend returns same feed, duplicates prevented
    }
}
