import SwiftUI
import PhotosUI
import AVKit

// MARK: - Style Post Models

struct BrandTag: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var category: String
    // Normalized position on the photo (0.0 - 1.0)
    var posX: CGFloat = 0.5
    var posY: CGFloat = 0.5

    static let popular = ["Nike", "Adidas", "Zara", "H&M", "Mango", "Bershka", "Pull&Bear",
                          "Stradivarius", "Massimo Dutti", "Levis", "Gucci", "Prada",
                          "Balenciaga", "New Balance", "Converse", "Vans", "Louis Vuitton"]
}

struct StylePost: Identifiable, Codable {
    var id: UUID = UUID()
    var imageFileName: String
    var caption: String
    var brandTags: [BrandTag]
    var likes: Int = 0
    var comments: [StyleComment] = []
    var username: String
    var userAvatar: String?
    var createdAt: Date = Date()
    var serverPostId: String? = nil  // tracks web-originated posts

    var image: UIImage {
        get { StyleImageStore.load(fileName: imageFileName) ?? UIImage(systemName: "photo")! }
    }
}

struct StyleComment: Identifiable, Codable {
    var id: UUID = UUID()
    var username: String
    var text: String
    var createdAt: Date = Date()
}

// MARK: - StyleImageStore (disk persistence for UIImage)

enum StyleImageStore {
    static var imagesDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("StyleImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(image: UIImage) -> String {
        let name = UUID().uuidString + ".jpg"
        let url = imagesDir.appendingPathComponent(name)
        if let data = image.jpegData(compressionQuality: 0.82) {
            try? data.write(to: url)
        }
        return name
    }

