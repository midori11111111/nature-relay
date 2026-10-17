import Foundation
import UIKit
import ImageIO

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) { requests.append(request) }
}

@main
struct PlantIdentificationChecks {
    @MainActor
    static func main() async throws {
        let endpoint = URL(string: "https://naturerelay-test.invalid/v1/identify")!
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 1200), format: format).image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1200))
        }
        let sourceData = NSMutableData()
        let destination = CGImageDestinationCreateWithData(sourceData, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image.cgImage!, [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.3,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.0,
                kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:17 12:00:00"]
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let photographedImage = UIImage(data: sourceData as Data)!

        // All responses below are contract fixtures. No request reaches Pl@ntNet or consumes quota.
        let json = Data("""
        {"provider":"plantnet","candidates":[
          {"scientificName":" Taraxacum officinale ","commonNames":[" セイヨウタンポポ ",""],"score":0.2},
          {"scientificName":"Eschscholzia californica","commonNames":["California poppy"],"score":0.91},
          {"scientificName":"Eschscholzia californica","commonNames":[],"score":0.5},
          {"scientificName":"Invalid score","commonNames":[],"score":1.1},
          {"scientificName":" ","commonNames":[],"score":0.9}
        ],"remainingDailyRequests":497}
        """.utf8)
        let recorder = RequestRecorder()
        let service = PlantIdentificationService(endpoint: endpoint) { request in
            await recorder.record(request)
            return (json, HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        precondition(service.isConfigured)
        let result = try await service.identify(image: photographedImage, bearerToken: "test-session-token")
        precondition(result.provider == "plantnet")
        precondition(result.remainingDailyRequests == 497)
        precondition(result.candidates.count == 2)
        precondition(result.candidates[0].scientificName == "Eschscholzia californica")
        precondition(result.candidates[0].score == 0.91)
        precondition(result.candidates[1].scientificName == "Taraxacum officinale")
        precondition(result.candidates[1].displayName == "セイヨウタンポポ")
        let requests = await recorder.requests
        precondition(requests.count == 1)
        let request = requests[0]
        precondition(request.url == endpoint && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-session-token")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        precondition(request.value(forHTTPHeaderField: "X-NatureRelay-Language") == "ja")
        let upload = request.httpBody!
        precondition(upload.count <= 1_572_864)
        let uploadedSource = CGImageSourceCreateWithData(upload as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(uploadedSource, 0, nil)! as NSDictionary
        precondition(properties[kCGImagePropertyPixelWidth] as? Int == 1280)
        precondition(properties[kCGImagePropertyPixelHeight] as? Int == 853)
        precondition(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        precondition(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)

        for url in [nil, URL(string: "http://naturerelay-test.invalid/v1/identify"), URL(string: "https://naturerelay-test.invalid/v1/identify?api-key=forbidden")] {
            let unavailable = PlantIdentificationService(endpoint: url) { request in
                await recorder.record(request)
                throw URLError(.unknown)
            }
            precondition(!unavailable.isConfigured)
            await expect(.notConfigured) { try await unavailable.identify(image: photographedImage, bearerToken: "test-session-token") }
        }
        let requestCountAfterUnconfigured = await recorder.requests.count
        precondition(requestCountAfterUnconfigured == 1)

        for (status, expected) in [(404, .noCandidates), (422, .noCandidates), (429, .freeLimitReached), (503, .unavailable)] as [(Int, PlantIdentificationService.IdentificationError)] {
            let failing = PlantIdentificationService(endpoint: endpoint) { _ in
                (Data(), HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            await expect(expected) { try await failing.identify(image: photographedImage, bearerToken: "test-session-token") }
        }
        let malformed = PlantIdentificationService(endpoint: endpoint) { _ in
            (Data("{\"provider\":\"invented\",\"candidates\":[]}".utf8), HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await expect(.invalidResponse) { try await malformed.identify(image: photographedImage, bearerToken: "test-session-token") }
        let empty = PlantIdentificationService(endpoint: endpoint) { _ in
            (Data("{\"provider\":\"plantnet\",\"candidates\":[]}".utf8), HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await expect(.noCandidates) { try await empty.identify(image: photographedImage, bearerToken: "test-session-token") }
        let offline = PlantIdentificationService(endpoint: endpoint) { _ in throw URLError(.notConnectedToInternet) }
        await expect(.connectionFailed) { try await offline.identify(image: photographedImage, bearerToken: "test-session-token") }
        let cancelled = PlantIdentificationService(endpoint: endpoint) { _ in throw URLError(.cancelled) }
        do {
            _ = try await cancelled.identify(image: photographedImage, bearerToken: "test-session-token")
            preconditionFailure("Cancellation must not return candidates")
        } catch is CancellationError { }
        print("PASS: JPEG metadata removal and dimensions, authenticated request contract, ranked/validated candidates, unconfigured/no-upload path, HTTP failures, offline handling, cancellation. Fixture responses only; live Pl@ntNet identification not verified.")
    }

    @MainActor
    private static func expect(_ expected: PlantIdentificationService.IdentificationError, operation: () async throws -> PlantIdentificationResult) async {
        do {
            _ = try await operation()
            preconditionFailure("Expected \(expected)")
        } catch {
            precondition(error as? PlantIdentificationService.IdentificationError == expected, "Expected \(expected), got \(error)")
        }
    }
}
