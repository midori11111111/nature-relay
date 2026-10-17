import Foundation
import UIKit

/// A provider's possible match, not a botanical determination or a probability of correctness.
struct PlantIdentificationCandidate: Codable, Identifiable, Equatable, Sendable {
    var scientificName: String
    var commonNames: [String]
    var score: Double

    var id: String { scientificName.lowercased() }
    var displayName: String { commonNames.first ?? scientificName }
}

struct PlantIdentificationResult: Equatable, Sendable {
    var provider: String
    var candidates: [PlantIdentificationCandidate]
    /// The provider account's shared daily balance, not a separate allowance for this device.
    var remainingDailyRequests: Int?
}

/// Sends one explicitly requested photo to Nature Relay's proxy. Provider keys stay on that server.
/// Offline Core ML category suggestions remain a separate feature and never enter these results.
@MainActor
final class PlantIdentificationService {
    typealias RequestSender = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    enum IdentificationError: LocalizedError, Equatable {
        case notConfigured
        case unreadableImage
        case noCandidates
        case freeLimitReached
        case unavailable
        case invalidResponse
        case connectionFailed

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Plant identification is not connected yet. You can choose a plant name yourself."
            case .unreadableImage:
                return "This photo could not be prepared for identification. Please choose another photo."
            case .noCandidates:
                return "No plant candidates were found. Try a clear close-up of one flower or leaf, or choose a name yourself."
            case .freeLimitReached:
                return "The free identification limit has been reached. Try again later, or choose a plant name yourself."
            case .unavailable:
                return "Plant identification is temporarily unavailable. You can still choose a plant name yourself."
            case .invalidResponse:
                return "The identification service did not return usable candidates. Please try again later."
            case .connectionFailed:
                return "Plant identification needs an internet connection. Your photo is still available to save."
            }
        }
    }

    private let endpoint: URL?
    private let sendRequest: RequestSender

    var isConfigured: Bool { endpoint != nil }

    init(endpoint: URL? = nil, session: URLSession = .shared) {
        self.endpoint = Self.validEndpoint(endpoint ?? Self.configuredEndpoint)
        self.sendRequest = { request in try await session.data(for: request) }
    }

    /// Injection keeps HTTP contract checks independent of network access and provider quota.
    init(endpoint: URL?, sendRequest: @escaping RequestSender) {
        self.endpoint = Self.validEndpoint(endpoint)
        self.sendRequest = sendRequest
    }

    /// Public endpoint configuration only. Never put a Pl@ntNet key in the app bundle.
    static var configuredEndpoint: URL? {
        guard let url = Bundle.main.url(forResource: "NatureRelayConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let value = values["plantIdentificationEndpoint"] as? String {
            return validEndpoint(URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        guard let value = values["communityAPIBaseURL"] as? String,
              let base = validEndpoint(URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))) else { return nil }
        return base.appendingPathComponent("v1").appendingPathComponent("identify")
    }

    func identify(image: UIImage, bearerToken: String) async throws -> PlantIdentificationResult {
        // Missing/invalid configuration must never produce fabricated matches or an upload.
        guard let endpoint else { throw IdentificationError.notConfigured }
        guard !bearerToken.isEmpty, bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw IdentificationError.unavailable
        }
        try Task.checkCancellation()
        let jpeg = try Self.preparedJPEG(from: image)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ja", forHTTPHeaderField: "X-NatureRelay-Language")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = jpeg

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await sendRequest(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // Do not expose upstream URLs, request bodies, credentials, or raw server errors.
            throw IdentificationError.connectionFailed
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw IdentificationError.invalidResponse }
        switch http.statusCode {
        case 200:
            return try Self.decodeResult(data)
        case 404, 422:
            throw IdentificationError.noCandidates
        case 429:
            throw IdentificationError.freeLimitReached
        case 401, 403, 502, 503, 504:
            throw IdentificationError.unavailable
        default:
            throw IdentificationError.invalidResponse
        }
    }

    /// Redrawing applies image orientation and removes EXIF/GPS/capture-time metadata.
    /// The proxy receives image pixels only; location and journal text are never submitted.
    static func preparedJPEG(from image: UIImage) throws -> Data {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw IdentificationError.unreadableImage
        }
        let factor = min(1, 1280 / max(width, height))
        let size = CGSize(width: max(1, (width * factor).rounded()), height: max(1, (height * factor).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let clean = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // Start with the provider's recommended quality; keep unusually complex images below
        // the proxy's 2 MB request limit without sending a second identification request.
        for quality in [0.9, 0.82, 0.72] {
            if let jpeg = clean.jpegData(compressionQuality: quality), jpeg.count <= 1_572_864 {
                return jpeg
            }
        }
        throw IdentificationError.unreadableImage
    }

    private static func validEndpoint(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    private struct ResponsePayload: Decodable {
        var provider: String
        var candidates: [PlantIdentificationCandidate]
        var remainingDailyRequests: Int?
    }

    private static func decodeResult(_ data: Data) throws -> PlantIdentificationResult {
        guard data.count <= 256 * 1024,
              let payload = try? JSONDecoder().decode(ResponsePayload.self, from: data),
              payload.provider == "plantnet" else { throw IdentificationError.invalidResponse }
        var seen = Set<String>()
        let candidates = payload.candidates.compactMap { candidate -> PlantIdentificationCandidate? in
            let scientificName = candidate.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !scientificName.isEmpty, scientificName.count <= 256,
                  candidate.score.isFinite, (0...1).contains(candidate.score) else { return nil }
            let commonNames = candidate.commonNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count <= 120 }
            return PlantIdentificationCandidate(scientificName: scientificName, commonNames: commonNames, score: candidate.score)
        }
        .sorted { $0.score > $1.score }
        .filter { seen.insert($0.id).inserted }
        .prefix(5)
        guard !candidates.isEmpty else { throw IdentificationError.noCandidates }
        return PlantIdentificationResult(
            provider: payload.provider,
            candidates: Array(candidates),
            remainingDailyRequests: payload.remainingDailyRequests.flatMap { $0 >= 0 ? $0 : nil }
        )
    }
}