    static func load(fileName: String) -> UIImage? {
        // Demo posts use a sentinel value
        if fileName == "__demo__" {
            return UIImage(systemName: "person.crop.rectangle")
        }
        let url = imagesDir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(fileName: String) {
        let url = imagesDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - StyleLikeStore (per-user like state)

enum StyleLikeStore {
    static func likedPostIds(for username: String) -> Set<String> {
        let key = "style_likes_\(username)"
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }

    static func isLiked(postId: UUID, username: String) -> Bool {
        likedPostIds(for: username).contains(postId.uuidString)
    }

    // Set explicit liked state (no toggle)
    static func setLike(postId: UUID, username: String, liked: Bool) {
        let key = "style_likes_\(username)"
        var ids = likedPostIds(for: username)
        if liked { ids.insert(postId.uuidString) }
        else     { ids.remove(postId.uuidString) }
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    // Toggle and return new state
    @discardableResult
    static func toggleLike(postId: UUID, username: String) -> Bool {
        let nowLiked = !isLiked(postId: postId, username: username)
        setLike(postId: postId, username: username, liked: nowLiked)
        return nowLiked
    }
}

@MainActor
class StyleFeedViewModel: ObservableObject {
    @Published var posts: [StylePost] = []
    @Published var showNewPostSheet = false

    private let saveKey = "snapshe_style_posts_v2"

    init() {
        loadFromDisk()
        Task { await fetchFromServer() }
        startPolling()
    }

    // MARK: - Polling (auto-refresh every 30s while app is open)

    private var pollingTask: Task<Void, Never>?

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                if !Task.isCancelled {
                    await fetchFromServer()
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Server fetch (web + mobile posts merged)

    func fetchFromServer() async {
        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/style-posts-fetch.php") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        struct FetchResponse: Decodable {
            let ok: Bool
            let posts: [ServerStylePost]?
        }
        struct ServerStylePost: Decodable {
            let post_id: String
            let username: String
            let caption: String
            let brand_tags: [ServerBrandTag]
            let image_url: String
            let likes: Int
            let created_at: String
        }
        struct ServerBrandTag: Decodable {
            let name: String
            let posX: Double?
            let posY: Double?
            let category: String?
        }

        guard let resp = try? JSONDecoder().decode(FetchResponse.self, from: data),
              resp.ok, let serverPosts = resp.posts else { return }

        // Build set of post_ids already stored locally
        let localIDs = Set(posts.compactMap { $0.serverPostId })

        var newPosts: [StylePost] = []
        let fmt = ISO8601DateFormatter()

        for sp in serverPosts {
            // Skip if already in local feed
            if localIDs.contains(sp.post_id) { continue }

            let tags = sp.brand_tags.map { t in
                BrandTag(
                    name: t.name,
                    category: t.category ?? "",
                    posX: t.posX ?? 0.5,
                    posY: t.posY ?? 0.5
                )
            }

            // Download image
            let fileName: String
            if let imgUrl = URL(string: sp.image_url),
               let (imgData, _) = try? await URLSession.shared.data(from: imgUrl),
               let img = UIImage(data: imgData) {
                fileName = StyleImageStore.save(image: img)
            } else {
                fileName = ""
            }

            var post = StylePost(
                imageFileName: fileName,
                caption: sp.caption,
                brandTags: tags,
                username: sp.username,
                userAvatar: nil
            )
            post.serverPostId = sp.post_id
            post.likes = sp.likes
            post.createdAt = fmt.date(from: sp.created_at) ?? Date()
            newPosts.append(post)
        }

        guard !newPosts.isEmpty else { return }

        await MainActor.run {
            // Merge: put server posts that aren't local at the end, sort by date
            posts.append(contentsOf: newPosts)
            posts.sort { $0.createdAt > $1.createdAt }
            saveToDisk()
        }
    }

    // MARK: - Persistence

    func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([StylePost].self, from: data) else {
            return   // first launch — no saved posts yet
        }
        posts = decoded
    }

    func saveToDisk() {
        guard let data = try? JSONEncoder().encode(posts) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    // MARK: - Actions

    func setLike(id: UUID, liked: Bool, fromUser: String, fromAvatar: String) {
        guard let i = posts.firstIndex(where: { $0.id == id }) else { return }

        // Sync count — card already updated UI, just persist
        StyleLikeStore.setLike(postId: id, username: fromUser, liked: liked)
        posts[i].likes = max(0, posts[i].likes + (liked ? 1 : -1))
        saveToDisk()

        // Notify only on like, not unlike
        if liked {
            let owner = posts[i].username
            let pid   = posts[i].id.uuidString
            if owner != fromUser {
                Task { await StyleNotificationService.send(
                    toUsername: owner,
                    type: "style_like",
                    fromUsername: fromUser,
                    fromAvatar: fromAvatar,
                    text: "liked your style post",
                    postId: pid
                )}
            }
        }
    }

    func addComment(postId: UUID, username: String, text: String, fromAvatar: String = "") {
        guard let i = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[i].comments.append(StyleComment(username: username, text: text))
        saveToDisk()
        // Send notification to post owner
        let owner = posts[i].username
        let pid   = posts[i].id.uuidString
        if owner != username {
            Task { await StyleNotificationService.send(
                toUsername: owner,
                type: "style_comment",
                fromUsername: username,
                fromAvatar: fromAvatar,
                text: "commented: \(text)",
                postId: pid
            )}
        }
    }

    func addPost(image: UIImage, caption: String, brandTags: [BrandTag], username: String, avatarURL: String = "") {
        let fileName = StyleImageStore.save(image: image)
        let post = StylePost(
            imageFileName: fileName,
            caption: caption,
            brandTags: brandTags,
            username: username,
            userAvatar: avatarURL
        )
        posts.insert(post, at: 0)
        saveToDisk()
        Task { await syncPostToServer(post, image: image) }
    }

    func deletePost(id: UUID) {
        if let i = posts.firstIndex(where: { $0.id == id }) {
            let post = posts[i]
            StyleImageStore.delete(fileName: post.imageFileName)
            posts.remove(at: i)
            saveToDisk()
            // Delete from server too
            Task { await deletePostFromServer(stylePostId: post.id.uuidString) }
        }
    }

    // MARK: - Server sync

    private func syncPostToServer(_ post: StylePost, image: UIImage) async {
        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/style-post-sync.php"),
              let imageData = image.jpegData(compressionQuality: 0.8) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        // Fields
        for (key, val) in [
            "post_id": post.id.uuidString,
            "username": post.username,
            "caption": post.caption,
            "brand_tags": (try? String(data: JSONEncoder().encode(post.brandTags), encoding: .utf8)) ?? "[]",
            "created_at": ISO8601DateFormatter().string(from: post.createdAt)
        ] {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(val)\r\n")
        }

        // Image
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"style.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body
        _ = try? await URLSession.shared.data(for: req)
    }

    private func deletePostFromServer(stylePostId: String) async {
        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/style-post-delete.php") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "post_id=\(stylePostId)".data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }

    // No demo posts — real posts only
    func seedDemoIfEmpty() {
        // Nothing to seed — users see empty state until they share their first look
    }
}

// MARK: - StyleNotificationService

enum StyleNotificationService {
    static func send(
        toUsername: String,
        type: String,
        fromUsername: String,
        fromAvatar: String,
        text: String,
        postId: String = ""
    ) async {
        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/style-notify.php") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "to_username":   toUsername,
            "type":          type,
            "from_username": fromUsername,
            "from_avatar":   fromAvatar,
            "text":          text,
            "post_id":       postId
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
        .joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        _ = try? await URLSession.shared.data(for: req)
    }
}

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
    @State private var showLiveCamera = false

    @State private var showInstagramFetch = false
    @State private var instagramImageURL: String? = nil
    @State private var pendingInstagramVideoURL: URL? = nil

    let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    @StateObject private var followingVM = FollowingFeedViewModel()
    @StateObject private var styleVM = StyleFeedViewModel()
    @State private var selectedFeedTab: FeedTab = .forYou
    @State private var showNotifications = false
    @State private var unreadCount: Int = 0
    @State private var showNewStylePost = false  // kept for future use

    enum FeedTab { case forYou, following, style }

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
                    } else if selectedFeedTab == .following {
                        followingFeedView
                    } else {
                        StyleFeedView(vm: styleVM, currentUsername: auth.currentUser?.username ?? "me")
                    }
                }
            }
            .background(Color.white)
            .sheet(isPresented: $showCollections) { CollectionsView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
        }
        .task { await vm.loadFeed(token: auth.token) }
        .onAppear {
            styleVM.seedDemoIfEmpty()
            styleVM.startPolling()
        }
        .onDisappear { styleVM.stopPolling() }
        .task(id: auth.token) {
            while !Task.isCancelled {
                if let r = try? await APIService.shared.fetchNotifications(token: auth.token) {
                    unreadCount = r.unreadCount ?? 0
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsView(unreadCount: $unreadCount, styleVM: styleVM)
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
        .fullScreenCover(isPresented: $showLiveCamera) {
            LiveCameraView()
                .environmentObject(auth)
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
            HStack(spacing: 6) {
                // Logo — only icon tappable, text is just a label
                HStack(spacing: 9) {
                    Button { showProfile = true } label: {
                        ZStack {
                            snapsheGradient
                            Text("S")
                                .font(.system(size: 34 * 0.52, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 34 * 0.28, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text("SnapShe")
                        .font(.system(size: 34 * 0.58, weight: .black, design: .rounded))
                        .foregroundStyle(Color.snapsheBlack)
                        .fixedSize()
                        .allowsHitTesting(false)   // ← not tappable
                }
                .fixedSize()

                Spacer(minLength: 4)

                Button { showProfile = true } label: {
                    SnapSheProfileChip(user: auth.currentUser)
                }
                .buttonStyle(.plain)

                // Bell
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
                    .fixedSize()

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

                // ── LIVE butonu ──────────────────────────────────
                Button { showLiveCamera = true } label: {
                    ZStack {
                        Capsule()
                            .fill(Color(hex: "#FF3B30"))
                            .frame(width: 56, height: 40)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.white)
                                .frame(width: 7, height: 7)
                            Text("LIVE")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                        }
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
            feedTabButton(title: "Style", tab: .style)
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
                if tab == .style {
                    styleVM.seedDemoIfEmpty()
                    Task { await styleVM.fetchFromServer() }
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
    var styleVM: StyleFeedViewModel   // to look up style posts by ID

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
                            NotificationRow(notification: notif, styleVM: styleVM)
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
    // StyleFeedViewModel passed so we can find the post by ID
    var styleVM: StyleFeedViewModel? = nil

    @State private var showProfile = false
    @State private var showStylePost: StylePost? = nil

    var body: some View {
        Button { handleTap() } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
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

                    // Type icon badge
                    Text(icon)
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                        .background(iconBg)
                        .clipShape(Circle())
                        .offset(x: 4, y: 4)
                }

                // Text + post thumbnail
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        (Text(notification.fromUsername).fontWeight(.bold)
                         + Text(" \(notifMessage)"))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.snapsheBlack)
                            .lineLimit(2)

                        Text(timeAgo(notification.createdAt))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#999"))
                    }

                    Spacer()

                    // Post thumbnail if it's a style notification
                    if isStyleNotif, let post = linkedPost {
                        Image(uiImage: post.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color(hex: "#E0E0E0"), lineWidth: 1)
                            )
                    } else if !notification.isRead {
                        Circle()
                            .fill(Color.snapshePurple)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            PublicProfileView(username: notification.fromUsername)
                .environmentObject(auth)
        }
        .sheet(item: $showStylePost) { post in
            StylePostDetailView(
                post: post,
                currentUsername: auth.currentUser?.username ?? "",
                onComment: { _ in }   // read-only from notification
            )
            .environmentObject(auth)
        }
    }

    // MARK: - Helpers

    var isStyleNotif: Bool {
        notification.type == "style_like" || notification.type == "style_comment"
    }

    // Find the post in local storage by post_id
    var linkedPost: StylePost? {
        guard let pid = notification.postId, !pid.isEmpty,
              let vm = styleVM,
              let uuid = UUID(uuidString: pid) else { return nil }
        return vm.posts.first { $0.id == uuid }
    }

    func handleTap() {
        if isStyleNotif, let post = linkedPost {
            showStylePost = post
        } else {
            showProfile = true
        }
    }

    var notifMessage: String {
        switch notification.type {
        case "style_like":    return "liked your style post ❤️"
        case "style_comment":
            if let t = notification.text, t.hasPrefix("commented: ") {
                let comment = String(t.dropFirst("commented: ".count))
                return "commented on your style post: \"\(comment)\" 💬"
            }
            return "commented on your style post 💬"
        case "follow":        return "started following you"
        case "like":          return "liked your photo ❤️"
        case "comment":       return "commented on your photo 💬"
        default:              return notification.text ?? "interacted with your post"
        }
    }

    var icon: String {
        switch notification.type {
        case "style_like", "like":       return "❤️"
        case "style_comment", "comment": return "💬"
        case "follow":                   return "👤"
        default:                         return "🔔"
        }
    }

    var iconBg: Color {
        switch notification.type {
        case "style_like", "like":       return Color.red.opacity(0.15)
        case "style_comment", "comment": return Color.blue.opacity(0.12)
        case "follow":                   return Color.snapshePurple.opacity(0.12)
        default:                         return Color.gray.opacity(0.1)
        }
    }

    var avatarURL: URL? {
        guard let av = notification.fromAvatar, !av.isEmpty else { return nil }
        if av.hasPrefix("http") { return URL(string: av) }
        return URL(string: "\(APIService.baseURL)/\(av.hasPrefix("/") ? String(av.dropFirst()) : av)")
    }

    func timeAgo(_ dateStr: String) -> String {
        let fmts = ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss+00:00",
                    "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"]
        for fmt in fmts {
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let date = df.date(from: dateStr) {
                let s = Int(-date.timeIntervalSinceNow)
                if s < 60    { return "just now" }
                if s < 3600  { return "\(s / 60)m ago" }
                if s < 86400 { return "\(s / 3600)h ago" }
                return "\(s / 86400)d ago"
            }
        }
        return ""
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

// MARK: - LiveCameraViewModel
/// Kameradan belirli aralıklarla frame yakalar ve SearchAPI Google Lens'e gönderir.
@MainActor
class LiveCameraViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isSearching = false
    @Published var error: String? = nil
    @Published var lastSearchTime: Date? = nil

    /// Arama aralığı (saniye) — çok sık istek atmamak için
    let searchInterval: TimeInterval = 2.5

    private var searchTask: Task<Void, Never>? = nil

    func canSearch() -> Bool {
        guard let last = lastSearchTime else { return true }
        return Date().timeIntervalSince(last) >= searchInterval
    }

    func performLiveSearch(frameData: Data, crop: CGRect, keyword: String, token: String) async {
        guard !isSearching else { return }
        isSearching = true
        error = nil
        lastSearchTime = Date()

        let cropString = "\(String(format: "%.4f", crop.minX));\(String(format: "%.4f", crop.minY));\(String(format: "%.4f", crop.maxX));\(String(format: "%.4f", crop.maxY))"

        do {
            let response = try await APIService.shared.visualSearch(
                imageData: frameData,
                imageURL: nil,
                crop: cropString,
                keyword: keyword.isEmpty ? nil : keyword,
                token: token
            )
            if response.ok {
                if let newProducts = response.products, !newProducts.isEmpty {
                    products = newProducts
                }
                self.error = nil
            } else {
                self.error = response.error ?? "Search failed."
            }
        } catch {
            // Sessiz hata — live modda küçük network hatası akışı kesmemeli
            if products.isEmpty {
                self.error = "Connection error."
            }
        }

        isSearching = false
    }
}

// MARK: - LiveCameraView
/// Kullanıcı kamerayı açar, karşısındaki kişinin üzerindeki
/// ürünleri fotoğraf/video çekmeden canlı olarak Google Lens ile arar.
struct LiveCameraView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    @StateObject private var vm = LiveCameraViewModel()
    @StateObject private var captureSession = LiveCaptureSession()

    @State private var cropRect = CGRect(x: 0.1, y: 0.08, width: 0.8, height: 0.55)
    @State private var keyword = ""
    @State private var showSaveModal = false
    @State private var productToSave: Product? = nil
    @State private var isPaused = false
    @State private var frameTimer: Timer? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── TOOLBAR ──────────────────────────────────────────
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
                        HStack(spacing: 6) {
                            if !isPaused {
                                Circle()
                                    .fill(Color.snapsheRed)
                                    .frame(width: 7, height: 7)
                            }
                            Text(isPaused ? "Paused" : "Live Search")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                        }
                        Text(vm.isSearching
                            ? "Searching for products…"
                            : (vm.products.isEmpty ? "Point camera at an outfit" : "\(vm.products.count) products found"))
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                            .lineLimit(1)
                    }

                    Spacer()

                    // Pause / Resume
                    Button {
                        isPaused.toggle()
                        if isPaused { stopFrameTimer() } else { startFrameTimer() }
                    } label: {
                        Text(isPaused ? "Resume" : "Pause")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(isPaused ? Color.snapshePurple : Color.snapsheGray)
                            .foregroundStyle(isPaused ? .white : Color.snapsheBlack)
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

                        // ── CAMERA + CROP ─────────────────────────────────
                        ZStack {
                            LivePreviewView(session: captureSession.session)
                                .frame(maxWidth: .infinity)
                                .frame(height: UIScreen.main.bounds.width * 1.05)
                                .clipped()

                            GeometryReader { geo in
                                LiveCropOverlay(cropRect: $cropRect, size: geo.size)
                            }
                            .frame(height: UIScreen.main.bounds.width * 1.05)

                            // Bottom pill
                            VStack {
                                Spacer()
                                Group {
                                    if vm.isSearching {
                                        HStack(spacing: 6) {
                                            ProgressView().tint(.white).scaleEffect(0.75)
                                            Text("Searching…")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                    } else {
                                        Text("Drag or resize selected area")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.horizontal, 18).padding(.vertical, 9)
                                .background(Color.snapsheBlack.opacity(0.82))
                                .clipShape(Capsule())
                                .padding(.bottom, 14)
                            }
                        }

                        // ── SHOP THE LOOK ─────────────────────────────────
                        VStack(alignment: .leading, spacing: 0) {

                            // Header
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Shop the look")
                                        .font(.system(size: 22, weight: .black))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Text("Products update automatically as you move the camera.")
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
                                TextField("Refine search (e.g. jacket, sneakers)", text: $keyword)
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled()
                                    .autocapitalization(.none)
                                if !keyword.isEmpty {
                                    Button { keyword = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color(hex: "#ccc"))
                                    }
                                }
                            }
                            .padding(13)
                            .background(Color.snapsheGray)
                            .clipShape(Capsule())
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)

                            // Error
                            if let err = vm.error {
                                SnapSheErrorBox(message: err)
                                    .padding(.horizontal, 16).padding(.bottom, 12)
                            }

                            // Empty state
                            if vm.products.isEmpty && !vm.isSearching && vm.error == nil {
                                VStack(spacing: 14) {
                                    Image(systemName: "sparkle.magnifyingglass")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color(hex: "#ccc"))
                                    Text("Point the selection area at someone's outfit")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(hex: "#aaa"))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }

                            // ── Horizontal product scroll — no layout conflict ──
                            if !vm.products.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(vm.products) { product in
                                            LiveHorizontalCard(product: product) {
                                                productToSave = product
                                                showSaveModal = true
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                                .padding(.bottom, 32)
                            }
                        }
                        .background(Color.white)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
        .onAppear {
            captureSession.start()
            startFrameTimer()
        }
        .onDisappear {
            stopFrameTimer()
            captureSession.stop()
        }
        .sheet(isPresented: $showSaveModal) {
            if let product = productToSave {
                SaveToCollectionView(product: product)
            }
        }
    }

    // MARK: - Frame Timer

    func startFrameTimer() {
        stopFrameTimer()
        frameTimer = Timer.scheduledTimer(withTimeInterval: vm.searchInterval, repeats: true) { _ in
            guard !isPaused else { return }
            Task { @MainActor in
                await captureAndSearch()
            }
        }
    }

    func stopFrameTimer() {
        frameTimer?.invalidate()
        frameTimer = nil
    }

    func captureAndSearch() async {
        guard vm.canSearch() else { return }
        guard let frameData = await captureSession.captureFrame(crop: cropRect) else { return }
        await vm.performLiveSearch(frameData: frameData, crop: cropRect, keyword: keyword, token: auth.token)
    }
}

// MARK: - LiveCropOverlay
/// Drag to move, corner handles to resize — matches VideoCropView style.
struct LiveCropOverlay: View {
    @Binding var cropRect: CGRect
    let size: CGSize

    @State private var isDragging = false
    @State private var dragStart: CGPoint = .zero
    @State private var cropStart: CGRect = .zero
    @State private var activeCorner: CropCorner? = nil

    enum CropCorner { case tl, tr, bl, br }

    var body: some View {
        let box = cropPx()
        ZStack {
            // Dim outside
            Color.black.opacity(0.5)
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

            // Solid border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)

            // Dashed inner border — same as VideoCropView
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: max(0, box.width - 4), height: max(0, box.height - 4))
                .position(x: box.midX, y: box.midY)

            // Corner handles — same white circle style as VideoCropView
            Group {
                cropCornerHandle(at: CGPoint(x: box.minX, y: box.minY))
                cropCornerHandle(at: CGPoint(x: box.maxX, y: box.minY))
                cropCornerHandle(at: CGPoint(x: box.minX, y: box.maxY))
                cropCornerHandle(at: CGPoint(x: box.maxX, y: box.maxY))
            }

            // Full gesture layer
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { val in
                            if !isDragging {
                                isDragging = true
                                dragStart = val.startLocation
                                cropStart = cropRect
                                activeCorner = detectCorner(at: val.startLocation)
                            }
                            updateCrop(location: val.location)
                        }
                        .onEnded { _ in
                            isDragging = false
                            activeCorner = nil
                        }
                )
        }
    }

    func cropPx() -> CGRect {
        CGRect(
            x: cropRect.minX * size.width,
            y: cropRect.minY * size.height,
            width: cropRect.width * size.width,
            height: cropRect.height * size.height
        )
    }

    func cropCornerHandle(at pos: CGPoint) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 18, height: 18)
            Circle().stroke(Color.white.opacity(0.4), lineWidth: 2).frame(width: 26, height: 26)
        }
        .shadow(color: .black.opacity(0.3), radius: 4)
        .position(x: pos.x, y: pos.y)
    }

    func detectCorner(at pt: CGPoint) -> CropCorner? {
        let box = cropPx()
        let d: CGFloat = 34
        let pairs: [(CGPoint, CropCorner)] = [
            (CGPoint(x: box.minX, y: box.minY), .tl),
            (CGPoint(x: box.maxX, y: box.minY), .tr),
            (CGPoint(x: box.minX, y: box.maxY), .bl),
            (CGPoint(x: box.maxX, y: box.maxY), .br),
        ]
        return pairs.first { abs(pt.x - $0.0.x) < d && abs(pt.y - $0.0.y) < d }?.1
    }

    func updateCrop(location: CGPoint) {
        let dx = (location.x - dragStart.x) / size.width
        let dy = (location.y - dragStart.y) / size.height
        let minSize: CGFloat = 0.1
        var r = cropStart

        switch activeCorner {
        case .none:
            r.origin.x = max(0, min(cropStart.minX + dx, 1 - cropStart.width))
            r.origin.y = max(0, min(cropStart.minY + dy, 1 - cropStart.height))
        case .tl:
            let nx = min(cropStart.maxX - minSize, cropStart.minX + dx)
            let ny = min(cropStart.maxY - minSize, cropStart.minY + dy)
            r = CGRect(x: max(0, nx), y: max(0, ny),
                       width: cropStart.maxX - max(0, nx),
                       height: cropStart.maxY - max(0, ny))
        case .tr:
            let ny = min(cropStart.maxY - minSize, cropStart.minY + dy)
            r = CGRect(x: cropStart.minX, y: max(0, ny),
                       width: min(cropStart.width + dx, 1 - cropStart.minX),
                       height: cropStart.maxY - max(0, ny))
        case .bl:
            let nx = min(cropStart.maxX - minSize, cropStart.minX + dx)
            r = CGRect(x: max(0, nx), y: cropStart.minY,
                       width: cropStart.maxX - max(0, nx),
                       height: min(cropStart.height + dy, 1 - cropStart.minY))
        case .br:
            r = CGRect(x: cropStart.minX, y: cropStart.minY,
                       width: min(cropStart.width + dx, 1 - cropStart.minX),
                       height: min(cropStart.height + dy, 1 - cropStart.minY))
        case .some(_):
            break
        }
        cropRect = r
    }
}

