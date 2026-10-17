import Foundation
import SwiftUI
import Security
import UIKit

struct CommunityConfiguration: Decodable {
    let communityAPIBaseURL: URL?
    static var apiBaseURL: URL? {
        guard let file = Bundle.main.url(forResource: "NatureRelayConfig", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let configuration = try? JSONDecoder().decode(Self.self, from: data),
              let url = validBaseURL(configuration.communityAPIBaseURL) else { return nil }
        return url
    }
    static func validBaseURL(_ url: URL?) -> URL? {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
}

struct CommunityUser: Codable, Identifiable, Hashable {
    let id: String
    var nickname: String
    var isFollowing: Bool?
}

struct CommunityPost: Codable, Identifiable, Hashable {
    let id: String
    var author: CommunityUser
    var clientObservationID: String?
    var name: String
    var kind: NatureKind
    var commonName: String?
    var scientificName: String?
    var note: String
    var locality: String
    var latitude: Double?
    var longitude: Double?
    var observedAt: Date
    var createdAt: Date
    var imageURL: String?
    var sourcePhotoURL: String?
    var sourceURL: String?
    var sourceAuthor: String?
    var sourceAttribution: String?
    var isReference: Bool
    var commentCount: Int
    var isFollowing: Bool
    var moderationStatus: String?

    var displayName: String { commonName?.isEmpty == false ? commonName! : name }
    var displayImageURL: String? { imageURL ?? sourcePhotoURL }
    var isPendingModeration: Bool { moderationStatus == "pending" }

    enum CodingKeys: String, CodingKey {
        case id, author, clientObservationID, name, kind, commonName, scientificName, note, locality
        case latitude, longitude, observedAt, createdAt, imageURL, sourcePhotoURL, sourceURL
        case sourceAuthor, sourceAttribution, isReference, commentCount, isFollowing, moderationStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        author = try c.decode(CommunityUser.self, forKey: .author)
        clientObservationID = try c.decodeIfPresent(String.self, forKey: .clientObservationID)
        name = try c.decode(String.self, forKey: .name)
        kind = (try? c.decode(NatureKind.self, forKey: .kind)) ?? .other
        commonName = try c.decodeIfPresent(String.self, forKey: .commonName)
        scientificName = try c.decodeIfPresent(String.self, forKey: .scientificName)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        locality = try c.decodeIfPresent(String.self, forKey: .locality) ?? "Location private"
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        observedAt = try c.decode(Date.self, forKey: .observedAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        sourcePhotoURL = try c.decodeIfPresent(String.self, forKey: .sourcePhotoURL)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceAuthor = try c.decodeIfPresent(String.self, forKey: .sourceAuthor)
        sourceAttribution = try c.decodeIfPresent(String.self, forKey: .sourceAttribution)
        isReference = try c.decodeIfPresent(Bool.self, forKey: .isReference) ?? false
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        isFollowing = try c.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? false
        moderationStatus = try c.decodeIfPresent(String.self, forKey: .moderationStatus)
    }
}

struct CommunityComment: Codable, Identifiable, Hashable {
    let id: String
    let postID: String
    let author: CommunityUser
    let text: String
    let createdAt: Date
    var moderationStatus: String?
    var isPendingModeration: Bool { moderationStatus == "pending" }
}

enum CommunityReportTarget: String, Encodable {
    case post, comment, user
    var label: String {
        switch self {
        case .post: return "dispatch"
        case .comment: return "comment"
        case .user: return "observer"
        }
    }
}

enum CommunityReportReason: String, CaseIterable, Encodable {
    case inappropriate, harassment, spam, privacy, other
    var label: String {
        switch self {
        case .inappropriate: return "Inappropriate content"
        case .harassment: return "Harassment or abuse"
        case .spam: return "Spam"
        case .privacy: return "Privacy concern"
        case .other: return "Other concern"
        }
    }
}

enum CommunityPolicy {
    static let privacyURL = URL(string: "https://nature-relay-community.midori-lab.workers.dev/privacy")!
    static let supportURL = URL(string: "https://nature-relay-community.midori-lab.workers.dev/support")!
    static let standardsURL = URL(string: "https://nature-relay-community.midori-lab.workers.dev/community")!
}

struct CommunityPublishRequest: Encodable {
    let clientObservationID: String
    let name: String
    let kind: NatureKind
    let commonName: String?
    let scientificName: String?
    let note: String
    let locality: String
    let latitude: Double?
    let longitude: Double?
    let observedAt: Date
    let imageBase64: String?
    let sourceURL: String?
    let sourcePhotoURL: String?
    let sourceAuthor: String?
    let sourceAttribution: String?
    let isReference: Bool
}

enum CommunityReference {
    static let restrictionMessage = "This reference is saved in your private journal with its source and credit. Public reference sharing requires both a supported iNaturalist observation link and photo link. This reference cannot be republished to the community."

    static func isReference(_ observation: NatureObservation) -> Bool {
        observation.isCommunity || observation.isSourceArchive == true || observation.sourcePhotoURL != nil || observation.sourceAttribution != nil || observation.sharedPostID != nil
    }

    static func isSupported(_ observation: NatureObservation) -> Bool {
        isSupported(sourceURL: observation.sourceURL, photoURL: observation.sourcePhotoURL, author: observation.author, attribution: observation.sourceAttribution)
    }

    static func isSupported(sourceURL: String?, photoURL: String?, author: String?, attribution: String?) -> Bool {
        guard validURL(sourceURL, photo: false), validURL(photoURL, photo: true),
              let author, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, author.count <= 120,
              let attribution, !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, attribution.count <= 1000 else { return false }
        return true
    }

    private static func validURL(_ value: String?, photo: Bool) -> Bool {
        guard let value, value.count <= 1000, let url = URLComponents(string: value),
              url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return false }
        if photo {
            let hosts = ["inaturalist-open-data.s3.amazonaws.com", "static.inaturalist.org", "static.inaturalist.org.s3.amazonaws.com"]
            return hosts.contains(host) && url.percentEncodedPath.range(of: "^/photos/[0-9]+/(small|medium|large|original|square)\\.(jpe?g|png)$", options: [.regularExpression, .caseInsensitive]) != nil
        }
        return ["www.inaturalist.org", "inaturalist.org"].contains(host) && url.percentEncodedPath.range(of: "^/observations/[0-9]+/?$", options: .regularExpression) != nil
    }
}

enum CommunityError: LocalizedError {
    case notConfigured, invalidResponse, sessionUnavailable, imageUnavailable, imageTooLarge, unavailableItem
    case server(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Community sharing is not connected yet. Your private journal is available."
        case .invalidResponse: return "The community service returned an unreadable response. Please try again."
        case .sessionUnavailable: return "Your device identity could not be saved securely. Please try again."
        case .imageUnavailable: return "The original photo could not be opened. Your discovery has not been published."
        case .imageTooLarge: return "This photo could not be prepared for sharing. Please choose another photo."
        case .unavailableItem: return "This community item is no longer available."
        case .server(let message): return message
        }
    }
}

struct CommunityCredential: Codable {
    let token: String
    var user: CommunityUser
}

@MainActor
protocol CommunitySessionStorage {
    func read(scope: String) -> CommunityCredential?
    func save(_ credential: CommunityCredential, scope: String) throws
    func remove(scope: String) throws
}

extension CommunitySessionStorage {
    // Existing injected stores remain source-compatible; deletion requires a store that can remove credentials.
    func remove(scope: String) throws { throw CommunityError.sessionUnavailable }
}

private struct CommunityKeychain: CommunitySessionStorage {
    private func query(scope: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.tomoki.naturerelay.community",
         kSecAttrAccount as String: "anonymous-session-v2|\(scope)",
         kSecAttrSynchronizable as String: false]
    }
    func read(scope: String) -> CommunityCredential? {
        var q = query(scope: scope)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CommunityCredential.self, from: data)
    }
    func save(_ credential: CommunityCredential, scope: String) throws {
        let data = try JSONEncoder().encode(credential)
        let changes: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query(scope: scope) as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(scope: scope)
            changes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CommunityError.sessionUnavailable }
        } else if status != errSecSuccess { throw CommunityError.sessionUnavailable }
    }
    func remove(scope: String) throws {
        let status = SecItemDelete(query(scope: scope) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CommunityError.sessionUnavailable }
    }
}

