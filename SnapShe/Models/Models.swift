import Foundation

// MARK: - User
struct SnapUser: Codable, Identifiable {
    let id: String
    var name: String
    var username: String
    var email: String
    var avatar: String?
    
    var displayName: String { name.isEmpty ? username : name }
    var avatarLetter: String { String(displayName.prefix(1)).uppercased() }
    var avatarURL: URL? {
        guard let avatar = avatar, !avatar.isEmpty else { return nil }
        if avatar.hasPrefix("http") { return URL(string: avatar) }
        return URL(string: "\(APIService.baseURL)/\(avatar)")
    }
}

struct LoginResponse: Codable {
    let ok: Bool; let user: SnapUser?; let token: String?; let error: String?
}
struct RegisterResponse: Codable {
    let ok: Bool; let user: SnapUser?; let token: String?; let error: String?
}

struct Product: Codable, Identifiable {
    let title: String
    let source: String
    let price: String
    let thumbnail: String
    let image: String
    let link: String
    var id: String { link }
    var thumbnailURL: URL? { URL(string: thumbnail) }
    var productURL: URL? { URL(string: link) }
}

struct VisualSearchResponse: Codable {
    let ok: Bool
    let imageUrl: String?
    let count: Int?
    let products: [Product]?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case ok; case imageUrl = "image_url"; case count; case products; case error
    }
}

struct SnapCollection: Codable, Identifiable {
    let id: String
    var title: String
    var products: [SavedProduct]
    var userId: String?
    enum CodingKeys: String, CodingKey {
        case id, title, products; case userId = "user_id"
    }
}

struct SavedProduct: Codable, Identifiable {
    let title: String
    let price: String
    let image: String
    let link: String
    let source: String
    var id: String { link }
    var imageURL: URL? { URL(string: image) }
    var productURL: URL? { URL(string: link) }
}

// MARK: - Feed Item (photo or video)
enum FeedMediaType: String, Codable {
    case photo
    case video
}

struct FeedItem: Codable, Identifiable {
    let id: String
    let username: String
    let name: String
    // photo fields
    var image: String?
    // video fields
    var video: String?
    var thumbnail: String?
    let filename: String
    let createdAt: String
    var type: FeedMediaType?

    var mediaType: FeedMediaType { type ?? (video != nil && !(video?.isEmpty ?? true) ? .video : .photo) }

    /// URL to show as thumbnail in the feed grid
    var coverURL: URL? {
        if mediaType == .video {
            // prefer explicit thumbnail, else nil (show video icon placeholder)
            if let t = thumbnail, !t.isEmpty { return URL(string: "\(APIService.baseURL)/\(t)") }
            return nil
        }
        guard let img = image, !img.isEmpty else { return nil }
        return URL(string: "\(APIService.baseURL)/\(img)")
    }

    /// URL for the actual media (video file or photo)
    var mediaURL: URL? {
        if mediaType == .video {
            guard let v = video, !v.isEmpty else { return nil }
            return URL(string: "\(APIService.baseURL)/\(v)")
        }
        guard let img = image, !img.isEmpty else { return nil }
        return URL(string: "\(APIService.baseURL)/\(img)")
    }

    enum CodingKeys: String, CodingKey {
        case id, username, name, image, video, thumbnail, filename, type
        case createdAt = "created_at"
    }
}

// Backward-compat typealias so existing code that uses FeedPhoto still compiles
typealias FeedPhoto = FeedItem

struct FeedResponse: Codable {
    let ok: Bool
    let photos: [FeedItem]?
    let error: String?
}
struct CollectionsResponse: Codable {
    let ok: Bool; let collections: [SnapCollection]?; let error: String?
}
struct GenericResponse: Codable {
    let ok: Bool; let error: String?; let id: String?; let collection: SnapCollection?
    let avatar: String?
}

// Token-bearing auth responses
struct LoginResponseWithToken: Codable {
    let ok: Bool; let user: SnapUser?; let token: String?; let error: String?
}
struct RegisterResponseWithToken: Codable {
    let ok: Bool; let user: SnapUser?; let token: String?; let error: String?
}

// MARK: - User Search
struct UserSearchResponse: Codable {
    let ok: Bool
    let users: [SnapUser]?
    let error: String?
}

// MARK: - Profile Response
struct ProfileResponse: Codable {
    let ok: Bool
    let user: SnapUser?
    let uploads: [FeedItem]?
    let isOwn: Bool?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case ok, user, uploads, error
        case isOwn = "is_own"
    }
}

// MARK: - Video Upload Response
struct VideoUploadResponse: Codable {
    let ok: Bool
    let path: String?
    let filename: String?
    let thumbnail: String?
    let id: String?
    let error: String?
}

// MARK: - Instagram Fetch Response
struct InstagramFetchResponse: Codable {
    let ok: Bool
    let type: String?
    let imageUrl: String?
    let videoUrl: String?
    let uploadId: String?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case ok, type, error
        case imageUrl  = "image_url"
        case videoUrl  = "video_url"
        case uploadId  = "upload_id"
    }
}

// MARK: - Instagram Fetch Error
struct InstagramFetchError: Error {
    let message: String
}

// MARK: - IdentifiableString (sheet binding helper)
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}