// MARK: - LiveHorizontalCard
/// App-themed horizontal scroll card. Fixed width = no overflow.
struct LiveHorizontalCard: View {
    let product: Product
    let onSave: () -> Void

    private let cardW: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: product.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(width: cardW, height: 150)
                            .clipped()
                    case .failure:
                        Color.snapsheGray
                            .frame(width: cardW, height: 150)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    default:
                        Color.snapsheGray
                            .frame(width: cardW, height: 150)
                            .shimmering()
                    }
                }
                .frame(width: cardW, height: 150)
                .clipped()

                if !product.price.isEmpty {
                    Text(product.price)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.snapsheBlack.opacity(0.82))
                        .clipShape(Capsule())
                        .padding(7)
                }
            }
            .frame(width: cardW, height: 150)
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = APIService.affiliateURL(for: product.link) {
                    UIApplication.shared.open(url)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.snapsheBlack)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(product.source)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#999"))
                    .lineLimit(1)

                Button(action: onSave) {
                    Text("Save")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.snapsheRed)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
                .simultaneousGesture(TapGesture().onEnded { _ in })
            }
            .padding(10)
        }
        .frame(width: cardW)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.snapsheBlack.opacity(0.07), radius: 8, y: 2)
    }
}

// MARK: - LiveCaptureSession
/// AVCaptureSession yönetir; istenen anda JPEG frame yakalar ve
/// crops the selected area and returns it.