@MainActor
final class SocialAPIService {
    typealias RequestSender = (URLRequest) async throws -> (Data, URLResponse)
    private let baseURL: URL?
    private let sendRequest: RequestSender
    private let storage: CommunitySessionStorage
    private let credentialScope: String
    private var credential: CommunityCredential?
    private var sessionCreationTask: Task<CommunityUser, Error>?
    private var sessionCreationID: UUID?
    private var identityRevision = 0
    private var isDeletingIdentity = false
    var currentUser: CommunityUser? { credential?.user }
    var isConfigured: Bool { baseURL != nil }
    // The identification service can reuse the device identity without persisting a second token.
    var bearerToken: String? { credential?.token }

    convenience init(baseURL: URL? = CommunityConfiguration.apiBaseURL, session: URLSession = .shared) {
        self.init(baseURL: baseURL, sendRequest: { request in try await session.data(for: request) })
    }
    init(baseURL: URL?, storage: CommunitySessionStorage? = nil, sendRequest: @escaping RequestSender) {
        self.baseURL = CommunityConfiguration.validBaseURL(baseURL)
        self.storage = storage ?? CommunityKeychain()
        credentialScope = self.baseURL?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "unconfigured"
        self.sendRequest = sendRequest
        credential = self.baseURL == nil ? nil : self.storage.read(scope: credentialScope)
    }

