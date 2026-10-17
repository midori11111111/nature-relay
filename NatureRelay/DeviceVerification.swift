#if DEBUG
import Foundation
import UIKit

@MainActor
enum DeviceVerification {
    private static var didRun = false
    static func runIfRequested(store: RelayStore) {
        let verifyAI = CommandLine.arguments.contains("--verify-ai")
        let verifyLive = CommandLine.arguments.contains("--verify-live")
        guard !didRun, verifyLive || verifyAI || CommandLine.arguments.contains("--verify-photo") else { return }
        didRun = true
        Task {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            do {
                guard let url = Bundle.main.url(forResource: "DemoFlower", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) else { throw CocoaError(.fileReadNoSuchFile) }
                if verifyLive {
                    let liveImage: UIImage
                    if let liveURL = Bundle.main.url(forResource: "LiveScanSample", withExtension: "jpg"), let sample = UIImage(contentsOfFile: liveURL.path) { liveImage = sample }
                    else { liveImage = image }
                    let report = await LiveNatureCameraFixtureVerifier.inspect(image: liveImage, maskDestination: directory.appendingPathComponent("device-live-mask.png"))
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(report).write(to: directory.appendingPathComponent("device-live-verification.json"), options: .atomic)
                    print("NATURE_RELAY_LIVE_CHECK: frame=\(report.hasFrame), mask=\(report.hasActualMask), stage=\(report.errorStage ?? "none")")
                    return
                }
                let result = try await PhotoRecognitionService().recognize(image: image)
                var details: [String: Any] = ["label": result.label, "kind": result.kind.rawValue, "confidence": result.confidence, "foregroundMask": result.usedForegroundMask, "palette": result.paletteHex ?? "none", "hasSticker": result.sticker != nil, "date": Date().ISO8601Format(), "device": UIDevice.current.model]
                try JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("device-verification.json"), options: .atomic)
                if let png = result.sticker?.pngData() { try png.write(to: directory.appendingPathComponent("device-photo-sticker.png"), options: .atomic) }
                print("NATURE_RELAY_DEVICE_CHECK: \(details)")
                if verifyAI {
                    let started = Date()
                    do {
                        // Only the bundled public Unsplash sample is eligible for this
                        // opt-in development check. It never reads personal photo data.
                        let companion = try await FreeStickerAIService().generate(image: image, kind: result.kind, label: result.label, paletteHex: result.paletteHex) { print("NATURE_RELAY_AI_CHECK: \($0)") }
                        let entry = try store.add(name: "AI Petal · demo", kind: result.kind, note: "AI example from the bundled public Unsplash flower photo (https://images.unsplash.com/photo-1490750967868-88aa4486c946). This is not a campus sighting.", author: "Nature Relay demo", latitude: NRTheme.campus.latitude, longitude: NRTheme.campus.longitude, observedAt: Date(), image: image, recognition: result, isSample: true, companion: companion)
                        details["aiSuccess"] = true
                        details["aiProvider"] = companion.provider
                        details["aiModel"] = companion.model
                        details["aiElapsedSeconds"] = Date().timeIntervalSince(started)
                        details["aiImagePersisted"] = entry.companionImageName.flatMap { store.image(named: $0) } != nil
                        if let png = companion.image.pngData() { try png.write(to: directory.appendingPathComponent("device-ai-companion.png"), options: .atomic) }
                    } catch {
                        details["aiSuccess"] = false
                        details["aiError"] = error.localizedDescription
                        if let exampleURL = Bundle.main.url(forResource: "DemoAIFlower", withExtension: "webp"), let example = UIImage(contentsOfFile: exampleURL.path) {
                            let saved = GeneratedCompanion(image: example, provider: "Hugging Face · Black Forest Labs · saved example", model: "FLUX.2 [klein] 4B", seed: 1127, prompt: "Saved public sample illustration; no new generation succeeded.")
                            let entry = try store.add(name: "AI Petal · saved demo", kind: result.kind, note: "Saved AI example, generated earlier from the public Unsplash sample flower photo (https://images.unsplash.com/photo-1490750967868-88aa4486c946). This live request did not succeed. Not a campus sighting.", author: "Nature Relay demo", latitude: NRTheme.campus.latitude, longitude: NRTheme.campus.longitude, observedAt: Date(), image: image, recognition: result, isSample: true, companion: saved)
                            details["savedAIExamplePersisted"] = entry.companionImageName.flatMap { store.image(named: $0) } != nil
                        }
                    }
                    try JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("device-ai-verification.json"), options: .atomic)
                }
            } catch {
                let details = ["error": error.localizedDescription]
                try? JSONSerialization.data(withJSONObject: details).write(to: directory.appendingPathComponent("device-verification.json"), options: .atomic)
                print("NATURE_RELAY_DEVICE_CHECK_ERROR: \(error.localizedDescription)")
            }
        }
    }
}
#endif