class LiveCaptureSession: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "live.capture.queue")
    private var latestSampleBuffer: CMSampleBuffer?
    private let bufferLock = NSLock()

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        // Dikey yönlendirme
        if let conn = output.connection(with: .video) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
    }

    func start() {
        guard !session.isRunning else { return }
        queue.async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        queue.async { self.session.stopRunning() }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        bufferLock.lock()
        latestSampleBuffer = sampleBuffer
        bufferLock.unlock()
    }

    // MARK: - Frame yakala + crop

    func captureFrame(crop: CGRect) async -> Data? {
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return nil }
            self.bufferLock.lock()
            let buffer = self.latestSampleBuffer
            self.bufferLock.unlock()

            guard let sb = buffer,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { return nil }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }

            // Crop uygula
            let fullW = CGFloat(cgImage.width)
            let fullH = CGFloat(cgImage.height)
            let cropCG = CGRect(
                x: crop.minX * fullW,
                y: crop.minY * fullH,
                width: crop.width * fullW,
                height: crop.height * fullH
            )

            let cropped: CGImage
            if let c = cgImage.cropping(to: cropCG) {
                cropped = c
            } else {
                cropped = cgImage
            }

            let uiImage = UIImage(cgImage: cropped, scale: 1.0, orientation: .up)
            return uiImage.jpegData(compressionQuality: 0.82)
        }.value
    }
}

// MARK: - LivePreviewView
/// AVCaptureSession'u SwiftUI'ya köprüler.

struct LivePreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}

// ============================================================
// MARK: - STYLE POSTS FEATURE
// ============================================================

// MARK: - StyleFeedView

enum StyleSheet: Identifiable {
    case newPost
    case brandPage(String)
    var id: String {
        switch self {
        case .newPost: return "newPost"
        case .brandPage(let b): return "brand_\(b)"
        }
    }
}

struct StyleFeedView: View {
    @EnvironmentObject var auth: AuthManager
    @ObservedObject var vm: StyleFeedViewModel
    let currentUsername: String

    @State private var selectedBrandFilter: String? = nil
    @State private var activeSheet: StyleSheet? = nil

    var filteredPosts: [StylePost] {
        guard let brand = selectedBrandFilter else { return vm.posts }
        return vm.posts.filter { $0.brandTags.contains { $0.name == brand } }
    }

    var allBrands: [String] {
        Array(Set(vm.posts.flatMap { $0.brandTags.map { $0.name } })).sorted()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Community header (no button here) ────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.snapshePurple)
                            Text("Style Community")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.snapshePurple)
                        }
                        Text("Share your look, tag the brands")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Post your photo, tag the brands you're wearing.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // ── Brand filter chips ────────────────────────
                    if !allBrands.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chipView(name: "All", selected: selectedBrandFilter == nil) {
                                    selectedBrandFilter = nil
                                }
                                ForEach(allBrands, id: \.self) { brand in
                                    chipView(name: brand, selected: selectedBrandFilter == brand) {
                                        selectedBrandFilter = selectedBrandFilter == brand ? nil : brand
                                    }
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 4)
                        }
                        .padding(.bottom, 8)
                    }

                    // ── Posts ─────────────────────────────────────
                    if filteredPosts.isEmpty {
                        VStack(spacing: 18) {
                            Spacer(minLength: 40)
                            Image(systemName: "tshirt.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color(hex: "#DDD"))
                            Text("No style posts yet")
                                .font(.system(size: 20, weight: .black))
                                .foregroundStyle(Color.snapsheBlack)
                            Text("Be the first to share your look!")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#999"))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredPosts) { post in
                                StylePostCard(
                                    post: post,
                                    onBrandTap: { brand in
                                        activeSheet = .brandPage(brand)
                                    },
                                    vm: vm,
                                    currentUsername: currentUsername
                                )
                                // Long-press to delete (owner only)
                                .contextMenu {
                                    if post.username == currentUsername {
                                        Button(role: .destructive) {
                                            vm.deletePost(id: post.id)
                                        } label: {
                                            Label("Delete Post", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 100) // space for FAB
                    }
                }
            }

            // ── Floating "Share Your Look" button (FAB) ───────
            // Completely outside ScrollView and LazyVStack —
            // no gesture conflict possible
            Button {
                activeSheet = .newPost
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("Share Your Look")
                        .font(.system(size: 16, weight: .black))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.snapshePurple)
                .clipShape(Capsule())
                .shadow(color: Color.snapshePurple.opacity(0.4), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newPost:
                NewStylePostView { image, caption, tags, username in
                    vm.addPost(
                        image: image,
                        caption: caption,
                        brandTags: tags,
                        username: username,
                        avatarURL: auth.currentUser?.avatarURL?.absoluteString ?? auth.currentUser?.avatar ?? ""
                    )
                }
                .environmentObject(auth)
            case .brandPage(let brand):
                BrandPageView(brandName: brand, posts: vm.posts)
            }
        }
    }

    func chipView(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 13, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? .white : Color.snapsheBlack)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Color.snapshePurple : Color.snapsheGray)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AvatarCache (in-memory cache for username → avatar URL)

final class AvatarCache {
    static let shared = AvatarCache()
    var cache: [String: URL] = [:]
    private var inFlight: Set<String> = []

    func url(for username: String) -> URL? { cache[username] }

    func fetch(username: String, token: String) async -> URL? {
        if let cached = cache[username] { return cached }
        guard !inFlight.contains(username) else { return nil }
        inFlight.insert(username)

        defer { inFlight.remove(username) }

        guard let url = URL(string: "\(APIService.baseURL)/api_mobile/public-avatar.php?username=\(username)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let avatar = json["avatar"] as? String,
              !avatar.isEmpty,
              let avatarURL = URL(string: avatar) else { return nil }

        cache[username] = avatarURL
        return avatarURL
    }
}

// MARK: - StylePostCard

enum CardSheet: Identifiable {
    case profile, detail, shopSimilar
    var id: String {
        switch self {
        case .profile: return "profile"
        case .detail: return "detail"
        case .shopSimilar: return "shopSimilar"
        }
    }
}

struct StylePostCard: View {
    let post: StylePost
    let onBrandTap: (String) -> Void
    let vm: StyleFeedViewModel
    let currentUsername: String

    @EnvironmentObject var auth: AuthManager
    @State private var activeCard: CardSheet? = nil
    @State private var showDeleteConfirm = false
    @State private var likedByMe: Bool = false
    @State private var likeCount: Int = 0
    @State private var resolvedAvatarURL: URL? = nil   // fetched if post.userAvatar is empty