    private struct SessionResponse: Decodable { let token: String; let user: CommunityUser }
    private struct UserResponse: Decodable { let user: CommunityUser }
    private struct PostsResponse: Decodable { let posts: [CommunityPost] }
    private struct PostResponse: Decodable { let post: CommunityPost }
    private struct CommentsResponse: Decodable { let comments: [CommunityComment] }
    private struct CommentResponse: Decodable { let comment: CommunityComment }
    private struct UsersResponse: Decodable { let users: [CommunityUser] }
    private struct FollowResponse: Decodable { let following: Bool }
    private struct DeleteResponse: Decodable { let deleted: Bool }
    private struct BlockResponse: Decodable { let blocked: Bool }
    private struct ReportResponse: Decodable { let received: Bool }
    private struct ServerError: Decodable { let error: String }
    private struct NicknameRequest: Encodable { let nickname: String }
    private struct CommentRequest: Encodable { let text: String }
    private struct ReportRequest: Encodable { let targetType: CommunityReportTarget; let targetID: String; let reason: CommunityReportReason }
    private struct AccountDeletionRequest: Encodable { let confirmation: String }

    func ensureSession(nickname: String = "Tomoki") async throws -> CommunityUser {
        guard !isDeletingIdentity else { throw CancellationError() }
        if let user = currentUser { return user }
        if let sessionCreationTask { return try await sessionCreationTask.value }
        let revision = identityRevision
        let creationID = UUID()
        let task = Task { @MainActor in
            let response: SessionResponse = try await self.send("v1/session", method: "POST", body: NicknameRequest(nickname: nickname))
            guard !Task.isCancelled, revision == self.identityRevision, !self.isDeletingIdentity else { throw CancellationError() }
            guard !response.token.isEmpty, response.token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw CommunityError.invalidResponse }
            let saved = CommunityCredential(token: response.token, user: response.user)
            try self.storage.save(saved, scope: self.credentialScope)
            self.credential = saved
            return response.user
        }
        sessionCreationTask = task
        sessionCreationID = creationID
        defer {
            if sessionCreationID == creationID { sessionCreationTask = nil; sessionCreationID = nil }
        }
        return try await task.value
    }

    func updateNickname(_ nickname: String) async throws -> CommunityUser {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw CommunityError.server("Choose a nickname between 1 and 40 characters.") }
        let user = try await ensureSession(nickname: name)
        guard user.nickname != name else { return user }
        let response: UserResponse = try await send("v1/me", method: "PATCH", body: NicknameRequest(nickname: name))
        guard var saved = credential else { throw CommunityError.sessionUnavailable }
        saved.user = response.user
        try storage.save(saved, scope: credentialScope)
        credential = saved
        return response.user
    }

    func fetchPosts(followingOnly: Bool = false) async throws -> [CommunityPost] {
        let response: PostsResponse = try await send("v1/posts", query: followingOnly ? [URLQueryItem(name: "following", value: "1")] : [])
        return response.posts
    }
    func publish(_ payload: CommunityPublishRequest) async throws -> CommunityPost {
        if payload.isReference {
            guard payload.imageBase64 == nil, CommunityReference.isSupported(sourceURL: payload.sourceURL, photoURL: payload.sourcePhotoURL, author: payload.sourceAuthor, attribution: payload.sourceAttribution) else {
                throw CommunityError.server(CommunityReference.restrictionMessage)
            }
        } else if payload.sourceURL != nil || payload.sourcePhotoURL != nil || payload.sourceAuthor != nil || payload.sourceAttribution != nil {
            throw CommunityError.server(CommunityReference.restrictionMessage)
        }
        let response: PostResponse = try await send("v1/posts", method: "POST", body: payload)
        return response.post
    }
    func deletePost(id: String) async throws {
        let response: DeleteResponse = try await send("v1/posts/\(try checkedIdentifier(id))", method: "DELETE")
        guard response.deleted else { throw CommunityError.invalidResponse }
    }
    func comments(postID: String) async throws -> [CommunityComment] {
        let response: CommentsResponse = try await send("v1/posts/\(try checkedIdentifier(postID))/comments")
        return response.comments
    }
    func comment(postID: String, text: String) async throws -> CommunityComment {
        let response: CommentResponse = try await send("v1/posts/\(try checkedIdentifier(postID))/comments", method: "POST", body: CommentRequest(text: text))
        return response.comment
    }
    func setFollowing(_ following: Bool, userID: String) async throws -> Bool {
        let response: FollowResponse = try await send("v1/follows/\(try checkedIdentifier(userID))", method: following ? "POST" : "DELETE")
        return response.following
    }
    func users(query: String = "") async throws -> [CommunityUser] {
        let response: UsersResponse = try await send("v1/users", query: [URLQueryItem(name: "query", value: query)])
        return response.users
    }
    func blockedUsers() async throws -> [CommunityUser] {
        guard currentUser != nil else { return [] }
        let response: UsersResponse = try await send("v1/blocks")
        return response.users
    }
    func setBlocked(_ blocked: Bool, userID: String) async throws -> Bool {
        let identifier = try checkedIdentifier(userID)
        _ = try await ensureSession()
        let response: BlockResponse = try await send("v1/blocks/\(identifier)", method: blocked ? "POST" : "DELETE")
        guard response.blocked == blocked else { throw CommunityError.invalidResponse }
        return response.blocked
    }
    func report(target: CommunityReportTarget, id: String, reason: CommunityReportReason) async throws {
        let identifier = try checkedIdentifier(id)
        _ = try await ensureSession()
        let response: ReportResponse = try await send("v1/reports", method: "POST", body: ReportRequest(targetType: target, targetID: identifier, reason: reason))
        guard response.received else { throw CommunityError.invalidResponse }
    }
    func deleteAccount() async throws {
        guard credential != nil, !isDeletingIdentity else { throw CommunityError.sessionUnavailable }
        isDeletingIdentity = true
        identityRevision += 1
        sessionCreationTask?.cancel()
        sessionCreationTask = nil
        sessionCreationID = nil
        defer { isDeletingIdentity = false }
        let response: DeleteResponse = try await send("v1/me", method: "DELETE", body: AccountDeletionRequest(confirmation: "DELETE"))
        guard response.deleted else { throw CommunityError.invalidResponse }
        // Never reuse a remotely deleted identity, even if the local Keychain operation fails.
        credential = nil
        do { try storage.remove(scope: credentialScope) }
        catch { throw CommunityError.server("Your community profile was deleted, but this iPhone could not clear its saved sign-in. Contact support for help.") }
    }

    private func checkedIdentifier(_ id: String) throws -> String {
        guard UUID(uuidString: id) != nil else { throw CommunityError.server("This community record has an invalid identifier.") }
        return id
    }

    private func send<Response: Decodable>(_ path: String, method: String = "GET", query: [URLQueryItem] = []) async throws -> Response {
        try await perform(path, method: method, query: query, body: nil)
    }
    private func send<Response: Decodable, Body: Encodable>(_ path: String, method: String, body: Body) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await perform(path, method: method, query: [], body: encoder.encode(body))
    }
    private func perform<Response: Decodable>(_ path: String, method: String, query: [URLQueryItem], body: Data?) async throws -> Response {
        guard !Task.isCancelled, !isDeletingIdentity || (path == "v1/me" && method == "DELETE") else { throw CancellationError() }
        let revision = identityRevision
        guard let baseURL else { throw CommunityError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CommunityError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 35
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token = credential?.token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await sendRequest(request) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        guard !Task.isCancelled, revision == identityRevision else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw CommunityError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw CommunityError.unavailableItem }
            if let error = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw CommunityError.server(error.error)
            }
            if http.statusCode == 401 { throw CommunityError.server("Your device session could not be verified. Your private journal remains saved.") }
            if http.statusCode == 429 { throw CommunityError.server("The free community service is busy. Please try again shortly.") }
            throw CommunityError.server("Community sharing is unavailable (\(http.statusCode)). Please try again.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid observation date")
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw CommunityError.invalidResponse }
    }
}

