import SwiftUI
import PhotosUI
import AVKit

struct HomeView: View {
    @EnvironmentObject var auth: AuthManager
    @StateObject private var vm = HomeViewModel()

    let onVisualSearch: (UIImage) -> Void

    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var videoPickerItem: PhotosPickerItem? = nil
    @State private var showImagePicker = false
    @State private var showVideoPicker = false
    @State private var showCamera = false
    @State private var showSourcePicker = false
    @State private var selectedFeedItem: FeedItem? = nil
    @State private var showCollections = false
    @State private var showProfile = false
    @State private var searchText = ""
    @State private var searchResults: [SnapUser] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil

    @State private var videoForSearch: URL? = nil
    @State private var showVideoSearch = false

    @State private var showInstagramFetch = false
    @State private var instagramImageURL: String? = nil
    @State private var pendingInstagramVideoURL: URL? = nil

    let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    @StateObject private var followingVM = FollowingFeedViewModel()
    @State private var selectedFeedTab: FeedTab = .forYou
    @State private var showNotifications = false
    @State private var unreadCount: Int = 0

    enum FeedTab { case forYou, following }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Divider()

                if !searchText.isEmpty {
                    searchResultsView
                } else {
                    feedTabPicker
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    if selectedFeedTab == .forYou {
                        if vm.isLoading && vm.photos.isEmpty {
                            Spacer()
                            ProgressView().tint(Color.snapshePurple)
                            Spacer()
                        } else if vm.photos.isEmpty {
                            emptyStateView
                        } else {
                            feedView
                        }
                    } else {
                        followingFeedView
                    }
                }
            }
            .background(Color.white)
            .sheet(isPresented: $showCollections) { CollectionsView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
        }
        .task { await vm.loadFeed(token: auth.token) }
        .task(id: auth.token) {
            while !Task.isCancelled {
                if let r = try? await APIService.shared.fetchNotifications(token: auth.token) {
                    unreadCount = r.unreadCount ?? 0
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView(unreadCount: $unreadCount)
                .environmentObject(auth)
        }
        .onReceive(NotificationCenter.default.publisher(for: .feedNeedsRefresh)) { _ in
            Task {
                await vm.silentRefresh(token: auth.token)
                if selectedFeedTab == .following {
                    await followingVM.loadFeed(token: auth.token)
                }
            }
        }
        .confirmationDialog("Upload", isPresented: $showSourcePicker) {
            Button("Camera") { showCamera = true }
            Button("Photo Library") { showImagePicker = true }
            Button("Video Library") { showVideoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showImagePicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onVisualSearch(image)
                }
                photoPickerItem = nil
            }
        }
        .photosPicker(isPresented: $showVideoPicker, selection: $videoPickerItem, matching: .videos)
        .onChange(of: videoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: VideoTransferable.self) {
                    videoForSearch = movie.url
                    showVideoSearch = true
                }
                videoPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                showCamera = false
                onVisualSearch(image)
            }
        }
        .sheet(item: $selectedFeedItem) { item in
            if item.mediaType == .video, let url = item.mediaURL {
                VideoVisualSearchView(videoURL: url, serverVideoPath: item.video)
                    .onDisappear {
                        NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                    }
            } else {
                VisualSearchView(feedPhotoURL: item.mediaURL?.absoluteString, initialImage: nil)
                    .onDisappear {
                        NotificationCenter.default.post(name: .feedNeedsRefresh, object: nil)
                    }
            }
        }
        .fullScreenCover(isPresented: $showVideoSearch) {
            if let url = videoForSearch {
                let serverPath = makeServerPath(from: url)
                VideoVisualSearchView(videoURL: url, serverVideoPath: serverPath)
            }
        }
        .sheet(isPresented: $showInstagramFetch) {
            InstagramFetchView(onResult: { result in
                switch result {
                case .image(let url):
                    instagramImageURL = url

                case .video(let urlStr):
                    if let url = URL(string: urlStr) {
                        pendingInstagramVideoURL = url
                    }
                }
            })
            .environmentObject(auth)
        }
        .sheet(item: Binding(
            get: { instagramImageURL.map { IdentifiableString(value: $0) } },
            set: { if $0 == nil { instagramImageURL = nil } }
        )) { item in
            VisualSearchView(feedPhotoURL: item.value, initialImage: nil)
        }
        .onChange(of: pendingInstagramVideoURL) { _, url in
            guard url != nil else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let url = pendingInstagramVideoURL {
                    videoForSearch = url
                    showVideoSearch = true
                    pendingInstagramVideoURL = nil
                }
            }
        }
    }

    var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SnapSheBrandView(size: 34)
                Spacer()

                Button { showProfile = true } label: {
                    SnapSheProfileChip(user: auth.currentUser)
                }
                .buttonStyle(.plain)

                // Bell notification button
                Button { showNotifications = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.snapsheBlack)
                        if unreadCount > 0 {
                            Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                }

                Button("Collections") { showCollections = true }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.snapsheGray)
                    .foregroundStyle(Color.snapsheBlack)
                    .clipShape(Capsule())

                Button("Logout") {
                    Task {
                        try? await APIService.shared.logout(token: auth.token)
                        auth.logout()
                    }
                }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.snapsheGray)
                .foregroundStyle(Color.snapsheBlack)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(hex: "#888"))

                    TextField("Search users...", text: $searchText)
                        .font(.system(size: 16))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: searchText) { _, q in
                            searchTask?.cancel()

                            if q.isEmpty {
                                searchResults = []
                                return
                            }

                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                guard !Task.isCancelled else { return }
                                await performSearch(q)
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "#ccc"))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.snapsheGray)
                .clipShape(Capsule())

                Button { showSourcePicker = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.snapsheBlack)
                            .frame(width: 40, height: 40)

                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    }
                }

                Button { showVideoPicker = true } label: {
                    ZStack {
                        Circle()
                            .fill(Color.snapshePurple)
                            .frame(width: 40, height: 40)

                        Image(systemName: "video.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }

                Button { showInstagramFetch = true } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#d62976"), Color(hex: "#962fbf")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)

                        Image(systemName: "camera")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.white)
    }

    var searchResultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(Color.snapshePurple)
                            .padding(24)
                        Spacer()
                    }
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 40)

                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: "#ddd"))

                        Text("No users found")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "#aaa"))

                        Text("Try a different name or username.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#ccc"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                } else {
                    Text("Results")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "#aaa"))
                        .padding(.horizontal, 18)
                        .padding(.top, 14)
                        .padding(.bottom, 6)

                    ForEach(searchResults) { user in
                        UserSearchRow(user: user)
                        Divider().padding(.horizontal, 18)
                    }
                }
            }
        }
        .background(Color.white)
    }

    var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.snapsheBlack)
                    .frame(width: 80, height: 80)

                Image(systemName: "viewfinder")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("Shop from any photo or video")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color.snapsheBlack)
                .multilineTextAlignment(.center)

            Text("Upload a photo or video, select an area, and discover visually similar products.")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#888"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            HStack(spacing: 12) {
                Button { showSourcePicker = true } label: {
                    Label("Upload photo", systemImage: "camera.viewfinder")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(Color.snapsheBlack)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button { showVideoPicker = true } label: {
                    Label("Upload video", systemImage: "video.fill")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(Color.snapshePurple)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .background(Color.white)
    }

    var feedView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Visual fashion discovery")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.snapsheBlack.opacity(0.07))
                        .clipShape(Capsule())

                    Text("Tap to shop the look")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(Color.snapsheBlack)

                    Text("Tap a photo or video to open visual search and find similar products.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#888"))

                    HStack(spacing: 10) {
                        Button { showSourcePicker = true } label: {
                            Label("Photo", systemImage: "camera.viewfinder")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.snapsheBlack)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

                        Button { showVideoPicker = true } label: {
                            Label("Video", systemImage: "video.fill")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.snapshePurple)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)

                MasonryFeedGrid(items: vm.photos) { item in
                    FeedItemCard(item: item) {
                        selectedFeedItem = item
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
        }
        .refreshable {
            await vm.loadFeed(token: auth.token)
        }
        .background(Color.white)
    }

    // MARK: - Feed Tab Picker

    var feedTabPicker: some View {
        HStack(spacing: 0) {
            feedTabButton(title: "For You", tab: .forYou)
            feedTabButton(title: "Following", tab: .following)
        }
        .padding(.horizontal, 18)
    }

    func feedTabButton(title: String, tab: FeedTab) -> some View {
        Button {
            if selectedFeedTab != tab {
                selectedFeedTab = tab
                if tab == .following && followingVM.photos.isEmpty && !followingVM.isLoading {
                    Task { await followingVM.loadFeed(token: auth.token) }
                }
            }
        } label: {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: selectedFeedTab == tab ? .bold : .regular))
                    .foregroundStyle(selectedFeedTab == tab ? Color.snapsheBlack : Color(hex: "#999"))
                Rectangle()
                    .fill(selectedFeedTab == tab ? Color.snapshePurple : Color.clear)
                    .frame(height: 2)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Following Feed View

    var followingFeedView: some View {
        Group {
            if followingVM.isLoading && followingVM.photos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().tint(Color.snapshePurple)
                    Spacer()
                }
            } else if followingVM.isEmpty {
                followingEmptyView
            } else {
                ScrollView(showsIndicators: false) {
                    MasonryFeedGrid(items: followingVM.photos) { item in
                        FeedItemCard(item: item) {
                            selectedFeedItem = item
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await followingVM.loadFeed(token: auth.token)
                }
                .background(Color.white)
            }
        }
    }

    var followingEmptyView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#DDD"))
            Text("Follow people to see their posts")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(Color.snapsheBlack)
                .multilineTextAlignment(.center)
            Text("Search for users and follow them to see their visual searches and uploads here.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#888"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    func performSearch(_ q: String) async {
        isSearching = true
        let r = try? await APIService.shared.searchUsers(query: q, token: auth.token)
        searchResults = r?.users ?? []
        isSearching = false
    }

    private func makeServerPath(from url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        let base = APIService.baseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var path = url.absoluteString

        if path.hasPrefix(base) {
            path = String(path.dropFirst(base.count))
        }

        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

// MARK: - User Search Row

struct UserSearchRow: View {
    let user: SnapUser
    @State private var showProfile = false

    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 14) {
                AvatarCircle(user: user, size: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.snapsheBlack)

                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#888"))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#ccc"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            PublicProfileView(username: user.username)
        }
    }
}

