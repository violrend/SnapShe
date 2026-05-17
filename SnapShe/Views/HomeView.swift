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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                Divider()

                if !searchText.isEmpty {
                    searchResultsView
                } else if vm.isLoading && vm.photos.isEmpty {
                    Spacer()
                    ProgressView().tint(Color.snapshePurple)
                    Spacer()
                } else if vm.photos.isEmpty {
                    emptyStateView
                } else {
                    feedView
                }
            }
            .background(Color.white)
            .sheet(isPresented: $showCollections) { CollectionsView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
        }
        .task { await vm.loadFeed(token: auth.token) }
        .onReceive(NotificationCenter.default.publisher(for: .feedNeedsRefresh)) { _ in
            Task { await vm.silentRefresh(token: auth.token) }
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