@MainActor
final class CommunityStore: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var followingPosts: [CommunityPost] = []
    @Published private(set) var user: CommunityUser?
    @Published private(set) var isLoading = false
    @Published private(set) var isPublishing = false
    @Published private(set) var blockedUsers: [CommunityUser] = []
    @Published private(set) var isDeletingAccount = false
    @Published var error: String?
    let api: SocialAPIService
    var isConfigured: Bool { api.isConfigured }
    private var contentRevision = 0

    func isBlocked(_ userID: String) -> Bool { blockedUsers.contains { $0.id == userID } }

    init(api: SocialAPIService? = nil) {
        self.api = api ?? SocialAPIService()
        user = self.api.currentUser
    }

    func refresh(followingOnly: Bool = false) async {
        guard !isLoading else { return }
        if followingOnly && user == nil { followingPosts = []; return }
        isLoading = true
        let revision = contentRevision
        defer { isLoading = false }
        do {
            let fetched = try await api.fetchPosts(followingOnly: followingOnly)
            guard revision == contentRevision else { return }
            if followingOnly { followingPosts = fetched.filter { !isBlocked($0.author.id) } }
            else { posts = fetched.filter { !isBlocked($0.author.id) } }
            error = nil
        }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    func updateNickname(_ nickname: String) async throws {
        let updated = try await api.updateNickname(nickname)
        guard !isDeletingAccount, api.currentUser?.id == updated.id else { throw CancellationError() }
        user = updated
        if let user {
            for index in posts.indices where posts[index].author.id == user.id { posts[index].author.nickname = user.nickname }
        }
    }

    @discardableResult
    func ensureSession(nickname: String = "Tomoki") async throws -> CommunityUser {
        let user = try await api.ensureSession(nickname: nickname)
        guard !isDeletingAccount, api.currentUser?.id == user.id else { throw CancellationError() }
        self.user = user
        return user
    }

    @discardableResult
    func publish(observation: NatureObservation, name: String, note: String, locality: String, shareLocation: Bool, nickname: String) async throws -> CommunityPost {
        guard !isPublishing else { throw CommunityError.server("Your discovery is already being published.") }
        isPublishing = true
        defer { isPublishing = false }
        let reference = CommunityReference.isReference(observation)
        guard !observation.isSample else { throw CommunityError.server("Demo discoveries cannot be published.") }
        guard !reference || CommunityReference.isSupported(observation) else { throw CommunityError.server(CommunityReference.restrictionMessage) }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = locality.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120, note.count <= 2000, !place.isEmpty, place.count <= 120 else {
            throw CommunityError.server("Add a discovery name and a city or area. Keep the note under 2,000 characters.")
        }
        var image: String?
        if !reference {
            guard let file = observation.originalImageName, let photo = CommunityPhoto.loadOriginal(file) else { throw CommunityError.imageUnavailable }
            image = try CommunityPhoto.prepare(photo).base64EncodedString()
        }
        try await updateNickname(nickname)
        let latitude = shareLocation ? (observation.latitude * 100).rounded() / 100 : nil
        let longitude = shareLocation ? (observation.longitude * 100).rounded() / 100 : nil
        let request = CommunityPublishRequest(clientObservationID: observation.id.uuidString,
            name: title, kind: observation.kind, commonName: observation.commonName, scientificName: observation.scientificName,
            note: note, locality: place, latitude: latitude, longitude: longitude, observedAt: observation.observedAt,
            imageBase64: image, sourceURL: reference ? observation.sourceURL : nil,
            sourcePhotoURL: reference ? observation.sourcePhotoURL : nil, sourceAuthor: reference ? observation.author : nil,
            sourceAttribution: reference ? observation.sourceAttribution : nil, isReference: reference)
        let post = try await api.publish(request)
        posts.removeAll { $0.id == post.id }
        posts.insert(post, at: 0)
        return post
    }

    func comment(postID: String, text: String, nickname: String) async throws -> CommunityComment {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1000 else { throw CommunityError.server("Write a comment of 1 to 1,000 characters.") }
        try await updateNickname(nickname)
        let comment = try await api.comment(postID: postID, text: text)
        if let index = posts.firstIndex(where: { $0.id == postID }) { posts[index].commentCount += 1 }
        return comment
    }

    func deletePost(_ post: CommunityPost) async throws {
        guard post.author.id == user?.id else { throw CommunityError.server("Only the author can delete this dispatch.") }
        try await api.deletePost(id: post.id)
        posts.removeAll { $0.id == post.id }
        followingPosts.removeAll { $0.id == post.id }
    }

    func refreshBlockedUsers() async throws {
        let revision = contentRevision
        let fetched = try await api.blockedUsers()
        guard revision == contentRevision else { return }
        blockedUsers = fetched
        posts.removeAll { isBlocked($0.author.id) }
        followingPosts.removeAll { isBlocked($0.author.id) }
    }

    func setBlocked(_ blocked: Bool, user target: CommunityUser) async throws {
        guard !isDeletingAccount else { throw CancellationError() }
        guard target.id != user?.id else { throw CommunityError.server("You cannot block your own profile.") }
        let activeUser = try await ensureSession()
        _ = try await api.setBlocked(blocked, userID: target.id)
        guard !isDeletingAccount, api.currentUser?.id == activeUser.id, user?.id == activeUser.id else { throw CancellationError() }
        contentRevision += 1
        blockedUsers.removeAll { $0.id == target.id }
        if blocked { blockedUsers.append(target) }
        posts.removeAll { isBlocked($0.author.id) }
        followingPosts.removeAll { isBlocked($0.author.id) }
        await refreshAfterCommunityChange()
    }

    private func refreshAfterCommunityChange() async {
        let revision = contentRevision
        do {
            let fetched = try await api.fetchPosts()
            guard revision == contentRevision else { return }
            posts = fetched.filter { !isBlocked($0.author.id) }
            if user != nil {
                let following = try await api.fetchPosts(followingOnly: true)
                guard revision == contentRevision else { return }
                followingPosts = following.filter { !isBlocked($0.author.id) }
            }
            error = nil
        }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    func report(target: CommunityReportTarget, id: String, reason: CommunityReportReason) async throws {
        try await api.report(target: target, id: id, reason: reason)
        user = api.currentUser
    }

    func deleteAccount() async throws {
        guard !isDeletingAccount, !isPublishing else { throw CommunityError.server("Please wait for the current community action to finish.") }
        isDeletingAccount = true
        contentRevision += 1
        defer { isDeletingAccount = false }
        do { try await api.deleteAccount() }
        catch {
            if api.currentUser == nil { clearCommunityState() }
            throw error
        }
        clearCommunityState()
    }

    private func clearCommunityState() {
        user = nil
        blockedUsers = []
        posts = []
        followingPosts = []
        error = nil
    }

    @discardableResult
    func toggleFollow(_ target: CommunityUser) async throws -> Bool {
        let activeUser = try await ensureSession()
        guard target.id != user?.id else { return false }
        let current = posts.first(where: { $0.author.id == target.id })?.isFollowing ?? target.isFollowing ?? false
        let following = try await api.setFollowing(!current, userID: target.id)
        guard !isDeletingAccount, api.currentUser?.id == activeUser.id, user?.id == activeUser.id else { throw CancellationError() }
        for index in posts.indices where posts[index].author.id == target.id {
            posts[index].isFollowing = following
            posts[index].author.isFollowing = following
        }
        followingPosts.removeAll { $0.author.id == target.id }
        if following { followingPosts.append(contentsOf: posts.filter { $0.author.id == target.id }) }
        followingPosts.sort { $0.createdAt > $1.createdAt }
        return following
    }
}

enum CommunityPhoto {
    static let maximumBytes = 128_000
    static func loadOriginal(_ name: String) -> UIImage? {
        guard name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NatureRelayMedia", isDirectory: true)
        return UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }
    // Drawing into a new bitmap removes the original photo's EXIF, GPS and filename metadata.
    static func prepare(_ image: UIImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else { throw CommunityError.imageUnavailable }
        var longestSide: CGFloat = min(1024, max(image.size.width, image.size.height))
        while longestSide >= 96 {
            let scale = longestSide / max(image.size.width, image.size.height)
            let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let flattened = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in [0.76, 0.60, 0.44, 0.28] as [CGFloat] {
                if let data = flattened.jpegData(compressionQuality: quality), data.count <= maximumBytes { return data }
            }
            longestSide *= 0.72
        }
        throw CommunityError.imageTooLarge
    }
}
