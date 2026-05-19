import Foundation
import UIKit

class APIService {
    static let shared = APIService()
    static let baseURL = "https://snapshe.com"  // ← kendi domain'in

    // VigLink affiliate redirect
    private static let vigLinkKey = "56f53588b18da5199d57ebb9da80688f"

    static func affiliateURL(for productLink: String) -> URL? {
        guard !productLink.isEmpty else { return nil }
        let encoded = productLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? productLink
        return URL(string: "https://redirect.viglink.com/?key=\(vigLinkKey)&u=\(encoded)")
    }

    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60  // video upload için artırıldı
        session = URLSession(configuration: cfg)
    }

    // MARK: - Auth
    func login(login: String, password: String) async throws -> LoginResponse {
        var req = post("\(Self.baseURL)/api_mobile/auth.php")
        req.httpBody = "action=login&login=\(login.urlEnc)&password=\(password.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    func register(name: String, username: String, email: String, password: String) async throws -> LoginResponse {
        var req = post("\(Self.baseURL)/api_mobile/auth.php")
        req.httpBody = "action=register&name=\(name.urlEnc)&username=\(username.urlEnc)&email=\(email.urlEnc)&password=\(password.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    func logout(token: String) async throws {
        var req = post("\(Self.baseURL)/api_mobile/auth.php")
        req.setValue(token, forHTTPHeaderField: "X-App-Token")
        req.httpBody = "action=logout".data(using: .utf8)
        _ = try? await session.data(for: req)
    }

    // MARK: - Feed
    func fetchFeed(token: String) async throws -> FeedResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/feed.php", token: token))
    }

    // MARK: - User Search
    func searchUsers(query: String, token: String) async throws -> UserSearchResponse {
        let url = "\(Self.baseURL)/api_mobile/user-search.php?q=\(query.urlEnc)"
        return try await decode(get(url, token: token))
    }

    // MARK: - Profile
    func fetchProfile(username: String? = nil, token: String) async throws -> ProfileResponse {
        var url = "\(Self.baseURL)/api_mobile/profile.php"
        if let u = username, !u.isEmpty { url += "?username=\(u.urlEnc)" }
        return try await decode(get(url, token: token))
    }

    // MARK: - Visual Search (photo)
    func visualSearch(imageData: Data, imageURL: String?, crop: String?, keyword: String?, token: String) async throws -> VisualSearchResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/api_mobile/visual-search.php")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-App-Token")

        var body = Data()
        if let url = imageURL, !url.isEmpty {
            body.appendField(boundary: boundary, name: "image_url", value: url)
        } else {
            body.appendFile(boundary: boundary, name: "image", filename: "photo.jpg", mime: "image/jpeg", data: imageData)
        }
        if let crop = crop, !crop.isEmpty    { body.appendField(boundary: boundary, name: "crop", value: crop) }
        if let kw = keyword, !kw.isEmpty     { body.appendField(boundary: boundary, name: "q", value: kw) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await decode(req)
    }

    // MARK: - Visual Search (video frame — capture edilmiş JPEG gönderilir)
    func visualSearchVideoFrame(
        frameData: Data,
        videoPath: String?,
        crop: String?,
        keyword: String?,
        saveFeedEntry: Bool,
        token: String
    ) async throws -> VisualSearchResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/api_mobile/visual-search.php")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-App-Token")

        var body = Data()
        body.appendFile(boundary: boundary, name: "image", filename: "video-frame.jpg", mime: "image/jpeg", data: frameData)
        if let vp = videoPath, !vp.isEmpty  { body.appendField(boundary: boundary, name: "video_path", value: vp) }
        if saveFeedEntry                    { body.appendField(boundary: boundary, name: "video_feed_save", value: "1") }
        if let crop = crop, !crop.isEmpty  { body.appendField(boundary: boundary, name: "crop", value: crop) }
        if let kw = keyword, !kw.isEmpty   { body.appendField(boundary: boundary, name: "q", value: kw) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await decode(req)
    }

    // MARK: - Video Upload
    /// Videoyu sunucuya yükler ve sunucu path'i döner.
    func uploadVideo(videoData: Data, filename: String, thumbnailData: Data? = nil, token: String) async throws -> VideoUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/api_mobile/upload_video.php")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-App-Token")
        req.timeoutInterval = 120

        let ext = (filename as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "mp4":  mime = "video/mp4"
        case "mov":  mime = "video/quicktime"
        case "webm": mime = "video/webm"
        default:     mime = "video/mp4"
        }

        var body = Data()
        body.appendFile(boundary: boundary, name: "video", filename: filename, mime: mime, data: videoData)
        if let thumb = thumbnailData {
            body.appendFile(boundary: boundary, name: "thumbnail", filename: "thumb.jpg", mime: "image/jpeg", data: thumb)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await decode(req)
    }

    // MARK: - Instagram Fetch
    func instagramFetch(url: String, token: String) async throws -> InstagramFetchResponse {
        var req = post("\(Self.baseURL)/instagram-fetch.php", token: token)
        req.httpBody = "url=\(url.urlEnc)".data(using: .utf8)
        req.timeoutInterval = 60
        let (data, _) = try await session.data(for: req)
        let decoded = try JSONDecoder().decode(InstagramFetchResponse.self, from: data)
        if !decoded.ok {
            throw InstagramFetchError(message: decoded.error ?? "Could not retrieve media.")
        }
        return decoded
    }

    // MARK: - Collections
    func fetchCollections(token: String) async throws -> CollectionsResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/collections.php", token: token))
    }
    func createCollection(title: String, token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/create-collection.php", token: token)
        req.httpBody = "title=\(title.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }
    func saveProduct(collectionId: String, product: Product, token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/save-product.php", token: token)
        req.httpBody = "collection_id=\(collectionId.urlEnc)&title=\(product.title.urlEnc)&price=\(product.price.urlEnc)&image=\(product.image.urlEnc)&link=\(product.link.urlEnc)&source=\(product.source.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    // MARK: - Profile management
    func uploadAvatar(imageData: Data, token: String) async throws -> GenericResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/api_mobile/upload-avatar.php")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-App-Token")
        var body = Data()
        body.appendFile(boundary: boundary, name: "avatar", filename: "avatar.jpg", mime: "image/jpeg", data: imageData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try await decode(req)
    }
    func updateProfile(name: String, username: String, token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/update-profile.php", token: token)
        req.httpBody = "name=\(name.urlEnc)&username=\(username.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }
    func deleteAccount(token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/delete-account.php", token: token)
        req.httpBody = "confirm=1".data(using: .utf8)
        return try await decode(req)
    }

    // MARK: - Following Feed
    func fetchFollowingFeed(token: String) async throws -> FollowingFeedResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/following-feed.php", token: token))
    }

    // MARK: - Follow / Unfollow
    func followUser(username: String, token: String) async throws -> FollowResponse {
        var req = post("\(Self.baseURL)/api_mobile/follow.php", token: token)
        req.httpBody = "action=follow&username=\(username.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    func unfollowUser(username: String, token: String) async throws -> FollowResponse {
        var req = post("\(Self.baseURL)/api_mobile/follow.php", token: token)
        req.httpBody = "action=unfollow&username=\(username.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    func fetchFollowers(username: String, token: String) async throws -> UserSearchResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/follow-list.php?type=followers&username=\(username.urlEnc)", token: token))
    }

    func fetchFollowing(username: String, token: String) async throws -> UserSearchResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/follow-list.php?type=following&username=\(username.urlEnc)", token: token))
    }

    // MARK: - Delete Upload
    func deleteUpload(uploadId: String, token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/delete-upload.php", token: token)
        req.httpBody = "upload_id=\(uploadId.urlEnc)".data(using: .utf8)
        return try await decode(req)
    }

    // MARK: - Notifications
    func fetchNotifications(token: String) async throws -> NotificationsResponse {
        return try await decode(get("\(Self.baseURL)/api_mobile/notifications.php", token: token))
    }

    func markNotificationsRead(token: String) async throws -> GenericResponse {
        var req = post("\(Self.baseURL)/api_mobile/notifications.php", token: token)
        req.httpBody = "action=mark_read".data(using: .utf8)
        return try await decode(req)
    }

    // MARK: - Private helpers
    private func post(_ urlStr: String, token: String? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if let t = token { req.setValue(t, forHTTPHeaderField: "X-App-Token") }
        return req
    }
    private func get(_ urlStr: String, token: String? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: urlStr)!)
        if let t = token { req.setValue(t, forHTTPHeaderField: "X-App-Token") }
        return req
    }
    private func decode<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Helpers
extension String {
    var urlEnc: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self }
}
extension Data {
    mutating func appendField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }
    mutating func appendFile(boundary: String, name: String, filename: String, mime: String, data: Data) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