    var isOwner: Bool {
        post.username == currentUsername ||
        post.username == (auth.currentUser?.username ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── User header ──────────────────────────────────
            HStack(spacing: 10) {
                Button { activeCard = .profile } label: {
                    HStack(spacing: 10) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.snapshePurple, Color.snapshePink],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)

                            if let url = resolvedAvatarURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable()
                                            .scaledToFill()
                                            .frame(width: 38, height: 38)
                                            .clipShape(Circle())
                                    default:
                                        Text(String(post.username.prefix(1)).uppercased())
                                            .font(.system(size: 15, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                }
                            } else {
                                Text(String(post.username.prefix(1)).uppercased())
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.username)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                            Text(timeAgo(post.createdAt))
                                .font(.system(size: 12))
                                .foregroundStyle(Color(hex: "#999"))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // ── … menu ────────────────────────────────────
                Menu {
                    if isOwner {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Post", systemImage: "trash")
                        }
                    }
                    Button { activeCard = .detail } label: {
                        Label("View Comments", systemImage: "bubble.left")
                    }
                    Button { activeCard = .shopSimilar } label: {
                        Label("Shop Similar", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#CCC"))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // ── Photo with pin dots — full image, no crop ────
            ZStack(alignment: .topLeading) {
                Image(uiImage: post.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)

                GeometryReader { geo in
                    ForEach(post.brandTags) { tag in
                        FeedBrandPinView(
                            tag: tag,
                            containerSize: geo.size,
                            onTap: { onBrandTap(tag.name) }
                        )
                    }
                }
            }

            // ── Caption ──────────────────────────────────────
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.snapsheBlack)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            // ── Brand tag pills ──────────────────────────────
            if !post.brandTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(post.brandTags) { tag in
                            Button { onBrandTap(tag.name) } label: {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.snapshePurple)
                                        .frame(width: 7, height: 7)
                                    Text(tag.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.snapshePurple)
                                    if !tag.category.isEmpty {
                                        Text("· \(tag.category)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color(hex: "#999"))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.snapshePurple.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }

            // ── Actions row ──────────────────────────────────
            HStack(spacing: 16) {
                Button(action: {
                    // 1. Toggle local UI immediately
                    likedByMe.toggle()
                    likeCount = max(0, likeCount + (likedByMe ? 1 : -1))
                    // 2. Persist + notify
                    vm.setLike(
                        id: post.id,
                        liked: likedByMe,
                        fromUser: currentUsername,
                        fromAvatar: auth.currentUser?.avatar ?? ""
                    )
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: likedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundStyle(likedByMe ? Color.red : Color.snapsheBlack)
                        Text("\(likeCount)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
                .buttonStyle(.plain)

                Button { activeCard = .detail } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("\(post.comments.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button { activeCard = .shopSimilar } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("Shop Similar")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.snapsheBlack)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)

            // ── Comment preview ──────────────────────────────
            if let first = post.comments.first {
                Divider().padding(.horizontal, 14)
                Button { activeCard = .detail } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        (Text(first.username).fontWeight(.bold)
                         + Text(" \(first.text)"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.snapsheBlack)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if post.comments.count > 1 {
                            Text("See all \(post.comments.count) comments")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#999"))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.snapsheBlack.opacity(0.07), radius: 12, y: 3)
        .onAppear {
            likedByMe = StyleLikeStore.isLiked(postId: post.id, username: currentUsername)
            likeCount = post.likes
            resolveAvatar()
        }
        .onChange(of: post.likes) { _, new in likeCount = new }
        // ── Delete confirmation ───────────────────────────────
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                vm.deletePost(id: post.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove your photo and brand tags.")
        }
        // ── ONE sheet modifier ────────────────────────────────
        .sheet(item: $activeCard) { card in
            switch card {
            case .profile:
                PublicProfileView(username: post.username)
                    .environmentObject(auth)
            case .detail:
                StylePostDetailView(
                    post: post,
                    currentUsername: currentUsername,
                    onComment: { text in
                        vm.addComment(
                            postId: post.id,
                            username: currentUsername,
                            text: text,
                            fromAvatar: auth.currentUser?.avatar ?? ""
                        )
                    }
                )
                .environmentObject(auth)
            case .shopSimilar:
                ShopSimilarView(post: post)
                    .environmentObject(auth)
            }
        }
    }

    func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s/60)m ago" }
        if s < 86400 { return "\(s/3600)h ago" }
        return "\(s/86400)d ago"
    }

    func resolveAvatar() {
        // 1. Post has saved avatar URL
        if let saved = post.userAvatar, !saved.isEmpty {
            let clean = saved.hasPrefix("/") ? String(saved.dropFirst()) : saved
            resolvedAvatarURL = URL(string: saved.hasPrefix("http") ? saved : "\(APIService.baseURL)/\(clean)")
            // Also store in cache
            if let url = resolvedAvatarURL {
                AvatarCache.shared.cache[post.username] = url
            }
            return
        }

        // 2. Current user — use their own known avatar
        if post.username == (auth.currentUser?.username ?? "") {
            resolvedAvatarURL = auth.currentUser?.avatarURL
            return
        }

        // 3. Check cache first
        if let cached = AvatarCache.shared.url(for: post.username) {
            resolvedAvatarURL = cached
            return
        }

        // 4. Fetch from public-avatar.php (no token needed)
        Task {
            let url = await AvatarCache.shared.fetch(username: post.username, token: auth.token)
            await MainActor.run { resolvedAvatarURL = url }
        }
    }
}

// MARK: - StylePostDetailView (Yorum + Shop Similar)

struct StylePostDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager
    let post: StylePost
    let currentUsername: String
    let onComment: (String) -> Void

    @State private var commentText = ""
    @FocusState private var inputFocused: Bool
    @State private var showShopSimilar = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Photo — full image, no crop
                    Image(uiImage: post.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)

                    // Brand tags
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(post.brandTags) { tag in
                                HStack(spacing: 4) {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.snapshePurple)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tag.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color.snapsheBlack)
                                        if !tag.category.isEmpty {
                                            Text(tag.category)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Color(hex: "#999"))
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.snapsheGray)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    // Caption
                    if !post.caption.isEmpty {
                        Text(post.caption)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.snapsheBlack)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }

                    // Shop Similar button
                    Button {
                        showShopSimilar = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .bold))
                            Text("Shop Similar — Find similar products")
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.snapshePurple, Color.snapshePink],
                                startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    Divider()

                    // Comments section header
                    HStack {
                        Text("Comments")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("(\(post.comments.count))")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#999"))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if post.comments.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 32))
                                .foregroundStyle(Color(hex: "#DDD"))
                            Text("Be the first to comment!")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#BBB"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(post.comments) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.snapsheGray)
                                        .frame(width: 32, height: 32)
                                    Text(String(comment.username.prefix(1)).uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(hex: "#888"))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(comment.username)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Text(comment.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.snapsheBlack)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(timeAgo(comment.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(hex: "#BBB"))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationTitle("@\(post.username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                commentInputBar
            }
        }
        .sheet(isPresented: $showShopSimilar) {
            ShopSimilarView(post: post)
                .environmentObject(auth)
        }
    }

    var commentInputBar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.snapshePurple, Color.snapshePink],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Text(String(currentUsername.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(.white)
            }

            TextField("Add a comment...", text: $commentText)
                .font(.system(size: 15))
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.snapsheGray)
                .clipShape(Capsule())

            Button {
                let text = commentText.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { return }
                onComment(text)
                commentText = ""
                inputFocused = false
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(commentText.trimmingCharacters(in: .whitespaces).isEmpty
                        ? Color(hex: "#DDD") : Color.snapshePurple)
                    .clipShape(Circle())
            }
            .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s/60)m ago" }
        if s < 86400 { return "\(s/3600)h ago" }
        return "\(s/86400)d ago"
    }
}

// MARK: - FeedBrandPinView (read-only pin on feed card)

struct FeedBrandPinView: View {
    let tag: BrandTag
    let containerSize: CGSize
    let onTap: () -> Void

    @State private var showLabel = true

    var pinX: CGFloat { tag.posX * containerSize.width }
    var pinY: CGFloat { tag.posY * containerSize.height }
    var labelOnLeft: Bool { tag.posX > 0.6 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Animated pulsing ring
            ZStack {
                Circle()
                    .fill(Color.snapshePurple.opacity(0.25))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.2), radius: 3)
                Circle()
                    .fill(Color.snapshePurple)
                    .frame(width: 11, height: 11)
            }
            .position(x: pinX, y: pinY)
            .onTapGesture {
                withAnimation(.spring(response: 0.25)) { showLabel.toggle() }
            }

            // Label bubble — shown on tap
            if showLabel {
                Button(action: onTap) {
                    HStack(spacing: 5) {
                        Text(tag.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                        if !tag.category.isEmpty {
                            Text(tag.category)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "#555"))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.snapshePurple)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .position(
                    x: labelOnLeft ? pinX - 60 : pinX + 60,
                    y: pinY - 30
                )
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .allowsHitTesting(true)
    }
}

// MARK: - BrandPostItem (used in BrandPageView)

struct BrandPostItem: View {
    @EnvironmentObject var auth: AuthManager
    let post: StylePost
    @State private var showProfile = false
    @State private var showShopSimilar = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: post.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width)

                // Brand tag pins
                ForEach(post.brandTags) { tag in
                    BrandPinView(tag: tag, containerSize: geo.size, onDelete: {})
                }

                // Bottom bar: username + shop button
                HStack {
                    Button { showProfile = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 13))
                            Text("@\(post.username)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.snapsheBlack.opacity(0.72))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button { showShopSimilar = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 11, weight: .bold))
                            Text("Shop Similar")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.snapshePurple.opacity(0.9))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }
            .frame(width: geo.size.width,
                   height: geo.size.width * post.image.size.height / max(post.image.size.width, 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(height: (UIScreen.main.bounds.width - 32) * post.image.size.height / max(post.image.size.width, 1))
        .sheet(isPresented: $showProfile) {
            PublicProfileView(username: post.username).environmentObject(auth)
        }
        .sheet(isPresented: $showShopSimilar) {
            ShopSimilarView(post: post).environmentObject(auth)
        }
    }
}

// MARK: - BrandPageView


struct BrandPageView: View {
    @Environment(\.dismiss) var dismiss
    let brandName: String
    let posts: [StylePost]

    var brandPosts: [StylePost] {
        posts.filter { $0.brandTags.contains { $0.name == brandName } }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Brand header
                    VStack(spacing: 10) {
                        // Brandfetch logo
                        let domain = brandName.lowercased()
                            .replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: "&", with: "and") + ".com"
                        let logoURL = URL(string: "https://cdn.brandfetch.io/domain/\(domain)/h/160/w/160/icon.png?c=1idTepj4w4y1xlCSbo_")

                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.snapshePurple.opacity(0.12), Color.snapshePink.opacity(0.12)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 88, height: 88)

                            AsyncImage(url: logoURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                default:
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.snapshePurple)
                                }
                            }
                        }

