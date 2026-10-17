import UIKit
import Vision
import CoreImage
import CoreML
import ImageIO
import CoreLocation

struct PhotoMetadata {
    var latitude: Double?
    var longitude: Double?
    var takenAt: Date?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }
}

/// Photo analysis stays on the device. Results are broad suggestions, not species identification.
final class PhotoRecognitionService {
    private let modelURL: URL?

    init(modelURL: URL? = nil) {
        self.modelURL = modelURL ?? Bundle.main.url(forResource: "MobileNetV2FP16", withExtension: "mlmodelc")
    }

    enum RecognitionError: LocalizedError {
        case unreadableImage
        case unavailable(String)
        case noResults

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "This photo could not be opened. Please choose another image."
            case .unavailable(let detail):
                return "On-device recognition is unavailable here. You can still choose a category and save your photo. \(detail)"
            case .noResults:
                return "No confident image labels were returned. Please choose a category yourself."
            }
        }
    }

    func recognize(image: UIImage) async throws -> RecognitionResult {
        let preferredModelURL = modelURL
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    do {
                        continuation.resume(returning: try Self.performRecognition(image: image, modelURL: preferredModelURL))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private static func performRecognition(image: UIImage, modelURL: URL?) throws -> RecognitionResult {
        guard let normalized = normalizedImage(image), let cgImage = normalized.cgImage else {
            throw RecognitionError.unreadableImage
        }
        // Drawing the source image above applies its EXIF orientation; Vision receives an upright image.
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let observations: [VNClassificationObservation]
        do {
            observations = try classifications(from: handler, modelURL: modelURL)
                .filter { $0.confidence > 0 }
                .sorted { $0.confidence > $1.confidence }
        } catch {
            throw RecognitionError.unavailable(error.localizedDescription)
        }
        guard let best = observations.first else { throw RecognitionError.noResults }

        // Masking is optional: some simulators/devices do not support its compute model.
        var sticker: UIImage?
        var paletteImage = normalized
        var usedForegroundMask = false
        if #available(iOS 17.0, *) {
            let segmentation = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([segmentation])) != nil,
               let mask = segmentation.results?.first,
               !mask.allInstances.isEmpty,
               let pixels = try? mask.generateMaskedImage(
                   ofInstances: mask.allInstances,
                   from: handler,
                   croppedToInstancesExtent: true
               ) {
                let cutout = CIImage(cvPixelBuffer: pixels)
                let context = CIContext(options: [.cacheIntermediates: false])
                if let output = context.createCGImage(cutout, from: cutout.extent) {
                    paletteImage = UIImage(cgImage: output)
                    sticker = borderedCutout(paletteImage)
                    usedForegroundMask = true
                }
            }
        }
        if sticker == nil { sticker = photoBadge(from: normalized) }

        let category = kind(for: [best.identifier])
        return RecognitionResult(
            kind: category,
            label: readableLabel(best.identifier),
            confidence: Double(best.confidence),
            alternatives: observations.prefix(5).map { readableLabel($0.identifier) },
            sticker: sticker,
            usedForegroundMask: usedForegroundMask,
            paletteHex: paletteHex(from: paletteImage, kind: category)
        )
    }

    /// Measures a visible color in the photo; this is a histogram, not image generation.
    /// Masked subjects are preferred by the caller. With a full photo this is only a palette suggestion.
    static func paletteHex(from image: UIImage, kind: NatureKind) -> String? {
        guard let cgImage = image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }

        struct Bin {
            var weight = 0.0
            var red = 0.0
            var green = 0.0
            var blue = 0.0
        }
        var bins = [Bin](repeating: Bin(), count: 24)
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha >= 0.5 else { continue }
            // CGContext stores premultiplied components. Recover the photographed color first.
            let red = min(1, Double(pixels[offset]) / 255 / alpha)
            let green = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let blue = min(1, Double(pixels[offset + 2]) / 255 / alpha)
            let value = max(red, green, blue)
            let delta = value - min(red, green, blue)
            let saturation = value > 0 ? delta / value : 0
            // Transparent cutout margins, dark shadows and white/gray backgrounds cannot define a color.
            guard value >= 0.16, saturation >= 0.20, delta > 0 else { continue }
            var hue: Double
            if value == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if value == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }

            let x = (Double(index % side) + 0.5) / Double(side) * 2 - 1
            let y = (Double(index / side) + 0.5) / Double(side) * 2 - 1
            let center = max(0, 1 - (x * x + y * y) / 2)
            let centerWeight = kind == .bird ? 0.5 + center * 1.5 : 0.75 + center * 0.5
            var categoryWeight = 1.0
            if kind == .flower {
                // Leaves/sky often occupy more of a flower photo than its petals.
                if (0.20..<0.52).contains(hue) { categoryWeight = 0.35 }
                else if (0.52..<0.72).contains(hue) { categoryWeight = 0.55 }
            } else if kind == .plant || kind == .tree {
                if (0.16..<0.50).contains(hue) { categoryWeight = 1.4 }
            }
            let weight = saturation * saturation * alpha * centerWeight * categoryWeight
            let bin = min(23, Int(hue * 24))
            bins[bin].weight += weight
            bins[bin].red += red * weight
            bins[bin].green += green * weight
            bins[bin].blue += blue * weight
        }
        guard let dominant = bins.max(by: { $0.weight < $1.weight }), dominant.weight > 0 else { return nil }
        let red = Int((dominant.red / dominant.weight * 255).rounded())
        let green = Int((dominant.green / dominant.weight * 255).rounded())
        let blue = Int((dominant.blue / dominant.weight * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func classifications(from handler: VNImageRequestHandler, modelURL: URL?) throws -> [VNClassificationObservation] {
        if let modelURL {
            // Bundled pretrained weights run locally. CPU mode is reliable on simulator and device.
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuOnly
            if let model = try? MLModel(contentsOf: modelURL, configuration: configuration),
               let visionModel = try? VNCoreMLModel(for: model) {
                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .centerCrop
                configureSimulatorCompute(for: request)
                if (try? handler.perform([request])) != nil,
                   let labels = request.results as? [VNClassificationObservation], !labels.isEmpty {
                    return labels
                }
            }
        }
        // If weights are missing or cannot load, use the system model without invented labels.
        let classification = VNClassifyImageRequest()
        configureSimulatorCompute(for: classification)
        try handler.perform([classification])
        return classification.results ?? []
    }

    private static func configureSimulatorCompute(for request: VNRequest) {
        #if targetEnvironment(simulator)
        // The simulator advertises a GPU that can fail to create an Espresso context.
        // Use a supported CPU stage when available; actual iPhones keep Vision's default acceleration.
        if let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                if let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
    }

    /// Conservative category grouping. It deliberately never assigns an exact species.
    static func kind(for labels: [String]) -> NatureKind {
        let groups: [(NatureKind, [String])] = [
            (.butterfly, ["butterfly", "butterflies", "admiral", "ringlet", "monarch", "lycaenid"]),
            (.bird, ["bird", "birds", "sparrow", "parrot", "pigeon", "dove", "robin", "crow", "raven", "duck", "eagle", "owl", "goose", "geese", "hummingbird", "peacock", "gull", "finch", "flamingo", "pelican", "woodpecker", "limpkin", "brambling", "goldfinch", "chickadee", "bulbul", "jay", "junco", "magpie", "kite", "vulture", "ptarmigan", "grouse", "quail", "partridge", "pheasant", "bustard", "ostrich", "kingfisher", "bee-eater", "hornbill", "drake", "hen", "cock", "coot", "oystercatcher", "sandpiper", "redshank", "dowitcher", "spoonbill", "stork", "crane", "egret", "heron", "albatross", "penguin", "dipper", "ouzel"]),
            (.flower, ["flower", "flowers", "floral", "blossom", "blossoms", "rose", "roses", "sunflower", "tulip", "daisy", "daisies", "lily", "lilies", "orchid", "dandelion", "marigold", "daffodil", "peony", "hibiscus", "lavender", "lotus"]),
            (.tree, ["tree", "trees", "oak", "maple", "birch", "pine", "palm", "conifer", "redwood", "sequoia", "cypress"]),
            (.plant, ["plant", "plants", "leaf", "leaves", "foliage", "vegetation", "succulent", "fern", "cactus", "cacti", "grass", "shrub", "moss", "seedling", "vine"])
        ]
        for label in labels {
            let words = Set(label.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
            for (category, keywords) in groups where keywords.contains(where: words.contains) {
                return category
            }
        }
        return .other
    }

    static func metadata(from data: Data) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        var latitude = (gps?[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue
        var longitude = (gps?[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue
        if (gps?[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased() == "S", let value = latitude {
            latitude = -abs(value)
        }
        if (gps?[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased() == "W", let value = longitude {
            longitude = -abs(value)
        }
        // Do not turn malformed or partial GPS into a plausible location.
        if let lat = latitude, let lon = longitude {
            if !lat.isFinite || !lon.isFinite || abs(lat) > 90 || abs(lon) > 180 {
                latitude = nil
                longitude = nil
            }
        } else {
            latitude = nil
            longitude = nil
        }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        var takenAt: Date?
        if let original = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.isLenient = false
            if let offset = exif?[kCGImagePropertyExifOffsetTimeOriginal as String] as? String,
               !offset.isEmpty {
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
                takenAt = formatter.date(from: original + offset)
            }
            if takenAt == nil {
                // Older cameras omit an offset; use the local calendar rather than claim a known UTC time.
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                formatter.timeZone = .current
                takenAt = formatter.date(from: original)
            }
        }
        guard latitude != nil || longitude != nil || takenAt != nil else { return nil }
        return PhotoMetadata(latitude: latitude, longitude: longitude, takenAt: takenAt)
    }

    private static func readableLabel(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let factor = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * factor), height: max(1, image.size.height * factor))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func borderedCutout(_ image: UIImage) -> UIImage {
        let side: CGFloat = 600
        let bounds = CGRect(x: 42, y: 42, width: side - 84, height: side - 84)
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let white = image.withTintColor(.white, renderingMode: .alwaysOriginal)
            for step in 0..<24 {
                let angle = CGFloat(step) / 24 * .pi * 2
                white.draw(in: rect.offsetBy(dx: cos(angle) * 10, dy: sin(angle) * 10))
            }
            image.draw(in: rect)
        }
    }

    /// Honest fallback: a circular original-photo badge, not a generated or segmented subject.
    static func photoBadge(from image: UIImage) -> UIImage {
        let side: CGFloat = 600
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let outer = CGRect(x: 24, y: 24, width: 552, height: 552)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: outer).fill()
            context.cgContext.saveGState()
            let inner = outer.insetBy(dx: 12, dy: 12)
            UIBezierPath(ovalIn: inner).addClip()
            let factor = max(inner.width / max(1, image.size.width), inner.height / max(1, image.size.height))
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: CGRect(x: inner.midX - size.width / 2, y: inner.midY - size.height / 2, width: size.width, height: size.height))
            context.cgContext.restoreGState()
        }
    }
}
