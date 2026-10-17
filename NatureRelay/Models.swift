import SwiftUI
import CoreLocation

enum NatureKind: String, Codable, CaseIterable, Identifiable {
    case flower, tree, bird, butterfly, plant, other
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .flower: return "camera.macro"
        case .tree: return "tree.fill"
        case .bird: return "bird.fill"
        case .butterfly: return "leaf.circle.fill"
        case .plant: return "leaf.fill"
        case .other: return "pawprint.fill"
        }
    }
    var color: Color {
        switch self {
        case .flower: return Color(red: 0.95, green: 0.63, blue: 0.57)
        case .tree: return Color(red: 0.46, green: 0.67, blue: 0.38)
        case .bird: return Color(red: 0.52, green: 0.73, blue: 0.83)
        case .butterfly: return Color(red: 0.77, green: 0.65, blue: 0.85)
        case .plant: return Color(red: 0.67, green: 0.77, blue: 0.39)
        case .other: return Color(red: 0.89, green: 0.70, blue: 0.44)
        }
    }
    var friendName: String {
        switch self {
        case .flower: return "Petal"
        case .tree: return "Oakie"
        case .bird: return "Pip"
        case .butterfly: return "Flutter"
        case .plant: return "Sprout"
        case .other: return "Scout"
        }
    }
}

enum NRTheme {
    static let ink = Color(red: 0.09, green: 0.22, blue: 0.15)
    static let green = Color(red: 0.17, green: 0.37, blue: 0.25)
    static let lime = Color(red: 0.79, green: 0.91, blue: 0.48)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.92)
    static let muted = Color(red: 0.44, green: 0.49, blue: 0.43)
    static let campus = CLLocationCoordinate2D(latitude: 37.3195, longitude: -122.0450)
}

struct NatureObservation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: NatureKind
    var note: String
    var author: String
    var latitude: Double
    var longitude: Double
    var observedAt: Date = Date()
    var originalImageName: String?
    var stickerImageName: String?
    var isSample: Bool = false
    var visionLabel: String?
    var confidence: Double?
    var liked: Bool = false
    var collected: Bool = false
    var followed: Bool = false
    var paletteHex: String?
    var profileID: UUID?
    var storyID: UUID { profileID ?? id }
    var sourceURL: String?
    var sourceAttribution: String?
    var sourcePhotoURL: String?
    var sourceRecordID: Int?
    var companionImageName: String?
    var aiProvider: String?
    var aiModel: String?
    var locationSource: String?
    var locality: String?
    var commonName: String?
    var scientificName: String?
    var photoLicense: String?
    var photoLicenseURL: String?
    var coordinateAccuracyMeters: Double?
    var isSourceArchive: Bool?
    var sourcePhotoID: Int?
    var sourceObservedOn: String?
    var hasSourceObservationTime: Bool?
    var identificationMethod: String?
    var sharedPostID: String?
    var isCommunity: Bool { sourceURL != nil }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var locationLabel: String {
        if isSample { return "De Anza · demo location" }
        if let locality, !locality.isEmpty { return locality }
        return "\(String(format: isCommunity ? "%.2f" : "%.4f", latitude)), \(String(format: isCommunity ? "%.2f" : "%.4f", longitude))"
    }
    var observationDayLabel: String {
        guard let sourceObservedOn else { return observedAt.formatted(date: .abbreviated, time: .omitted) }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: sourceObservedOn) else { return sourceObservedOn }
        parser.dateStyle = .medium
        parser.timeStyle = .none
        return parser.string(from: date)
    }
}

struct RecognitionResult {
    var kind: NatureKind
    var label: String
    var confidence: Double
    var alternatives: [String]
    var sticker: UIImage?
    var usedForegroundMask: Bool
    var paletteHex: String? = nil
}
