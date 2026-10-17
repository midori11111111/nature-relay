import Foundation

/// Public, licensed historical records. These are separate from a user's discoveries.
struct CaliforniaCatalog: Decodable {
    let records: [Record]

    struct Record: Decodable {
        let id: UUID
        let name: String
        let scientificName: String?
        let kind: NatureKind
        let latitude: Double
        let longitude: Double
        let locality: String
        let observedAt: String
        let observedOn: String?
        let hasSourceObservationTime: Bool?
        let author: String
        let sourceURL: String
        let sourceRecordID: Int
        let sourcePhotoID: Int?
        let sourcePhotoURL: String
        let sourceAttribution: String
        let photoLicense: String
        let photoLicenseURL: String
        let imageName: String
        let locationSource: String?
        let coordinateAccuracyMeters: Double?
        let companionImageName: String?
        let aiProvider: String?
        let aiModel: String?
    }

    static func load() throws -> (catalog: CaliforniaCatalog, directory: URL)? {
        guard let directory = Bundle.main.url(forResource: "CaliforniaCatalog", withExtension: nil) else { return nil }
        let bytes = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
        return (try JSONDecoder().decode(Self.self, from: bytes), directory)
    }

    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}