// MARK: - Feed Item Card

struct FeedItemCard: View {
    let item: FeedItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let url = item.coverURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFit()

                            case .failure:
                                Color.snapsheGray
                                    .frame(height: 160)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    )

                            default:
                                Color.snapsheGray
                                    .frame(height: 160)
                                    .shimmering()
                            }
                        }
                    } else if item.mediaType == .video {
                        Color(hex: "#1a1a1a")
                            .frame(height: 180)
                            .overlay(
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white.opacity(0.7))
                            )
                    } else {
                        Color.snapsheGray
                            .frame(height: 160)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    }
                }

                HStack(spacing: 5) {
                    if item.mediaType == .video {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                    }

                    Text(item.mediaType == .video ? "Video Search" : "Visual Search")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    item.mediaType == .video
                    ? Color.snapshePurple.opacity(0.9)
                    : Color.snapsheBlack.opacity(0.75)
                )
                .clipShape(Capsule())
                .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

typealias FeedPhotoCard = FeedItemCard

// MARK: - Masonry Grid

struct MasonryFeedGrid<Content: View>: View {
    let items: [FeedItem]
    let content: (FeedItem) -> Content

    init(items: [FeedItem], @ViewBuilder content: @escaping (FeedItem) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            LazyVStack(spacing: 6) {
                ForEach(Array(items.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element })) { item in
                    content(item)
                }
            }

