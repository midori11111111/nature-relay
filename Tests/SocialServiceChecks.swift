import Foundation
import UIKit
import ImageIO

@MainActor
private final class MemorySessionStorage: CommunitySessionStorage {
    var values: [String: CommunityCredential] = [:]
    var saveCount = 0
    var removeCount = 0
    func read(scope: String) -> CommunityCredential? { values[scope] }
    func save(_ credential: CommunityCredential, scope: String) throws {
        values[scope] = credential
        saveCount += 1
    }
    func remove(scope: String) throws {
        values.removeValue(forKey: scope)
        removeCount += 1
    }
}

private actor CommunityRequestRecorder {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}

private actor CommunityRequestGate {
    private var arrived = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var response: CheckedContinuation<Void, Never>?
    func hold() async {
        arrived = true
        arrivals.forEach { $0.resume() }
        arrivals = []
        await withCheckedContinuation { response = $0 }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func release() { response?.resume(); response = nil }
}

@main
struct SocialServiceChecks {
    private static let userID = "a0000000-0000-4000-8000-000000000001"
    private static let postID = "b0000000-0000-4000-8000-000000000001"
    private static let zeroPostID = "b0000000-0000-4000-8000-000000000002"
    private static let commentID = "c0000000-0000-4000-8000-000000000001"
    private static let fixtureToken = "fixture-only-not-a-real-session"

    @MainActor
    static func main() async throws {
        let base = URL(string: "https://community-contract.invalid")!
        let storage = MemorySessionStorage()
        let recorder = CommunityRequestRecorder()
        let service = SocialAPIService(baseURL: base, storage: storage) { request in
            await recorder.record(request)
            let url = request.url!
            var body: [String: Any] = [:]
            if let data = request.httpBody { body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
            let response: [String: Any]
            switch (url.path, request.httpMethod ?? "GET") {
            case ("/v1/session", "POST"):
                // A real suspension exposes duplicate-session races between simultaneous callers.
                try await Task.sleep(for: .milliseconds(35))
                response = ["token": fixtureToken, "user": ["id": userID, "nickname": body["nickname"] as? String ?? "Tester"]]
            case ("/v1/me", "PATCH"):
                response = ["user": ["id": userID, "nickname": body["nickname"] as? String ?? "Tester"]]
            case ("/v1/posts", "GET"):
                var zero = postFixture(id: zeroPostID)
                zero["latitude"] = 0
                zero["longitude"] = 0
                zero["isReference"] = true
                zero["sourceURL"] = "https://www.inaturalist.org/observations/123"
                zero["sourceAttribution"] = "Original observer · CC BY 4.0"
                var invalid = postFixture(id: "b0000000-0000-4000-8000-000000000003")
                invalid["latitude"] = 91
                invalid["longitude"] = 0
                response = ["posts": [postFixture(id: postID), zero, invalid]]
            case ("/v1/posts", "POST"):
                response = ["post": postFixture(id: postID)]
            case ("/v1/posts/\(postID)", "DELETE"):
                response = ["deleted": true]
            case ("/v1/posts/\(postID)/comments", "GET"):
                response = ["comments": [commentFixture]]
            case ("/v1/posts/\(postID)/comments", "POST"):
                var comment = commentFixture
                comment["text"] = body["text"] as? String ?? ""
                response = ["comment": comment]
            case ("/v1/follows/\(userID)", "POST"):
                response = ["following": true]
            case ("/v1/follows/\(userID)", "DELETE"):
                response = ["following": false]
            case ("/v1/users", "GET"):
                response = ["users": [["id": userID, "nickname": "Tester", "isFollowing": true]]]
            default:
                preconditionFailure("Unexpected fixture route")
            }
            let data = try JSONSerialization.data(withJSONObject: response)
            return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let posts = try await service.fetchPosts()
        precondition(posts.count == 3)
        precondition(posts[0].displayName == "California poppy")
        precondition(posts[0].commentCount == 0 && !posts[0].isFollowing && !posts[0].isReference)
        precondition(posts[0].observedAt < posts[0].createdAt)
        precondition(posts[0].mapObservation == nil, "Omitted coordinates must not create a map point at zero")
        let zero = posts[1].mapObservation!
        precondition(zero.latitude == 0 && zero.longitude == 0, "An explicitly shared point at zero is valid")
        precondition(zero.sharedPostID == zeroPostID)
        precondition(zero.coordinateAccuracyMeters! >= 1000)
        precondition(zero.isSourceArchive == true && zero.sourceAttribution == "Original observer · CC BY 4.0")
        precondition(zero.commonName == "California poppy" && zero.scientificName == "Eschscholzia californica")
        precondition(posts[2].mapObservation == nil, "Invalid latitude must never become a map annotation")
        let firstRequest = await recorder.requests.first!
        precondition(firstRequest.value(forHTTPHeaderField: "Authorization") == nil)

        async let firstIdentity = service.ensureSession(nickname: "Tester")
        async let secondIdentity = service.ensureSession(nickname: "Tester")
        let identities = try await [firstIdentity, secondIdentity]
        precondition(identities[0].id == identities[1].id)
        let sessionRequests = await recorder.requests.filter { $0.url?.path == "/v1/session" }
        precondition(sessionRequests.count == 1 && storage.saveCount == 1, "Concurrent callers must share one anonymous identity")
        precondition(service.currentUser?.id == userID)
        _ = try await service.fetchPosts(followingOnly: true)
        let authenticated = await recorder.requests.last!
        precondition(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixtureToken)")
        precondition(URLComponents(url: authenticated.url!, resolvingAgainstBaseURL: false)?.queryItems?.first == URLQueryItem(name: "following", value: "1"))
        precondition(authenticated.cachePolicy == .reloadIgnoringLocalCacheData)

        let restored = SocialAPIService(baseURL: base, storage: storage) { request in
            await recorder.record(request)
            return (try JSONSerialization.data(withJSONObject: ["posts": []]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        precondition(restored.currentUser?.id == userID)
        let separateBackend = SocialAPIService(baseURL: URL(string: "https://another-community-contract.invalid")!, storage: storage) { request in
            await recorder.record(request)
            return (try JSONSerialization.data(withJSONObject: ["posts": []]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        precondition(separateBackend.currentUser == nil, "A different backend must not receive this backend's device token")
        _ = try await separateBackend.fetchPosts()
        let unboundRequest = await recorder.requests.last!
        precondition(unboundRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let comment = try await service.comment(postID: postID, text: "A lovely flower.")
        precondition(comment.id == commentID && comment.text == "A lovely flower.")
        let comments = try await service.comments(postID: postID)
        let followed = try await service.setFollowing(true, userID: userID)
        let unfollowed = try await service.setFollowing(false, userID: userID)
        precondition(comments.count == 1 && followed && !unfollowed)
        let found = try await service.users(query: "Tester & friend")
        precondition(found.first?.isFollowing == true)
        let searchRequest = await recorder.requests.last!
        precondition(URLComponents(url: searchRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Tester & friend")

        let store = CommunityStore(api: service)
        var archive = NatureObservation(name: "Original poppy", kind: .flower, note: "Archive original note", author: "Original observer", latitude: 37.32123, longitude: -122.04567)
        archive.sourceURL = "https://www.inaturalist.org/observations/123"
        archive.sourcePhotoURL = "https://static.inaturalist.org/photos/123/medium.jpg"
        archive.sourceAttribution = "Original observer · CC BY 4.0"
        archive.commonName = "California poppy"
        archive.scientificName = "Eschscholzia californica"
        archive.isSourceArchive = true
        archive.originalImageName = "private-original-must-not-be-uploaded.jpg"
        let beforeUnsupportedReferences = await recorder.requests.count
        let unsupportedLinks: [(String?, String?)] = [
            ("https://unsplash.com/photos/reference", nil),
            (archive.sourceURL, nil),
            (archive.sourceURL, "https://example.com/photo.jpg"),
            ("https://www.inaturalist.org.evil.invalid/observations/123", archive.sourcePhotoURL),
            ("https://www.inaturalist.org/observations/%31%32%33", archive.sourcePhotoURL),
            (archive.sourceURL, "https://static.inaturalist.org/photos/123/medium.jpg?download=1"),
            (nil, archive.sourcePhotoURL),
        ]
        for (source, photo) in unsupportedLinks {
            var unsupported = archive
            unsupported.sourceURL = source
            unsupported.sourcePhotoURL = photo
            do {
                _ = try await store.publish(observation: unsupported, name: "Private reference", note: "", locality: "Cupertino", shareLocation: false, nickname: "Tester")
                preconditionFailure("Unsupported references must stay private")
            } catch CommunityError.server(let message) { precondition(message == CommunityReference.restrictionMessage) }
        }
        var photoOnly = archive
        photoOnly.sourceURL = nil
        photoOnly.sourcePhotoURL = "https://example.com/another-persons-photo.jpg"
        photoOnly.sourceAttribution = nil
        photoOnly.isSourceArchive = false
        precondition(CommunityReference.isReference(photoOnly), "A remote source photo must never become an own-photo upload")
        do {
            _ = try await store.publish(observation: photoOnly, name: "Private photo reference", note: "", locality: "Cupertino", shareLocation: false, nickname: "Tester")
            preconditionFailure("A source photo without archive flags must stay private")
        } catch CommunityError.server(let message) { precondition(message == CommunityReference.restrictionMessage) }
        let disguisedReference = CommunityPublishRequest(clientObservationID: UUID().uuidString, name: "Private reference", kind: .flower,
            commonName: nil, scientificName: nil, note: "", locality: "Cupertino", latitude: nil, longitude: nil, observedAt: Date(),
            imageBase64: "must-not-be-uploaded", sourceURL: "https://example.com/source", sourcePhotoURL: nil,
            sourceAuthor: "Original observer", sourceAttribution: "Original credit", isReference: false)
        do { _ = try await service.publish(disguisedReference); preconditionFailure("A direct service call cannot disguise a reference as an own upload") }
        catch CommunityError.server(let message) { precondition(message == CommunityReference.restrictionMessage) }
        let afterUnsupportedReferences = await recorder.requests.count
        precondition(beforeUnsupportedReferences == afterUnsupportedReferences, "Reject unsupported references before identity creation or any upload request")
        _ = try await store.publish(observation: archive, name: "Reference poppy", note: "My reference note", locality: "Cupertino", shareLocation: false, nickname: "Tester")
        let privateLocationRequest = await recorder.requests.last!
        let privateBody = try JSONSerialization.jsonObject(with: privateLocationRequest.httpBody!) as! [String: Any]
        precondition(privateBody["latitude"] == nil && privateBody["longitude"] == nil)
        precondition(privateBody["imageBase64"] == nil)
        precondition(privateBody["sourceAuthor"] as? String == "Original observer")
        precondition(privateBody["sourceAttribution"] as? String == archive.sourceAttribution)
        precondition(privateBody["isReference"] as? Bool == true)
        precondition(!String(data: privateLocationRequest.httpBody!, encoding: .utf8)!.contains("private-original"))
        _ = try await store.publish(observation: archive, name: "Reference poppy", note: "My reference note", locality: "Cupertino", shareLocation: true, nickname: "Tester")
        let coarseRequest = await recorder.requests.last!
        let coarseBody = try JSONSerialization.jsonObject(with: coarseRequest.httpBody!) as! [String: Any]
        precondition(coarseBody["latitude"] as? Double == 37.32)
        precondition(coarseBody["longitude"] as? Double == -122.05)
        precondition(coarseBody["commonName"] as? String == archive.commonName)
        precondition(coarseBody["scientificName"] as? String == archive.scientificName)
        try await store.deletePost(store.posts[0])
        precondition(store.posts.isEmpty)
        let deletion = await recorder.requests.last!
        precondition(deletion.httpMethod == "DELETE" && deletion.url?.path == "/v1/posts/\(postID)")

        let beforeInvalid = await recorder.requests.count
        for url in [nil, URL(string: "http://community-contract.invalid"), URL(string: "https://user:secret@community-contract.invalid"), URL(string: "https://community-contract.invalid?token=forbidden"), URL(string: "https://community-contract.invalid#fragment")] {
            let disabled = SocialAPIService(baseURL: url, storage: storage) { request in
                await recorder.record(request)
                throw URLError(.unknown)
            }
            precondition(!disabled.isConfigured)
            do { _ = try await disabled.fetchPosts(); preconditionFailure("Invalid endpoint must not send") }
            catch CommunityError.notConfigured { }
        }
        do { _ = try await service.comments(postID: "../private"); preconditionFailure("Invalid record ID must not send") }
        catch CommunityError.server { }
        let afterInvalid = await recorder.requests.count
        precondition(beforeInvalid == afterInvalid)

        let malformed = SocialAPIService(baseURL: base, storage: storage) { request in
            var post = postFixture(id: postID)
            post["observedAt"] = "not-a-date"
            return (try JSONSerialization.data(withJSONObject: ["posts": [post]]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await malformed.fetchPosts(); preconditionFailure("Malformed remote records must not turn into fake content") }
        catch CommunityError.invalidResponse { }
        let unavailable = SocialAPIService(baseURL: base, storage: storage) { request in
            (Data("{\"error\":\"This discovery is no longer available.\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await unavailable.comments(postID: postID); preconditionFailure("A removed dispatch must return the typed unavailable error") }
        catch CommunityError.unavailableItem { }
        let limited = SocialAPIService(baseURL: base, storage: storage) { request in
            (Data("{\"error\":\"Free community limit reached.\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
        }
        do { _ = try await limited.fetchPosts(); preconditionFailure("Quota failure must stay visible") }
        catch { precondition(error.localizedDescription == "Free community limit reached.") }
        let cancelled = SocialAPIService(baseURL: base, storage: storage) { _ in throw URLError(.cancelled) }
        do { _ = try await cancelled.fetchPosts(); preconditionFailure("Cancellation must not return content") }
        catch is CancellationError { }

        try checkPhotoPrivacy()
        try await checkDeletionRaces()
        print("PASS: ISO dates and optional fields; private/zero/invalid map coordinates; one identity for concurrent calls; endpoint-scoped credentials; Bearer headers; real comment/follow/delete request contracts; archive credits; optional/coarse location payload; blocked unsafe URLs and IDs; visible quota/malformed failures; JPEG metadata removal and 128 KB cap. Fixture responses only; no network requests.")
    }

    private static func postFixture(id: String) -> [String: Any] {
        ["id": id, "author": ["id": userID, "nickname": "Tester"],
         "name": "Poppy", "kind": "flower", "commonName": "California poppy", "scientificName": "Eschscholzia californica",
         "note": "A field note", "locality": "Cupertino", "observedAt": "2026-10-16T10:00:00.123Z", "createdAt": "2026-10-17T10:00:00Z"]
    }
    private static var commentFixture: [String: Any] {
        ["id": commentID, "postID": postID, "author": ["id": userID, "nickname": "Tester"], "text": "A field reply", "createdAt": "2026-10-17T10:05:00.456Z"]
    }

    @MainActor
    private static func checkDeletionRaces() async throws {
        let base = URL(string: "https://deletion-contract.invalid")!
        let scope = base.absoluteString
        let storage = MemorySessionStorage()
        storage.values[scope] = CommunityCredential(token: fixtureToken, user: CommunityUser(id: userID, nickname: "Tester"))
        let recorder = CommunityRequestRecorder()
        let blockGate = CommunityRequestGate()
        let searchGate = CommunityRequestGate()
        let nicknameGate = CommunityRequestGate()
        let deletionGate = CommunityRequestGate()
        let target = CommunityUser(id: "a0000000-0000-4000-8000-000000000002", nickname: "Another observer")
        let service = SocialAPIService(baseURL: base, storage: storage) { request in
            await recorder.record(request)
            let result: [String: Any]
            switch (request.url!.path, request.httpMethod ?? "GET") {
            case ("/v1/blocks/\(target.id)", "POST"):
                await blockGate.hold()
                result = ["blocked": true]
            case ("/v1/users", "GET"):
                await searchGate.hold()
                result = ["users": [["id": target.id, "nickname": target.nickname]]]
            case ("/v1/me", "PATCH"):
                await nicknameGate.hold()
                result = ["user": ["id": userID, "nickname": "Delayed nickname"]]
            case ("/v1/me", "DELETE"):
                await deletionGate.hold()
                result = ["deleted": true]
            case ("/v1/posts", "GET"):
                result = ["posts": []]
            default:
                preconditionFailure("Deletion must not create a replacement identity or make extra authenticated requests")
            }
            return (try JSONSerialization.data(withJSONObject: result), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let store = CommunityStore(api: service)
        let block = Task { try await store.setBlocked(true, user: target) }
        await blockGate.waitForArrival()
        let search = Task { try await service.users(query: "observer") }
        await searchGate.waitForArrival()
        let nickname = Task { try await store.updateNickname("Delayed nickname") }
        await nicknameGate.waitForArrival()
        let deletion = Task { try await store.deleteAccount() }
        await deletionGate.waitForArrival()
        precondition(storage.removeCount == 0 && service.currentUser != nil, "Never clear a credential before confirmed remote deletion")
        do { _ = try await service.ensureSession(); preconditionFailure("A deletion in progress must not create or return a session") }
        catch is CancellationError { }
        await deletionGate.release()
        try await deletion.value
        precondition(service.currentUser == nil && service.bearerToken == nil && store.user == nil)
        precondition(storage.values.isEmpty && storage.removeCount == 1)
        await blockGate.release()
        await searchGate.release()
        await nicknameGate.release()
        do { try await block.value; preconditionFailure("An old block completion must be discarded") }
        catch is CancellationError { }
        do { _ = try await search.value; preconditionFailure("An old search completion must be discarded") }
        catch is CancellationError { }
        do { try await nickname.value; preconditionFailure("An old nickname completion must not restore credentials") }
        catch is CancellationError { }
        precondition(store.blockedUsers.isEmpty && store.posts.isEmpty && store.followingPosts.isEmpty && store.user == nil)
        precondition(storage.saveCount == 0 && storage.values.isEmpty)
        try await store.refreshBlockedUsers()
        await store.refresh()
        let requests = await recorder.requests
        precondition(requests.count == 5 && !requests.contains { $0.url?.path == "/v1/session" })
        precondition(requests.last?.url?.path == "/v1/posts" && requests.last?.value(forHTTPHeaderField: "Authorization") == nil, "Browsing after deletion stays anonymous")
        let deleteRequest = requests.first { $0.httpMethod == "DELETE" }!
        let body = try JSONSerialization.jsonObject(with: deleteRequest.httpBody!) as! [String: String]
        precondition(body == ["confirmation": "DELETE"] && deleteRequest.value(forHTTPHeaderField: "Authorization") == "Bearer \(fixtureToken)")

        let failedStorage = MemorySessionStorage()
        failedStorage.values[scope] = CommunityCredential(token: fixtureToken, user: CommunityUser(id: userID, nickname: "Tester"))
        let failed = SocialAPIService(baseURL: base, storage: failedStorage) { request in
            (Data("{\"error\":\"Fixture deletion unavailable\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        do { try await failed.deleteAccount(); preconditionFailure("A failed deletion must fail visibly") }
        catch CommunityError.server { }
        precondition(failed.currentUser?.id == userID && failedStorage.removeCount == 0 && !failedStorage.values.isEmpty, "Retain the existing credential when the server rejects deletion")
        print("PASS: delayed block/search/nickname responses discarded after deletion; no replacement session or credential writes; confirmation and anonymous browsing; failed deletion preserves identity. Fixture responses only.")
    }

    @MainActor
    private static func checkPhotoPrivacy() throws {
        // Seeded noise is deliberately expensive to JPEG-compress, exercising the byte limit.
        let width = 2400, height = 1600
        var random: UInt64 = 9234
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            random = random &* 6364136223846793005 &+ 1
            pixels[index * 4] = UInt8(truncatingIfNeeded: random >> 24)
            pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: random >> 32)
            pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: random >> 40)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let source = NSMutableData()
        let destination = CGImageDestinationCreateWithData(source, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.32123, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 122.04567, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:16 12:00:00"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Private camera name"]
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let originalSource = CGImageSourceCreateWithData(source as CFData, nil)!
        let originalProperties = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil)! as NSDictionary
        precondition(originalProperties[kCGImagePropertyGPSDictionary] != nil, "Source fixture must contain GPS metadata")
        let originalBytes = source as Data
        let prepared = try CommunityPhoto.prepare(UIImage(data: originalBytes)!)
        precondition(prepared.count <= 128_000 && prepared.count > 0)
        let sharedSource = CGImageSourceCreateWithData(prepared as CFData, nil)!
        let shared = CGImageSourceCopyPropertiesAtIndex(sharedSource, 0, nil)! as NSDictionary
        precondition(shared[kCGImagePropertyGPSDictionary] == nil)
        precondition((shared[kCGImagePropertyExifDictionary] as? NSDictionary)?[kCGImagePropertyExifDateTimeOriginal] == nil)
        precondition((shared[kCGImagePropertyTIFFDictionary] as? NSDictionary)?[kCGImagePropertyTIFFMake] == nil)
        precondition(max(shared[kCGImagePropertyPixelWidth] as! Int, shared[kCGImagePropertyPixelHeight] as! Int) <= 1024)
        precondition(originalBytes == source as Data, "Preparing the public copy must preserve original bytes")
    }
}