                        Text(brandName)
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)

                        Text("\(brandPosts.count) style post\(brandPosts.count != 1 ? "s" : "")")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#888"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.snapsheGray)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)

                    if brandPosts.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36))
                                .foregroundStyle(Color(hex: "#DDD"))
                            Text("No one has tagged this brand yet")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#AAA"))
                        }
                        .padding(40)
                    } else {
                        // Single column — full images, no crop
                        LazyVStack(spacing: 12) {
                            ForEach(brandPosts) { post in
                                BrandPostItem(post: post)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(brandName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
        }
    }
}

// MARK: - NewStylePostView (Yeni post oluşturma)

// MARK: - StyleFilter

struct StyleFilter: Identifiable, Equatable {
    let id: String
    let name: String
    // CIFilter name + params
    let filterName: String?
    let params: [String: Any]

    static func == (l: StyleFilter, r: StyleFilter) -> Bool { l.id == r.id }

    static let all: [StyleFilter] = [
        StyleFilter(id: "none",      name: "Original",  filterName: nil,                         params: [:]),
        StyleFilter(id: "vivid",     name: "Vivid",     filterName: "CIVibrance",                params: ["inputAmount": 1.0 as NSNumber]),
        StyleFilter(id: "fade",      name: "Fade",      filterName: "CIColorControls",           params: ["inputSaturation": 0.5 as NSNumber, "inputBrightness": 0.05 as NSNumber]),
        StyleFilter(id: "warm",      name: "Warm",      filterName: "CITemperatureAndTint",      params: ["inputNeutral": CIVector(x: 4500, y: 0)]),
        StyleFilter(id: "cool",      name: "Cool",      filterName: "CITemperatureAndTint",      params: ["inputNeutral": CIVector(x: 7500, y: 0)]),
        StyleFilter(id: "mono",      name: "Mono",      filterName: "CIColorMonochrome",         params: ["inputColor": CIColor(red: 0.7, green: 0.7, blue: 0.7), "inputIntensity": 1.0 as NSNumber]),
        StyleFilter(id: "noir",      name: "Noir",      filterName: "CIPhotoEffectNoir",         params: [:]),
        StyleFilter(id: "chrome",    name: "Chrome",    filterName: "CIPhotoEffectChrome",       params: [:]),
        StyleFilter(id: "fade2",     name: "Matte",     filterName: "CIPhotoEffectProcess",      params: [:]),
        StyleFilter(id: "instant",   name: "Instant",   filterName: "CIPhotoEffectInstant",      params: [:]),
        StyleFilter(id: "transfer",  name: "Transfer",  filterName: "CIPhotoEffectTransfer",     params: [:]),
    ]

    func apply(to image: UIImage) -> UIImage {
        guard let filterName = filterName,
              let ciImage = CIImage(image: image),
              let filter = CIFilter(name: filterName) else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        for (k, v) in params { filter.setValue(v, forKey: k) }
        guard let output = filter.outputImage else { return image }
        let ctx = CIContext()
        guard let cgImg = ctx.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: cgImg, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - NewStylePostView

enum NewPostStep: Int, CaseIterable {
    case source       // pick: camera or gallery
    case filter       // apply filter
    case tag          // pin brand tags
    case caption      // write caption + share
}

struct NewStylePostView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager
    let onPost: (UIImage, String, [BrandTag], String) -> Void

    // Step flow
    @State private var step: NewPostStep = .source

    // Image
    @State private var rawImage: UIImage? = nil          // original from camera/gallery
    @State private var filteredImage: UIImage? = nil     // after filter applied
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showCamera = false
    @State private var showPicker = false

    // Filter
    @State private var selectedFilter: StyleFilter = .all[0]

    // Tags
    @State private var brandTags: [BrandTag] = []
    @State private var pendingTagPos: CGPoint? = nil
    @State private var showBrandPin = false

    // Caption
    @State private var caption = ""
    @FocusState private var captionFocused: Bool

    var displayImage: UIImage? { filteredImage ?? rawImage }
    var canShare: Bool { displayImage != nil && !brandTags.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Step indicator ──────────────────────────────
                stepBar

                // ── Content per step ────────────────────────────
                switch step {
                case .source:   sourceStep
                case .filter:   filterStep
                case .tag:      tagStep
                case .caption:  captionStep
                }
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if step == .source {
                            dismiss()
                        } else {
                            step = NewPostStep(rawValue: step.rawValue - 1) ?? .source
                        }
                    } label: {
                        Image(systemName: step == .source ? "xmark" : "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(stepTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.snapsheBlack)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if step != .source && step != .caption {
                        Button("Next") {
                            step = NewPostStep(rawValue: step.rawValue + 1) ?? .caption
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.snapshePurple)
                        .disabled(displayImage == nil)
                    }
                }
            }
        }
        // Camera — fullScreenCover stays open until we explicitly close it
        .fullScreenCover(isPresented: $showCamera) {
            StyleCameraView(
                onCapture: { captured in
                    rawImage = captured
                    filteredImage = captured
                    selectedFilter = .all[0]
                    brandTags = []
                    showCamera = false   // close camera, stay in NewStylePostView
                    step = .filter
                },
                onCancel: {
                    showCamera = false   // close camera, go back to source step
                }
            )
        }
        // Gallery picker sheet
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    rawImage = img
                    filteredImage = img
                    selectedFilter = .all[0]
                    brandTags = []
                    step = .filter
                }
                pickerItem = nil
            }
        }
        // Brand pin sheet
        .sheet(isPresented: $showBrandPin) {
            BrandPinNameSheet { name, category in
                guard let pos = pendingTagPos else { return }
                brandTags.append(BrandTag(name: name, category: category, posX: pos.x, posY: pos.y))
                pendingTagPos = nil
            }
        }
    }

    // MARK: - Step bar

    var stepBar: some View {
        HStack(spacing: 4) {
            ForEach(NewPostStep.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.snapshePurple : Color(hex: "#E0E0E0"))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.25), value: step)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    var stepTitle: String {
        switch step {
        case .source:  return "New Post"
        case .filter:  return "Choose Filter"
        case .tag:     return "Tag Brands"
        case .caption: return "Share Your Look"
        }
    }

    // MARK: - Step 1: Source

    var sourceStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Camera button
                Button { showCamera = true } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.snapsheBlack)
                                .frame(width: 56, height: 56)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Take a Photo")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                            Text("Use your camera")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#999"))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#CCC"))
                    }
                    .padding(18)
                    .background(Color.snapsheGray)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                // Gallery button
                Button { showPicker = true } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.snapshePurple)
                                .frame(width: 56, height: 56)
                            Image(systemName: "photo.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Choose from Gallery")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.snapsheBlack)
                            Text("Pick an existing photo")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#999"))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#CCC"))
                    }
                    .padding(18)
                    .background(Color.snapsheGray)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Step 2: Filter

    var filterStep: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Photo fills all space above the bottom controls
                if let img = displayImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height - 160)
                        .clipped()
                        .animation(.easeInOut(duration: 0.2), value: selectedFilter.id)
                }

                // Filter strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(StyleFilter.all) { filter in
                            FilterThumb(
                                filter: filter,
                                image: rawImage,
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                                if let raw = rawImage {
                                    Task.detached(priority: .userInitiated) {
                                        let result = filter.apply(to: raw)
                                        await MainActor.run { filteredImage = result }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .frame(height: 100)

                // Next button
                Button { step = .tag } label: {
                    Text("Next — Tag Brands")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.snapshePurple)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .frame(height: 60)
            }
        }
    }

    // MARK: - Step 3: Tag brands

    var tagStep: some View {
        VStack(spacing: 0) {
            // Hint bar
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.snapshePurple)
                Text("Tap on the photo to pin a brand")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#555"))
                Spacer()
                if !brandTags.isEmpty {
                    Text("\(brandTags.count) tagged")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.snapshePurple)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.snapshePurple.opacity(0.06))

            // Photo + pins — full image, no crop
            if let img = displayImage {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()          // ← shows full photo, no crop
                        .frame(maxWidth: .infinity)
                        .overlay(
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { loc in
                                        pendingTagPos = CGPoint(
                                            x: max(0.05, min(0.95, loc.x / geo.size.width)),
                                            y: max(0.05, min(0.95, loc.y / geo.size.height))
                                        )
                                        showBrandPin = true
                                    }
                            }
                        )

                    // Pin overlays
                    GeometryReader { geo in
                        ForEach(brandTags) { tag in
                            BrandPinView(
                                tag: tag,
                                containerSize: geo.size,
                                onDelete: { brandTags.removeAll { $0.id == tag.id } }
                            )
                        }
                        // Purple border
                        Rectangle()
                            .stroke(Color.snapshePurple, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Tags list
            if !brandTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(brandTags) { tag in
                            HStack(spacing: 5) {
                                Circle().fill(Color.snapshePurple).frame(width: 7, height: 7)
                                Text(tag.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.snapsheBlack)
                                Button {
                                    brandTags.removeAll { $0.id == tag.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color(hex: "#999"))
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.snapshePurple.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }

            Spacer()

            Button {
                step = .caption
            } label: {
                Text(brandTags.isEmpty ? "Skip — Add Caption" : "Next — Add Caption")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.snapshePurple)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Step 4: Caption + Share

    var captionStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Photo preview with pins — full image, no crop
                if let img = displayImage {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        GeometryReader { geo in
                            ForEach(brandTags) { tag in
                                BrandPinView(
                                    tag: tag,
                                    containerSize: geo.size,
                                    onDelete: { brandTags.removeAll { $0.id == tag.id } }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Brand tags summary
                if !brandTags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(brandTags) { tag in
                            HStack(spacing: 5) {
                                Circle().fill(Color.snapshePurple).frame(width: 7, height: 7)
                                Text(tag.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.snapshePurple)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.snapshePurple.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "tag")
                            .foregroundStyle(Color(hex: "#BBB"))
                        Text("No brands tagged")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#BBB"))
                        Spacer()
                        Button("Go back to tag") { step = .tag }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.snapshePurple)
                    }
                    .padding(.horizontal, 16)
                }

                // Caption field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caption")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "#555"))
                    TextField("Say something about your look... (optional)", text: $caption, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color.snapsheGray)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .focused($captionFocused)
                }
                .padding(.horizontal, 16)

                // Share button
                Button {
                    guard let img = displayImage else { return }
                    onPost(img, caption, brandTags, auth.currentUser?.username ?? "me")
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Share Your Look")
                            .font(.system(size: 16, weight: .black))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(canShare ? Color.snapshePurple : Color(hex: "#CCC"))
                    .clipShape(Capsule())
                }
                .disabled(!canShare)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - FilterThumb

struct FilterThumb: View {
    let filter: StyleFilter
    let image: UIImage?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var preview: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    if let prev = preview {
                        Image(uiImage: prev)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipped()
                    } else {
                        Color.snapsheGray
                            .frame(width: 68, height: 68)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.snapshePurple : Color.clear, lineWidth: 3)
                )
                .shadow(color: isSelected ? Color.snapshePurple.opacity(0.35) : .clear, radius: 6)

                Text(filter.name)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.snapshePurple : Color(hex: "#666"))
            }
        }
        .buttonStyle(.plain)
        .task {
            guard let img = image else { return }
            // Generate thumb async so UI doesn't block
            preview = await Task.detached(priority: .userInitiated) {
                let small = img.thumbnailSize(CGSize(width: 136, height: 136))
                return filter.apply(to: small)
            }.value
        }
    }
}

