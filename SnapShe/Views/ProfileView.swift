import SwiftUI

// MARK: - ProfileView (own profile, opened from tab/topbar)
struct ProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showSettings = false
    @State private var uploads: [FeedPhoto] = []
    @State private var isLoading = true
    @State private var selectedPhoto: FeedPhoto? = nil

    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var showFollowersList = false
    @State private var showFollowingList = false

    let columns = [GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3), GridItem(.flexible(minimum: 0), spacing: 3)]

    var user: SnapUser? { auth.currentUser }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ownProfileHeader(user: user)
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
        .sheet(isPresented: $showFollowersList) {
            FollowListView(username: user?.username ?? "", listType: .followers)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showFollowingList) {
            FollowListView(username: user?.username ?? "", listType: .following)
                .environmentObject(auth)
        }
        .sheet(item: $selectedPhoto) { item in
            if item.mediaType == .video, let url = item.mediaURL {
                VideoVisualSearchView(videoURL: url, serverVideoPath: item.video)
            } else {
                VisualSearchView(feedPhotoURL: item.mediaURL?.absoluteString, initialImage: nil)
            }
        }
        .task { await loadUploads() }
    }

    @ViewBuilder
    func ownProfileHeader(user: SnapUser?) -> some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 12)

            HStack(spacing: 32) {
                Button { showFollowersList = true } label: {
                    VStack(spacing: 2) {
                        Text("\(followerCount)")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Followers")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                }
                .buttonStyle(.plain)

                Button { showFollowingList = true } label: {
                    VStack(spacing: 2) {
                        Text("\(followingCount)")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Following")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)
        }
    }

    @State private var uploadToDelete: FeedPhoto? = nil
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false

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
                            .contextMenu {
                                Button(role: .destructive) {
                                    uploadToDelete = photo
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this \(uploadToDelete?.mediaType == .video ? "video" : "photo")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let item = uploadToDelete {
                    Task { await deleteUpload(item) }
                }
            }
            Button("Cancel", role: .cancel) { uploadToDelete = nil }
        } message: {
            Text("This will be permanently removed from your profile.")
        }
    }

    func deleteUpload(_ item: FeedPhoto) async {
        isDeleting = true
        let result = try? await APIService.shared.deleteUpload(uploadId: item.id, token: auth.token)
        if result?.ok == true {
            uploads.removeAll { $0.id == item.id }
        }
        uploadToDelete = nil
        isDeleting = false
    }

    func loadUploads() async {
        if uploads.isEmpty { isLoading = true }
        let r = try? await APIService.shared.fetchProfile(token: auth.token)
        if let newUploads = r?.uploads, !newUploads.isEmpty {
            uploads = newUploads
        } else if r?.ok == true {
            uploads = r?.uploads ?? []
        }
        if let fc = r?.followerCount  { followerCount  = fc }
        if let fg = r?.followingCount { followingCount = fg }
        isLoading = false
    }
}

// MARK: - PublicProfileView

struct PublicProfileView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let username: String

    @State private var profileUser: SnapUser? = nil
    @State private var uploads: [FeedPhoto] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var selectedPhoto: FeedPhoto? = nil

    @State private var isFollowing = false
    @State private var followerCount: Int = 0
    @State private var followingCount: Int = 0
    @State private var isFollowLoading = false
    @State private var showFollowersList = false
    @State private var showFollowingList = false

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
                        publicProfileHeader(user: profileUser)
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
        .sheet(isPresented: $showFollowersList) {
            FollowListView(username: username, listType: .followers)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showFollowingList) {
            FollowListView(username: username, listType: .following)
                .environmentObject(auth)
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

    @ViewBuilder
    func publicProfileHeader(user: SnapUser?) -> some View {
        VStack(spacing: 0) {
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
            .padding(.bottom, 12)

            HStack(spacing: 32) {
                Button { showFollowersList = true } label: {
                    VStack(spacing: 2) {
                        Text("\(followerCount)")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Followers")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                }
                .buttonStyle(.plain)

                Button { showFollowingList = true } label: {
                    VStack(spacing: 2) {
                        Text("\(followingCount)")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Color.snapsheBlack)
                        Text("Following")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#888"))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)

            Button {
                Task { await toggleFollow() }
            } label: {
                HStack(spacing: 6) {
                    if isFollowLoading {
                        ProgressView().tint(isFollowing ? Color.snapsheBlack : .white).scaleEffect(0.8)
                    } else {
                        Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .frame(minWidth: 140)
                .padding(.horizontal, 28)
                .padding(.vertical, 11)
                .background(isFollowing ? Color(hex: "#F2F2F2") : Color.snapshePurple)
                .foregroundStyle(isFollowing ? Color.snapsheBlack : .white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isFollowing ? Color(hex: "#DDD") : Color.clear, lineWidth: 1))
            }
            .disabled(isFollowLoading)
            .padding(.bottom, 20)
        }
    }

    func toggleFollow() async {
        isFollowLoading = true
        do {
            let result: FollowResponse
            if isFollowing {
                result = try await APIService.shared.unfollowUser(username: username, token: auth.token)
            } else {
                result = try await APIService.shared.followUser(username: username, token: auth.token)
            }
            if result.ok {
                isFollowing = result.following ?? !isFollowing
                if let count = result.followerCount { followerCount = count }
            }
        } catch {}
        isFollowLoading = false
    }

    func loadProfile() async {
        isLoading = true
        do {
            let r = try await APIService.shared.fetchProfile(username: username, token: auth.token)
            if r.ok {
                profileUser = r.user
                uploads = r.uploads ?? []
                isFollowing = r.isFollowing ?? false
                followerCount = r.followerCount ?? 0
                followingCount = r.followingCount ?? 0
            } else {
                error = r.error ?? "Could not load profile."
            }
        } catch {
            self.error = "Network error."
        }
        isLoading = false
    }
}

// MARK: - Follow List View

enum FollowListType {
    case followers, following
    var title: String { self == .followers ? "Followers" : "Following" }
}

struct FollowListView: View {
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss

    let username: String
    let listType: FollowListType

    @State private var users: [SnapUser] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack { Spacer(); ProgressView().tint(Color.snapshePurple); Spacer() }
                } else if users.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: listType == .followers ? "person.2" : "person.badge.plus")
                            .font(.system(size: 44)).foregroundStyle(Color(hex: "#DDD"))
                        Text(listType == .followers ? "No followers yet" : "Not following anyone yet")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(Color(hex: "#AAA"))
                        Spacer()
                    }
                } else {
                    List(users) { user in FollowUserRow(user: user) }
                        .listStyle(.plain)
                }
            }
            .navigationTitle(listType.title)
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
        .task { await loadList() }
    }

    func loadList() async {
        isLoading = true
        let result: UserSearchResponse?
        if listType == .followers {
            result = try? await APIService.shared.fetchFollowers(username: username, token: auth.token)
        } else {
            result = try? await APIService.shared.fetchFollowing(username: username, token: auth.token)
        }
        users = result?.users ?? []
        isLoading = false
    }
}

struct FollowUserRow: View {
    @EnvironmentObject var auth: AuthManager
    let user: SnapUser
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 14) {
                AvatarCircle(user: user, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(user.displayName)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.snapsheBlack)
                    Text("@\(user.username)")
                        .font(.system(size: 13)).foregroundStyle(Color(hex: "#888"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13)).foregroundStyle(Color(hex: "#CCC"))
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            PublicProfileView(username: user.username).environmentObject(auth)
        }
    }
}

struct ProfilePhotoTile: View {
    let photo: FeedItem

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: photo.coverURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Color.snapsheGray.overlay(
                            Image(systemName: photo.mediaType == .video ? "video.slash" : "photo")
                                .foregroundStyle(.tertiary)
                        )
                    default:
                        Color.snapsheGray.shimmering()
                    }
                }
                .frame(width: size, height: size).clipped()

                if photo.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(6).background(Color.snapshePurple.opacity(0.9))
                        .clipShape(Circle()).padding(6)
                }
            }
            .frame(width: size, height: size).contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit).clipped()
    }
}
