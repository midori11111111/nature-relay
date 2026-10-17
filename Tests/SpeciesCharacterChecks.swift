import Foundation
import UIKit

private struct CharacterCheckFailure: Error, CustomStringConvertible { let description: String }

@main
struct SpeciesCharacterChecks {
    private struct Manifest: Decodable {
        let generatedCount: Int
        let complete: Bool
        let records: [SpeciesACollection.Record]
    }
    private struct Catalog: Decodable { let records: [SourceRecord] }
    private struct SourceRecord: Decodable {
        let name: String
        let scientificName: String
        let sourceRecordID: Int
        let kind: NatureKind
    }

    @MainActor
    static func main() throws {
        let project = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = project.appendingPathComponent("NatureRelay/SpeciesCharactersA", isDirectory: true)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: project.appendingPathComponent("Resources/CaliforniaCatalog/catalog.json")))
        let partial = CommandLine.arguments.contains("--allow-partial")
        try require(partial || (manifest.complete && manifest.generatedCount == 100), "final collection must contain all 100 species")
        try require(manifest.records.count == manifest.generatedCount, "declared and actual counts must agree")
        let index = SpeciesACollection.Index(records: manifest.records)
        var thumbnailBytes = 0
        let began = Date()
        for record in manifest.records {
            guard let source = catalog.records.first(where: { $0.sourceRecordID == record.sourceRecordID }) else {
                throw CharacterCheckFailure(description: "character has no source observation: \(record.scientificName)")
            }
            var observation = NatureObservation(name: source.name, kind: source.kind, note: "", author: "Fixture", latitude: 0, longitude: 0)
            observation.commonName = source.name
            observation.scientificName = source.scientificName
            observation.sourceRecordID = source.sourceRecordID
            try require(index.record(for: observation)?.assetID == record.assetID, "archive must match its own species: \(source.scientificName)")
            observation.sourceRecordID = nil
            observation.scientificName = " \n" + source.scientificName.uppercased() + "  "
            try require(index.record(for: observation)?.assetID == record.assetID, "manual/community scientific names must normalize consistently")
            observation.scientificName = nil
            observation.commonName = source.name.uppercased()
            try require(index.record(for: observation)?.assetID == record.assetID, "known common name without a scientific identity must resolve")
            observation.commonName = nil
            observation.sourceRecordID = source.sourceRecordID
            try require(index.record(for: observation)?.assetID == record.assetID, "older source entries must resolve by immutable observation ID")
            observation.sourceRecordID = nil
            observation.commonName = source.name
            observation.scientificName = "Unknownus fixture"
            try require(index.record(for: observation) == nil, "a conflicting scientific identity must not silently reuse a common-name character")
            observation.scientificName = nil
            observation.commonName = nil
            try require(index.record(for: observation) == nil, "a category or display nickname must not count as a species identification")
            try autoreleasepool {
                let url = folder.appendingPathComponent(record.filename)
                guard let small = SpeciesCharacterCatalog.decodeArtwork(at: url, maximumPixels: 162)?.cgImage,
                      let detail = SpeciesCharacterCatalog.decodeArtwork(at: url, maximumPixels: 540)?.cgImage else {
                    throw CharacterCheckFailure(description: "actual PNG failed ImageIO decoding: \(record.filename)")
                }
                try require(max(small.width, small.height) <= 162 && max(detail.width, detail.height) <= 540, "map/detail assets must decode at bounded dimensions")
                try require(small.alphaInfo != .none && detail.alphaInfo != .none, "thumbnail decoding must preserve transparency")
                thumbnailBytes += small.bytesPerRow * small.height
            }
        }
        let invalid = folder.appendingPathComponent("missing-character.png")
        try require(SpeciesCharacterCatalog.decodeArtwork(at: invalid, maximumPixels: 162) == nil, "missing artwork must return nil")
        print("PASS: \(manifest.records.count) real species match across archive/manual/community identity routes; unknown identities stay unmatched.")
        print("PASS: all \(manifest.records.count) actual transparent PNGs decode at map/detail sizes; combined map pixels use \(thumbnailBytes) bytes, elapsed \(String(format: "%.2f", Date().timeIntervalSince(began)))s.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        if !condition() { throw CharacterCheckFailure(description: description) }
    }
}
