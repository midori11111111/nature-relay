import Foundation
import UIKit

struct GeneratedCompanion {
    var image: UIImage
    var provider: String
    var model: String
    var seed: Int?
    var prompt: String
}

/// Optional, anonymous image editing through the model author's public Hugging Face Space.
/// This uses no account, API key, billing method or paid fallback. ZeroGPU can refuse a
/// request when the anonymous shared quota is exhausted. Call only after upload consent.
@MainActor
final class FreeStickerAIService {
    static let providerName = "Hugging Face · Black Forest Labs"
    static let modelName = "FLUX.2 [klein] 4B"
    static let providerURL = URL(string: "https://huggingface.co/spaces/black-forest-labs/FLUX.2-klein-4B")!
    static let privacyMessage = "A resized copy of this photo is sent to Black Forest Labs’ public Hugging Face Space. Photo metadata, your location and your name are not sent. Uploaded and generated images may be accessible through public cache links. The free shared quota may run out; there is no paid fallback."

    enum AIError: LocalizedError {
        case unreadableImage
        case freeQuota(String)
        case service(String)
        case invalidResponse
        case unsafeResult
        case oversizedResponse

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "This photo could not be prepared for AI. Please choose another photo."
            case .freeQuota(let detail):
                return "The free AI quota is temporarily unavailable. Try again later or keep the on-device character. No paid service was used.\(detail.isEmpty ? "" : " " + detail)"
            case .service(let detail): return "The free AI could not finish. You can keep the on-device character. \(detail)"
            case .invalidResponse: return "The free AI returned an unreadable result. Please try again later."
            case .unsafeResult: return "The AI returned an unexpected download address, so the download was stopped."
            case .oversizedResponse: return "The AI response was larger than expected, so the download was stopped."
            }
        }
    }

    private let host = URL(string: "https://black-forest-labs-flux-2-klein-4b.hf.space")!
    private let session: URLSession
    private let redirectGuard: StickerAIRedirectGuard
    private let maxImageBytes = 4 * 1_024 * 1_024

    init() {
        let redirectGuard = StickerAIRedirectGuard()
        self.redirectGuard = redirectGuard
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 200
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "NatureRelay/1.0 (anonymous free demo)"]
        session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
    }

    func generate(
        image: UIImage,
        kind: NatureKind,
        label: String,
        paletteHex: String?,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> GeneratedCompanion {
        try Task.checkCancellation()
        progress("Preparing a photo without location metadata…")
        let jpeg = try preparedJPEG(image)
        progress("Uploading a small photo to the free AI…")
        let remotePath = try await upload(jpeg)
        let imageInput: [String: Any] = [
            "path": remotePath,
            "orig_name": "nature-reference.jpg",
            "mime_type": "image/jpeg",
            "meta": ["_type": "gradio.FileData"]
        ]
        return try await infer(imageInput: imageInput, kind: kind, progress: progress)
    }

    /// Public, licensed source-photo testing can avoid uploading a local photo entirely.
    /// The caller must preserve the source photo's attribution and license with the result.
    func generate(
        publicPhotoURL: URL,
        kind: NatureKind,
        label: String,
        paletteHex: String?,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> GeneratedCompanion {
        guard publicPhotoURL.scheme == "https", publicPhotoURL.user == nil, publicPhotoURL.password == nil else {
            throw AIError.unsafeResult
        }
        let imageInput: [String: Any] = [
            "path": publicPhotoURL.absoluteString,
            "url": publicPhotoURL.absoluteString,
            "orig_name": "public-nature-reference.jpg",
            "meta": ["_type": "gradio.FileData"]
        ]
        return try await infer(imageInput: imageInput, kind: kind, progress: progress)
    }

    private func preparedJPEG(_ image: UIImage) throws -> Data {
        guard image.size.width > 0, image.size.height > 0 else { throw AIError.unreadableImage }
        let scale = min(1, 512 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        // Drawing applies UIImage orientation. Re-encoding the rendered pixels omits EXIF,
        // GPS, capture date and the source filename rather than forwarding the source data.
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.85), data.count < 1_024 * 1_024 else {
            throw AIError.unreadableImage
        }
        return data
    }

    private func upload(_ jpeg: Data) async throws -> String {
        try Task.checkCancellation()
        let boundary = "NatureRelay-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"nature-reference.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: host.appendingPathComponent("gradio_api/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await boundedData(for: request, maximum: 64 * 1_024)
        guard let paths = try? JSONSerialization.jsonObject(with: data) as? [String],
              let path = paths.first, path.hasPrefix("/tmp/gradio/"), path.count < 2_048,
              !path.contains("..") else { throw AIError.invalidResponse }
        return path
    }

    private func infer(
        imageInput: [String: Any],
        kind: NatureKind,
        progress: @escaping @MainActor (String) -> Void
    ) async throws -> GeneratedCompanion {
        try Task.checkCancellation()
        let seed = Int.random(in: 0...2_147_483_647)
        let prompt = stickerPrompt(kind: kind)
        let parameters: [Any] = [
            prompt, [["image": imageInput]], "Distilled (4 steps)", seed, false,
            512, 512, 4, 1.0, false
        ]
        var request = URLRequest(url: host.appendingPathComponent("gradio_api/call/infer"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": parameters])
        progress("Joining the free AI queue…")
        let submitted = try await boundedData(for: request, maximum: 64 * 1_024)
        guard let object = try? JSONSerialization.jsonObject(with: submitted) as? [String: Any],
              let eventID = object["event_id"] as? String,
              eventID.count <= 80,
              !eventID.isEmpty,
              eventID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw AIError.invalidResponse
        }
        let resultURL = host.appendingPathComponent("gradio_api/call/infer").appendingPathComponent(eventID)
        var streamRequest = URLRequest(url: resultURL)
        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: streamRequest)
        // End the underlying connection when the SSE completion arrives, or when any
        // validation/size/cancellation check exits early instead of consuming its body.
        defer { bytes.task.cancel() }
        try validate(response)
        guard response.mimeType == "text/event-stream" else { throw AIError.invalidResponse }
        var eventName = ""
        var eventData: [String] = []
        var totalCharacters = 0
        var completion: [Any]?
        progress("Turning your photo into a companion…")
        for try await line in bytes.lines {
            try Task.checkCancellation()
            totalCharacters += line.utf8.count
            guard totalCharacters <= 512 * 1_024, line.utf8.count <= 128 * 1_024 else {
                throw AIError.oversizedResponse
            }
            if line.hasPrefix("event:") { eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("data:") {
                eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                // Each Gradio call produces one JSON data line per event. Handling it here
                // also works with line iterators which omit the empty SSE separator line.
                let raw = eventData.joined(separator: "\n")
                if eventName == "error" { throw serviceError(raw) }
                if eventName == "complete", let data = raw.data(using: .utf8),
                   let value = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    completion = value
                    break
                }
                if eventName == "heartbeat" || eventName == "generating" { eventData = [] }
            } else if line.isEmpty {
                eventName = ""
                eventData = []
            }
        }
        guard let completion, let file = completion.first as? [String: Any],
              let address = file["url"] as? String, let outputURL = URL(string: address),
              StickerAIRedirectGuard.isAllowed(outputURL) else { throw AIError.invalidResponse }
        progress("Saving your AI companion…")
        let imageData = try await boundedData(for: URLRequest(url: outputURL), maximum: maxImageBytes, image: true)
        guard let image = UIImage(data: imageData), image.size.width <= 2_048, image.size.height <= 2_048 else {
            throw AIError.invalidResponse
        }
        return GeneratedCompanion(
            image: image,
            provider: Self.providerName,
            model: Self.modelName,
            seed: (completion.count > 1 ? completion[1] as? NSNumber : nil)?.intValue ?? seed,
            prompt: prompt
        )
    }

    private func stickerPrompt(kind: NatureKind) -> String {
        // The local histogram may describe background foliage instead of a small bird.
        // Let image editing preserve the photographed subject's own colors; neither the
        // scene palette nor an uncertain classifier label should override the image.
        return "Transform the main \(kind.rawValue == "other" ? "nature subject" : kind.rawValue) in the reference photo into one adorable original collectible nature companion. Preserve the photographed subject's recognizable shape, markings, petals or leaves and its own colors, ignoring the background colors. Make its defining natural feature oversized and charming, with a tiny rounded body, short little limbs, small warm brown bead eyes, faint rosy cheeks and a gentle expression. Soft sculpted storybook illustration, subtle matte clay texture, warm cream highlights, rounded forms and delicate shading. Keep the subject recognizable as the photographed plant or animal. One centered full-body character with breathing room on a clean white background, ready to become a sticker. No heavy black outlines, text, logos, human face or extra characters."
    }

    private func boundedData(for request: URLRequest, maximum: Int, image: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        guard let url = request.url, StickerAIRedirectGuard.isAllowed(url) else { throw AIError.unsafeResult }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try validate(response)
        if image {
            guard let mime = response.mimeType, ["image/webp", "image/png", "image/jpeg"].contains(mime) else {
                throw AIError.invalidResponse
            }
        }
        if response.expectedContentLength > Int64(maximum) { throw AIError.oversizedResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximum else { throw AIError.oversizedResponse }
            data.append(byte)
        }
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              let url = response.url, StickerAIRedirectGuard.isAllowed(url) else { throw AIError.unsafeResult }
        if response.statusCode == 429 { throw AIError.freeQuota("") }
        guard (200...299).contains(response.statusCode) else {
            throw AIError.service("HTTP \(response.statusCode).")
        }
    }

    private func serviceError(_ raw: String) -> AIError {
        // Provider error strings can contain public cache paths. Do not store or expose
        // raw response dumps in the app or debug logs. This public Space currently has
        // show_error=false, so an SSE error may carry JSON null with no usable diagnosis.
        let text = raw.lowercased()
        if text.contains("quota") || text.contains("rate limit") || text.contains("too many requests") || text.contains("429") {
            reportSafeErrorClassification("free-quota-or-rate-limit")
            return .freeQuota("")
        }
        if text.contains("out of capacity") || text.contains("no gpu available") || text.contains("no available gpu") {
            reportSafeErrorClassification("free-gpu-capacity")
            return .service("The free GPU service is at capacity. Try again later.")
        }
        if text.contains("cannot identify image file") || text.contains("not a valid image") || text.contains("failed to download") {
            reportSafeErrorClassification("provider-image-read-error")
            return .service("The provider could not read the photo. Try another photo or try again later.")
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" {
            reportSafeErrorClassification("provider-hidden-error-without-details")
            return .service("The provider returned an error without details. Try again later.")
        }
        reportSafeErrorClassification("provider-error-with-unrecognized-details")
        return .service("The provider reported an error. Try again later.")
    }

    private func reportSafeErrorClassification(_ code: String) {
        #if DEBUG
        // Only a fixed code written by this app is logged: never provider error content,
        // uploaded paths, photo data, coordinates, or the user's original file name.
        print("NATURE_RELAY_AI_ERROR_CLASSIFICATION: \(code)")
        #endif
    }
}

private final class StickerAIRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "black-forest-labs-flux-2-klein-4b.hf.space"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(Self.isAllowed) == true ? request : nil)
    }
}