            LazyVStack(spacing: 6) {
                ForEach(Array(items.enumerated().filter { $0.offset % 2 == 1 }.map { $0.element })) { item in
                    content(item)
                }
            }
        }
    }
}

// MARK: - VideoTransferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            try FileManager.default.copyItem(at: received.file, to: dest)

            return VideoTransferable(url: dest)
        }
    }
}

// MARK: - Instagram Fetch Result

enum InstagramFetchResult {
    case image(url: String)
    case video(url: String)
}

// MARK: - InstagramFetchView

struct InstagramFetchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var auth: AuthManager

    var onResult: (InstagramFetchResult) -> Void

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // Handle bar
            Capsule()
                .fill(Color(hex: "#DDDDDD"))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#d62976"), Color(hex: "#962fbf")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: "camera")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search from Instagram")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.snapsheBlack)
                    Text("Paste a post or Reels link")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#888"))
                }
                Spacer()

                Button { dismiss() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F0F0F0"))
                            .frame(width: 30, height: 30)
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "#666"))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // URL Input
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#999"))

                    TextField("https://www.instagram.com/reel/...", text: $urlText)
                        .font(.system(size: 15))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($inputFocused)
                        .submitLabel(.go)
                        .onSubmit { Task { await fetchInstagram() } }

                    if !urlText.isEmpty {
                        Button { urlText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "#CCC"))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color(hex: "#F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task { await fetchInstagram() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.snapsheBlack)
                            .frame(width: 56, height: 50)
                        if isLoading {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(isLoading || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)

            // Error message
            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(err)
                        .font(.system(size: 13))
                }
                .foregroundStyle(Color(hex: "#E53935"))
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Paste from clipboard button
            if UIPasteboard.general.hasStrings {
                Button {
                    if let str = UIPasteboard.general.string {
                        urlText = str
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12))
                        Text("Paste from clipboard")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "#555"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#F0F0F0"))
                    .clipShape(Capsule())
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 20)

            // Note
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#AAAAAA"))
                Text("Only public Instagram accounts are supported.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#AAAAAA"))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .onAppear { inputFocused = true }
    }

    // MARK: - Fetch

    private func fetchInstagram() async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        guard url.lowercased().contains("instagram.com") else {
            errorMessage = "Please enter a valid Instagram URL."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await APIService.shared.instagramFetch(url: url, token: auth.token)
            dismiss()

            if result.type == "video", let videoUrl = result.videoUrl {
                onResult(.video(url: videoUrl))
            } else if let imageUrl = result.imageUrl {
                onResult(.image(url: imageUrl))
            } else {
                errorMessage = "Could not retrieve media. Please try again."
            }
        } catch {
            errorMessage = (error as? InstagramFetchError)?.message ?? "Connection error. Please try again."
        }

        isLoading = false
    }
}