extension UIImage {
    func thumbnailSize(_ size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - StyleCameraView

struct StyleCameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // DO NOT call picker.dismiss — SwiftUI manages the fullScreenCover lifecycle
            if let img = info[.originalImage] as? UIImage {
                onCapture(img)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            // DO NOT call picker.dismiss — just notify SwiftUI
            onCancel()
        }
    }
}

// MARK: - BrandPinView (pin on photo)

struct BrandPinView: View {
    let tag: BrandTag
    let containerSize: CGSize
    let onDelete: () -> Void

    @State private var showLabel = true

    var pinX: CGFloat { tag.posX * containerSize.width }
    var pinY: CGFloat { tag.posY * containerSize.height }

    // Flip label direction if too close to right edge
    var labelOnLeft: Bool { tag.posX > 0.6 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Label
            if showLabel {
                HStack(spacing: 0) {
                    if labelOnLeft {
                        Spacer(minLength: 0)
                        brandLabel
                        // line to dot
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 18, height: 1.5)
                    } else {
                        // line to dot
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 18, height: 1.5)
                        brandLabel
                    }
                }
                .fixedSize()
                .position(
                    x: labelOnLeft ? pinX - 9 : pinX + 9,
                    y: pinY - 22
                )
            }

            // Dot + ring
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.25), radius: 4)
                Circle()
                    .fill(Color.snapshePurple)
                    .frame(width: 12, height: 12)
            }
            .position(x: pinX, y: pinY)
            .onTapGesture { showLabel.toggle() }
            .onLongPressGesture { onDelete() }
        }
        .frame(width: containerSize.width, height: containerSize.height)
    }

    var brandLabel: some View {
        HStack(spacing: 5) {
            Text(tag.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.snapsheBlack)
            if !tag.category.isEmpty {
                Text(tag.category)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#555"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
        )
    }
}

// MARK: - BrandPinNameSheet (quick name entry after tap)

struct BrandPinNameSheet: View {
    @Environment(\.dismiss) var dismiss
    let onConfirm: (String, String) -> Void

    @State private var searchText = ""
    @State private var selectedCategory = ""
    @FocusState private var focused: Bool

    let categories = ["Top", "Bottom", "Shoes", "Bag", "Accessory", "Outerwear", "Other"]

    var filteredBrands: [String] {
        if searchText.isEmpty { return BrandTag.popular }
        return BrandTag.popular.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(hex: "#888"))
                    TextField("Search brand name...", text: $searchText)
                        .autocorrectionDisabled()
                        .autocapitalization(.words)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit {
                            guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            onConfirm(searchText.trimmingCharacters(in: .whitespaces), selectedCategory)
                            dismiss()
                        }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "#CCC"))
                        }
                    }
                }
                .padding(13)
                .background(Color.snapsheGray)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(16)

                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = selectedCategory == cat ? "" : cat
                            } label: {
                                Text(cat)
                                    .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .regular))
                                    .foregroundStyle(selectedCategory == cat ? .white : Color.snapsheBlack)
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(selectedCategory == cat ? Color.snapshePurple : Color.snapsheGray)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                Divider()

                List {
                    // Custom entry
                    if !searchText.isEmpty && !BrandTag.popular.contains(where: { $0.lowercased() == searchText.lowercased() }) {
                        Button {
                            onConfirm(searchText.trimmingCharacters(in: .whitespaces), selectedCategory)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.snapshePurple.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.snapshePurple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pin \"\(searchText)\"")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Text("Custom brand")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "#999"))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(filteredBrands, id: \.self) { brand in
                        Button {
                            onConfirm(brand, selectedCategory)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(Color.snapsheGray)
                                        .frame(width: 38, height: 38)
                                    Text(String(brand.prefix(1)))
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(Color(hex: "#888"))
                                }
                                Text(brand)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.snapsheBlack)
                                Spacer()
                                // Pin dot indicator
                                ZStack {
                                    Circle().fill(Color.white).frame(width: 20, height: 20)
                                        .shadow(radius: 2)
                                    Circle().fill(Color.snapshePurple).frame(width: 10, height: 10)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Pin a Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - BrandSearchSheet

struct BrandSearchSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var brandTags: [BrandTag]

    @State private var searchText = ""
    @State private var selectedCategory = ""
    @State private var customBrandName = ""

    let categories = ["Top", "Bottom", "Shoes", "Bag", "Accessory", "Outerwear", "Other"]

    var filteredBrands: [String] {
        if searchText.isEmpty { return BrandTag.popular }
        return BrandTag.popular.filter { $0.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color(hex: "#888"))
                    TextField("Search or type a brand...", text: $searchText)
                        .autocorrectionDisabled()
                        .autocapitalization(.words)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(hex: "#CCC"))
                        }
                    }
                }
                .padding(12)
                .background(Color.snapsheGray)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = selectedCategory == cat ? "" : cat
                            } label: {
                                Text(cat)
                                    .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .regular))
                                    .foregroundStyle(selectedCategory == cat ? .white : Color.snapsheBlack)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selectedCategory == cat ? Color.snapshePurple : Color.snapsheGray)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }

                // Added tags preview
                if !brandTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(brandTags) { tag in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.snapshePurple)
                                    Text(tag.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Button {
                                        brandTags.removeAll { $0.id == tag.id }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color(hex: "#999"))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.snapshePurple.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                    Divider()
                }

                Divider()

                List {
                    // Custom brand entry
                    if !searchText.isEmpty && !BrandTag.popular.contains(where: { $0.lowercased() == searchText.lowercased() }) {
                        Button {
                            addBrand(name: searchText)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.snapshePurple.opacity(0.12))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: "plus")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.snapshePurple)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add \"\(searchText)\"")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.snapsheBlack)
                                    Text("Custom brand")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color(hex: "#999"))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }

                    ForEach(filteredBrands, id: \.self) { brand in
                        let isAdded = brandTags.contains { $0.name == brand }
                        Button {
                            if isAdded {
                                brandTags.removeAll { $0.name == brand }
                            } else {
                                addBrand(name: brand)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(isAdded ? Color.snapshePurple : Color.snapsheGray)
                                        .frame(width: 38, height: 38)
                                    Text(String(brand.prefix(1)))
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(isAdded ? .white : Color(hex: "#888"))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(brand)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.snapsheBlack)
                                    if isAdded, let tag = brandTags.first(where: { $0.name == brand }) {
                                        Text(tag.category.isEmpty ? "Tagged" : tag.category)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.snapshePurple)
                                    }
                                }
                                Spacer()
                                if isAdded {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.snapshePurple)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Tag Brands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.snapshePurple)
                }
            }
        }
    }

    func addBrand(name: String) {
        guard !brandTags.contains(where: { $0.name == name }) else { return }
        brandTags.append(BrandTag(name: name, category: selectedCategory))
        searchText = ""
    }
}

// MARK: - ShopSimilarView (Real API)

