import SwiftUI

// MARK: - ProfileView (own profile, opened from tab/topbar)
struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showSettings = false
    @State private var uploads: [FeedPhoto] = []
    @State private var isLoading = true
    @State private var selectedPhoto: FeedPhoto? = nil

    let columns = [GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3)]

    var user: SnapUser? { auth.currentUser }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    profileHeader(user: user, isOwn: true)

                    Divider()

                    uploadsGrid
                }
            }
            .refreshable { await loadUploads() }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.snapsheBlack)
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $selectedPhoto) { item in
            if item.mediaType == .video, let url = item.mediaURL {
                VideoVisualSearchView(videoURL: url, serverVideoPath: item.video)
            } else {
                VisualSearchView(feedPhotoURL: item.mediaURL?.absoluteString, initialImage: nil)
            }
        }
        .task { await loadUploads() }
    }

    var uploadsGrid: some View {
        Group {
            if isLoading {
                ProgressView().tint(Color.snapshePurple).padding(40)
            } else if uploads.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 32)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44)).foregroundStyle(Color(hex: "#ddd"))
                    Text("No uploads yet")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "#aaa"))
                    Text("Photos you upload through visual search will appear here.")
                        .font(.system(size: 14)).foregroundStyle(Color(hex: "#ccc"))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Spacer(minLength: 32)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(uploads) { photo in
                        ProfilePhotoTile(photo: photo)
                            .onTapGesture { selectedPhoto = photo }
                    }
                }
            }
        }
    }

    func loadUploads() async {
        // isLoading sadece ilk yüklemede true — refresh'te mevcut görseller kaybolmasın
        if uploads.isEmpty { isLoading = true }
        let r = try? await APIService.shared.fetchProfile(token: auth.token)
        if let newUploads = r?.uploads, !newUploads.isEmpty {
            uploads = newUploads
        } else if r?.ok == true {
            uploads = r?.uploads ?? []
        }
        isLoading = false
    }
}

// MARK: - PublicProfileView (for viewing other users, tapped from search)
struct PublicProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let username: String

    @State private var profileUser: SnapUser? = nil
    @State private var uploads: [FeedPhoto] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var selectedPhoto: FeedPhoto? = nil

    let columns = [GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView().tint(Color.snapshePurple).padding(60)
                    } else if let err = error {
                        Text(err).foregroundStyle(.red).padding(40)
                    } else {
                        profileHeader(user: profileUser, isOwn: false)
                        Divider()

                        if uploads.isEmpty {
                            VStack(spacing: 14) {
                                Spacer(minLength: 32)
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 44)).foregroundStyle(Color(hex: "#ddd"))
                                Text("No uploads yet")
                                    .font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "#aaa"))
                                Spacer(minLength: 32)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(uploads) { photo in
                                    ProfilePhotoTile(photo: photo)
                                        .onTapGesture { selectedPhoto = photo }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color.white)
            .navigationTitle("@\(username)")
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
        .sheet(item: $selectedPhoto) { item in
            if item.mediaType == .video, let url = item.mediaURL {
                VideoVisualSearchView(videoURL: url, serverVideoPath: item.video)
            } else {
                VisualSearchView(feedPhotoURL: item.mediaURL?.absoluteString, initialImage: nil)
            }
        }
        .task { await loadProfile() }
    }

    func loadProfile() async {
        isLoading = true
        do {
            let r = try await APIService.shared.fetchProfile(username: username, token: auth.token)
            if r.ok {
                profileUser = r.user
                uploads = r.uploads ?? []
            } else {
                error = r.error ?? "Could not load profile."
            }
        } catch {
            self.error = "Network error."
        }
        isLoading = false
    }
}

// MARK: - Shared profile header (matches site)
@ViewBuilder
func profileHeader(user: SnapUser?, isOwn: Bool) -> some View {
    VStack(spacing: 0) {
        // Gradient banner
        ZStack(alignment: .bottom) {
            snapsheGradient
                .frame(height: 110)
                .overlay(Color.black.opacity(0.15))

            AvatarCircle(user: user, size: 84)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.12), radius: 6)
                .offset(y: 42)
        }

        VStack(spacing: 5) {
            Text(user?.displayName ?? "")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Color.snapsheBlack)
            Text("@\(user?.username ?? "")")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#888"))
        }
        .padding(.top, 50)
        .padding(.bottom, 18)
    }
}

// MARK: - Photo/Video tile (Instagram-style grid)
struct ProfilePhotoTile: View {
    let photo: FeedItem   // FeedItem = FeedPhoto (typealias)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width

            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: photo.coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.snapsheGray
                            .overlay(
                                Image(systemName: photo.mediaType == .video ? "video.slash" : "photo")
                                    .foregroundStyle(.tertiary)
                            )
                    default:
                        Color.snapsheGray.shimmering()
                    }
                }
                .frame(width: size, height: size)
                .clipped()

                if photo.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.snapshePurple.opacity(0.9))
                        .clipShape(Circle())
                        .padding(6)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}