// MARK: - NotificationsView

struct NotificationsView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @Binding var unreadCount: Int

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView().tint(Color.snapshePurple)
                        Spacer()
                    }
                } else if notifications.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bell.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(Color(hex: "#DDD"))
                        Text("No notifications yet")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(hex: "#AAA"))
                        Text("When someone follows you, it'll show up here.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#BBB"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(notifications) { notif in
                            NotificationRow(notification: notif)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
        }
        .task {
            await loadNotifications()
        }
    }

    func loadNotifications() async {
        isLoading = true
        if let r = try? await APIService.shared.fetchNotifications(token: auth.token) {
            notifications = r.notifications ?? []
        }
        isLoading = false
        // Tümünü okundu işaretle
        _ = try? await APIService.shared.markNotificationsRead(token: auth.token)
        unreadCount = 0
    }
}

// MARK: - Single notification row

struct NotificationRow: View {
    @EnvironmentObject var auth: AuthManager
    let notification: AppNotification
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 12) {
                // Avatar
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(hex: "#EEE").overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color(hex: "#BBB"))
                        )
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(Circle())

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Group {
                        Text(notification.fromName).fontWeight(.bold)
                        + Text(" started following you.")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Color.snapsheBlack)

                    Text(timeAgo(notification.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#999"))
                }

                Spacer()

                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(Color.snapshePurple)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            PublicProfileView(username: notification.fromUsername)
                .environmentObject(auth)
        }
    }

    var avatarURL: URL? {
        guard let av = notification.fromAvatar, !av.isEmpty else { return nil }
        return URL(string: av)
    }

    func timeAgo(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = fmt.date(from: dateStr) else { return "" }
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60    { return "just now" }
        if seconds < 3600  { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - DiscoverView

struct DiscoverView: View {
    @EnvironmentObject var auth: AuthManager
    @Binding var selectedTab: Int
    @StateObject private var vm = DiscoverViewModel()

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
                            // Reset duration — new card's video will report its own duration
                            currentItemDuration = nil
                            startAutoTimer()
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
        let currentItem = vm.items.indices.contains(currentIndex) ? vm.items[currentIndex] : nil
        // For videos: wait for real duration from onDurationKnown before starting timer
        // For photos: use defaultInterval immediately
        if currentItem?.mediaType == .video && currentItemDuration == nil {
            return // duration not known yet — onDurationKnown will call restartAutoTimer
        }
        let interval = currentItemDuration ?? defaultInterval
        autoTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                guard !self.vm.items.isEmpty else { return }
                withAnimation {
                    if self.currentIndex < self.vm.items.count - 1 {
                        self.currentIndex += 1
                    }
                }
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
            // Deduplicate by both id AND media path — backend sometimes sends same content with different ids
            var seenIDs = Set<String>()
            var seenPaths = Set<String>()
            allItems = raw.filter { item in
                let mediaPath = item.video ?? item.image ?? ""
                let newID = seenIDs.insert(item.id).inserted
                let newPath = mediaPath.isEmpty ? true : seenPaths.insert(mediaPath).inserted
                return newID && newPath
            }
            items = allItems
            print("[Discover] Loaded \(raw.count) raw → \(allItems.count) unique items")
        }
        isLoading = false
        didLoad = true
    }

    func loadMore(token: String) async {
        // No-op: backend returns same feed, duplicates prevented
    }
}