struct ShopSimilarView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var auth: AuthManager
    let post: StylePost

    @State private var isLoading = false
    @State private var realProducts: [Product] = []
    @State private var errorMessage: String? = nil
    @State private var selectedTag: BrandTag? = nil
    @State private var productToSave: Product? = nil
    @State private var showSaveModal = false

    // Crop state
    @State private var showCrop = false
    @State private var cropRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    @State private var pendingTag: BrandTag? = nil

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {

                    // ── Photo with crop overlay ──────────────────────────
                    GeometryReader { geo in
                        ZStack {
                            Image(uiImage: post.image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width)

                            if showCrop {
                                CropOverlayView(
                                    cropRect: $cropRect,
                                    imageSize: geo.size
                                )
                            }
                        }
                        .frame(width: geo.size.width,
                               height: geo.size.width * (post.image.size.height / max(post.image.size.width, 1)))
                        .clipped()
                    }
                    .frame(height: UIScreen.main.bounds.width * (post.image.size.height / max(post.image.size.width, 1)))
                    .background(Color.black)

                    // ── Crop toolbar (shown when crop active) ────────────
                    if showCrop {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                showCrop = false
                                pendingTag = nil
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: "#666"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Color.snapsheGray)
                            .clipShape(Capsule())

                            Button {
                                let tag = pendingTag
                                showCrop = false
                                Task { await loadProducts(for: tag, crop: cropRect) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkle.magnifyingglass")
                                    Text("Search this area")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Color.snapshePurple)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        Divider()
                    }

                    // ── Brand tag chips ──────────────────────────────────
                    if !post.brandTags.isEmpty && !showCrop {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(post.brandTags) { tag in
                                    Button {
                                        // Open crop UI centred on this tag's pin position
                                        pendingTag = tag
                                        cropRect = CGRect(
                                            x: max(0, tag.posX - 0.25),
                                            y: max(0, tag.posY - 0.25),
                                            width: 0.5,
                                            height: 0.5
                                        )
                                        showCrop = true
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "tag.fill")
                                                .font(.system(size: 10, weight: .bold))
                                            Text(tag.name)
                                                .font(.system(size: 13, weight: .semibold))
                                            if !tag.category.isEmpty {
                                                Text("· \(tag.category)")
                                                    .font(.system(size: 12))
                                                    .opacity(0.7)
                                            }
                                            Image(systemName: "crop")
                                                .font(.system(size: 10))
                                                .opacity(0.6)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(selectedTag?.id == tag.id ? Color.snapshePurple : Color.snapsheGray)
                                        .foregroundStyle(selectedTag?.id == tag.id ? Color.white : Color.snapsheBlack)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        Divider()
                    }

                    // ── Results ──────────────────────────────────────────
                    if isLoading {
                        VStack(spacing: 14) {
                            ProgressView().tint(Color.snapshePurple).scaleEffect(1.2)
                            Text("Finding similar products...")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#888"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)

                    } else if let err = errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 32))
                                .foregroundStyle(Color(hex: "#DDD"))
                            Text(err)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "#AAA"))
                                .multilineTextAlignment(.center)
                            Button("Try Again") { Task { await loadProducts(for: selectedTag) } }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.snapshePurple)
                        }
                        .padding(40)

                    } else if realProducts.isEmpty && !showCrop {
                        VStack(spacing: 12) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(Color(hex: "#DDD"))
                            Text("Tap a brand tag to crop & search")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: "#AAA"))
                            Text("Select the exact area you want to search")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#BBB"))
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)

                    } else if !realProducts.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 16
                        ) {
                            ForEach(realProducts) { product in
                                RealProductCard(product: product) {
                                    productToSave = product
                                    showSaveModal = true
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Shop Similar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
        }
        .sheet(isPresented: $showSaveModal) {
            if let product = productToSave {
                SaveToCollectionView(product: product)
            }
        }
    }

    // MARK: - Load products via visual search API

    func loadProducts(for tag: BrandTag? = nil, crop: CGRect? = nil) async {
        selectedTag = tag
        isLoading = true
        errorMessage = nil
        realProducts = []

        guard let imageData = post.image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Could not process image."
            isLoading = false
            return
        }

        // Build crop string
        let cropStr: String?
        if let c = crop {
            let left   = max(0.0, c.minX)
            let top    = max(0.0, c.minY)
            let right  = min(1.0, c.maxX)
            let bottom = min(1.0, c.maxY)
            cropStr = String(format: "%.4f;%.4f;%.4f;%.4f", left, top, right, bottom)
        } else if let t = tag {
            let cx = t.posX, cy = t.posY
            let left   = max(0.0, cx - 0.25)
            let top    = max(0.0, cy - 0.25)
            let right  = min(1.0, cx + 0.25)
            let bottom = min(1.0, cy + 0.25)
            cropStr = String(format: "%.4f;%.4f;%.4f;%.4f", left, top, right, bottom)
        } else {
            cropStr = nil
        }

        let keyword = tag?.name ?? post.brandTags.map { $0.name }.joined(separator: " ")

        do {
            let response = try await APIService.shared.visualSearch(
                imageData: imageData,
                imageURL: nil,
                crop: cropStr,
                keyword: keyword.isEmpty ? nil : keyword,
                token: auth.token
            )
            if response.ok {
                realProducts = response.products ?? []
            } else {
                errorMessage = response.error ?? "Search failed. Please try again."
            }
        } catch {
            errorMessage = "Connection error. Please check your network."
        }

        isLoading = false
    }
}


// MARK: - CropOverlayView

struct CropOverlayView: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize

    @State private var dragStart: CGRect = .zero
    @State private var activeHandle: String = ""

    let minSize: CGFloat = 0.1

    var body: some View {
        ZStack {
            // Dim outside crop
            Color.black.opacity(0.45)
                .mask(
                    Rectangle()
                        .overlay(
                            Rectangle()
                                .frame(
                                    width: cropRect.width * imageSize.width,
                                    height: cropRect.height * imageSize.height
                                )
                                .offset(
                                    x: (cropRect.midX - 0.5) * imageSize.width,
                                    y: (cropRect.midY - 0.5) * imageSize.height
                                )
                                .blendMode(.destinationOut)
                        )
                )
                .allowsHitTesting(false)

            // Crop box border
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(
                    width: cropRect.width * imageSize.width,
                    height: cropRect.height * imageSize.height
                )
                .offset(
                    x: (cropRect.midX - 0.5) * imageSize.width,
                    y: (cropRect.midY - 0.5) * imageSize.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if activeHandle == "" || activeHandle == "move" {
                                activeHandle = "move"
                                if v.translation == .zero { dragStart = cropRect }
                                let dx = v.translation.width  / imageSize.width
                                let dy = v.translation.height / imageSize.height
                                let nx = max(0, min(1 - dragStart.width,  dragStart.minX + dx))
                                let ny = max(0, min(1 - dragStart.height, dragStart.minY + dy))
                                cropRect = CGRect(x: nx, y: ny, width: dragStart.width, height: dragStart.height)
                            }
                        }
                        .onEnded { _ in activeHandle = "" }
                )

            // Corner handles
            ForEach(["tl","tr","bl","br"], id: \.self) { h in
                cropHandle(h)
            }
        }
    }

    func handlePos(_ h: String) -> CGPoint {
        let bx = cropRect.minX * imageSize.width
        let by = cropRect.minY * imageSize.height
        let bw = cropRect.width  * imageSize.width
        let bh = cropRect.height * imageSize.height
        switch h {
        case "tl": return CGPoint(x: bx,      y: by)
        case "tr": return CGPoint(x: bx + bw, y: by)
        case "bl": return CGPoint(x: bx,      y: by + bh)
        default:   return CGPoint(x: bx + bw, y: by + bh)
        }
    }

    func cropHandle(_ h: String) -> some View {
        let pos = handlePos(h)
        return Rectangle()
            .fill(Color.white)
            .frame(width: 20, height: 20)
            .cornerRadius(4)
            .shadow(radius: 2)
            .position(x: pos.x + imageSize.width * 0.0,
                      y: pos.y + imageSize.height * 0.0)
            .offset(x: -imageSize.width/2, y: -imageSize.height/2)
            .gesture(
                DragGesture()
                    .onChanged { v in
                        if activeHandle == "" || activeHandle == h { activeHandle = h }
                        if v.translation == .zero { dragStart = cropRect }
                        let dx = v.translation.width  / imageSize.width
                        let dy = v.translation.height / imageSize.height
                        var r = dragStart
                        switch h {
                        case "tl":
                            let nx = min(r.maxX - minSize, r.minX + dx)
                            let ny = min(r.maxY - minSize, r.minY + dy)
                            r = CGRect(x: max(0,nx), y: max(0,ny),
                                       width: r.maxX - max(0,nx), height: r.maxY - max(0,ny))
                        case "tr":
                            let ny = min(r.maxY - minSize, r.minY + dy)
                            let nw = max(minSize, min(1 - r.minX, r.width + dx))
                            r = CGRect(x: r.minX, y: max(0,ny), width: nw, height: r.maxY - max(0,ny))
                        case "bl":
                            let nx = min(r.maxX - minSize, r.minX + dx)
                            let nh = max(minSize, min(1 - r.minY, r.height + dy))
                            r = CGRect(x: max(0,nx), y: r.minY, width: r.maxX - max(0,nx), height: nh)
                        default: // br
                            let nw = max(minSize, min(1 - r.minX, r.width + dx))
                            let nh = max(minSize, min(1 - r.minY, r.height + dy))
                            r = CGRect(x: r.minX, y: r.minY, width: nw, height: nh)
                        }
                        cropRect = r
                    }
                    .onEnded { _ in activeHandle = "" }
            )
    }
}

// MARK: - RealProductCard

struct RealProductCard: View {
    let product: Product
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: product.thumbnailURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(height: 170)
                            .clipped()
                    case .failure:
                        Color.snapsheGray
                            .frame(height: 170)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color(hex: "#BBB"))
                                    .font(.system(size: 28))
                            )
                    default:
                        Color.snapsheGray
                            .frame(height: 170)
                            .shimmering()
                    }
                }
                .frame(height: 170)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = APIService.affiliateURL(for: product.link) {
                        UIApplication.shared.open(url)
                    }
                }

                if !product.price.isEmpty {
                    Text(product.price)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.snapsheBlack.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(product.source)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.snapshePurple)
                    .lineLimit(1)
                Text(product.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.snapsheBlack)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Button {
                        if let url = APIService.affiliateURL(for: product.link) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("View")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(Color.snapsheBlack)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button(action: onSave) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.snapsheGray)
                            .foregroundStyle(Color.snapsheBlack)
                            .clipShape(Circle())
                    }
                    .simultaneousGesture(TapGesture().onEnded { _ in })
                }
                .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.snapsheBlack.opacity(0.07), radius: 8, y: 2)
    }
}

// MARK: - FlowLayout (wrapping tag row)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        height += rowH
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

// FollowingFeedViewModel is defined in HomeViewModel.swift
