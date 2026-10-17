import Foundation

/// Pre-generated characters use the confirmed/source species identity. No photo
/// classification or online generation happens when a map annotation is drawn.
@MainActor
enum SpeciesACollection {
    struct Record: Decodable {
        let assetID: String
        let scientificName: String
        let name: String
        let filename: String
        let sourceRecordID: Int
        let traits: String
    }
    private struct Manifest: Decodable { let records: [Record] }
    static let directory = "SpeciesCharactersA"
    static let records: [Record] = {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: directory),
              let bytes = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: bytes) else { return [] }
        return manifest.records.filter {
            !$0.scientificName.isEmpty && $0.filename == $0.assetID + ".png"
                && $0.assetID.range(of: "^a-[a-f0-9]{12}$", options: .regularExpression) != nil
                && Bundle.main.url(forResource: $0.assetID, withExtension: "png", subdirectory: directory) != nil
        }
    }()
    /// The same index is used for archive entries, manual species choices, and
    /// community posts. A category label alone never counts as species identity.
    struct Index {
        private let byScientificName: [String: Record]
        private let bySourceID: [Int: Record]
        private let byCommonName: [String: Record]

        init(records: [Record]) {
            byScientificName = Dictionary(records.map { (Self.normalized($0.scientificName), $0) }, uniquingKeysWith: { first, _ in first })
            bySourceID = Dictionary(records.map { ($0.sourceRecordID, $0) }, uniquingKeysWith: { first, _ in first })
            byCommonName = Dictionary(records.map { (Self.normalized($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        }

        func record(for observation: NatureObservation) -> Record? {
            if let scientificName = observation.scientificName,
               let match = byScientificName[Self.normalized(scientificName)] { return match }
            if let sourceID = observation.sourceRecordID, let match = bySourceID[sourceID] { return match }
            if observation.scientificName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
               let commonName = observation.commonName { return byCommonName[Self.normalized(commonName)] }
            return nil
        }

        private static func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    private static let index = Index(records: records)
    static func record(for observation: NatureObservation) -> Record? { index.record(for: observation) }

    static func assetInfo(for observation: NatureObservation) -> SpeciesCharacterCatalog.AssetInfo? {
        guard let record = record(for: observation) else { return nil }
        return .init(id: record.assetID, title: "\(record.name) companion",
            credit: "Nature Relay · built-in AI image generation", sourceURL: "",
            licenseName: "AI-generated artwork", licenseURL: "",
            isSpeciesSpecific: true, isAdapted: false,
            matchDescription: "\(record.traits)\(record.traits.hasSuffix(".") ? " " : ". ")A stylized character, not evidence of identification.",
            isAIGenerated: true)
    }

}
