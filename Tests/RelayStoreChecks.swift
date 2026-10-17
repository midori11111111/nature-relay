import Foundation
import UIKit

// Only these two unrelated service surfaces are stubbed. Persistence and all file
// operations below use the production RelayStore, Models, and CaliforniaCatalog.
struct GeneratedCompanion {
    let image: UIImage
    let provider: String
    let model: String
}

enum PhotoRecognitionService {
    static func paletteHex(from image: UIImage, kind: NatureKind) -> String? { nil }
}

private struct StoreCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct RelayStoreChecks {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nature-relay-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("NatureRelayMedia", isDirectory: true)
        let store = RelayStore(directory: root, importCatalog: false)
        try require(store.storageError == nil && store.observations.isEmpty, "isolated store must open empty without importing catalog records")
        let photo = makeImage(.green)
        let redArt = makeImage(.red)
        let blueArt = makeImage(.blue)
        let date = Date(timeIntervalSince1970: 1_750_000_000)

        // These names are manual test input. No image-recognition service is called.
        let manual = try store.add(name: "Poppy friend", kind: .flower, note: "My field note", author: "Photographer",
            latitude: 37.321, longitude: -122.043, observedAt: date, image: photo, recognition: nil,
            commonName: "California poppy", scientificName: "Eschscholzia californica", identificationMethod: "Chosen by photographer")
        let manualPhoto = try fileURL(manual.originalImageName, in: media)
        let manualPhotoBytes = try Data(contentsOf: manualPhoto)
        try require(store.image(named: manual.originalImageName) != nil, "injected store image lookup must use injected media directory")
        let firstColdLoad = RelayStore(directory: root, importCatalog: false)
        try require(firstColdLoad.storageError == nil, "manual entry journal must reopen")
        try require(firstColdLoad.observations.first(where: { $0.id == manual.id }) == manual, "manual common/scientific names and identification method must survive cold reload")
        print("PASS: manual common/scientific names and method survive a cold journal load in an isolated directory.")

        let neighbor = try store.add(name: "Neighbor", kind: .tree, note: "Unrelated note", author: "Other photographer",
            latitude: 36.2, longitude: -121.4, observedAt: date.addingTimeInterval(-100), image: photo, recognition: nil,
            companion: GeneratedCompanion(image: blueArt, provider: "Neighbor fixture", model: "neighbor-model"),
            commonName: "Blue oak", scientificName: "Quercus douglasii", identificationMethod: "Chosen by photographer")
        let neighborMedia = try [neighbor.originalImageName, neighbor.companionImageName].map { try fileURL($0, in: media) }
        let neighborBytes = try neighborMedia.map { try Data(contentsOf: $0) }

        // A wholly synthetic public-source record. No real observation or API is used.
        var source = NatureObservation(id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!, name: "California poppy", kind: .flower,
            note: "Synthetic source note", author: "Fixture observer", latitude: 34.5, longitude: -118.2,
            observedAt: date.addingTimeInterval(-1_000_000))
        source.commonName = "California poppy"
        source.scientificName = "Eschscholzia californica"
        source.sourceURL = "https://www.inaturalist.org/observations/999999999"
        source.sourcePhotoURL = "https://inaturalist-open-data.s3.amazonaws.com/photos/999999999/medium.jpg"
        source.sourceAttribution = "Synthetic attribution fixture, not a real observation"
        source.sourceRecordID = 999999999
        source.sourcePhotoID = 999999999
        source.sourceObservedOn = "2025-01-01"
        source.hasSourceObservationTime = false
        source.photoLicense = "cc-by"
        source.photoLicenseURL = "https://creativecommons.org/licenses/by/4.0/"
        source.locality = "Synthetic fixture area"
        source.coordinateAccuracyMeters = 100
        source.isSourceArchive = true
        source.locationSource = "Synthetic public-source location"

        let savedSource = try store.add(name: "Source companion", kind: .flower, note: "Keep this custom journal note.", author: "Local name",
            latitude: 0, longitude: 0, observedAt: date, image: photo, recognition: nil, sourceObservation: source,
            companion: GeneratedCompanion(image: redArt, provider: "Fixture generator A", model: "fixture-model-a"),
            commonName: "Caller name must not replace source identity", scientificName: "Caller scientific name")
        store.update(savedSource.id) { entry in entry.liked = true; entry.followed = true }
        let oldArtURL = try fileURL(savedSource.companionImageName, in: media)
        let oldArtBytes = try Data(contentsOf: oldArtURL)
        let oldPhotoURL = try fileURL(savedSource.originalImageName, in: media)
        try assertSourceMetadata(savedSource, matches: source)

        let defaultCaptureNote = "A companion inspired by \(source.name). iNaturalist observation by \(source.author); original photo credit below."
        let preserved = try store.add(name: "Source companion again", kind: .flower, note: defaultCaptureNote, author: "Local name",
            latitude: 0, longitude: 0, observedAt: date, image: photo, recognition: nil, sourceObservation: source)
        try require(preserved.companionImageName == savedSource.companionImageName, "saving a source without new artwork must retain its existing artwork filename")
        try require(preserved.aiProvider == "Fixture generator A" && preserved.aiModel == "fixture-model-a", "preserved artwork must retain provider/model provenance")
        try require(preserved.note == "Keep this custom journal note.", "default capture note must not overwrite a custom journal note")
        try require(preserved.liked && preserved.followed, "resaving must preserve favorite and follow state")
        try require(try Data(contentsOf: oldArtURL) == oldArtBytes, "retained artwork bytes must not be deleted or rewritten")
        try require(!FileManager.default.fileExists(atPath: oldPhotoURL.path), "superseded source photo file should be cleaned up")
        try assertSourceMetadata(preserved, matches: source)
        try assertUnchangedNeighbors(in: store, manual: manual, manualPhoto: manualPhoto, manualBytes: manualPhotoBytes,
            neighbor: neighbor, neighborMedia: neighborMedia, neighborBytes: neighborBytes)
        try assertOnlyOneSource(in: store, id: source.id)
        let preservedColdLoad = RelayStore(directory: root, importCatalog: false)
        try require(preservedColdLoad.observations.first(where: { $0.id == source.id }) == preserved, "preserved source artwork and note must survive cold reload")
        print("PASS: repeated public-source save preserves artwork bytes, provider/model, custom note, source credit, likes/follows, and one journal ID.")

        // Also exercise the source-note preservation branch, not only the UI default note.
        let preservedFromSourceNote = try store.add(name: "Source companion", kind: .flower, note: source.note, author: "Local name",
            latitude: 0, longitude: 0, observedAt: date, image: photo, recognition: nil, sourceObservation: source)
        try require(preservedFromSourceNote.note == preserved.note, "an unchanged source note must preserve the custom journal note")
        try require(try Data(contentsOf: oldArtURL) == oldArtBytes, "a second resave must still retain original artwork bytes")
        try assertOnlyOneSource(in: store, id: source.id)

        let replaced = try store.add(name: "Source companion", kind: .flower, note: "An explicitly changed journal note.", author: "Local name",
            latitude: 0, longitude: 0, observedAt: date, image: photo, recognition: nil, sourceObservation: source,
            companion: GeneratedCompanion(image: blueArt, provider: "Fixture generator B", model: "fixture-model-b"))
        let newArtURL = try fileURL(replaced.companionImageName, in: media)
        try require(newArtURL != oldArtURL && FileManager.default.fileExists(atPath: newArtURL.path), "replacement art must be written under a new filename")
        try require(!FileManager.default.fileExists(atPath: oldArtURL.path), "superseded artwork should be removed only after successful replacement")
        try require(try Data(contentsOf: newArtURL) == blueArt.pngData(), "new artwork bytes must match the newly supplied companion")
        try require(replaced.aiProvider == "Fixture generator B" && replaced.aiModel == "fixture-model-b", "replacement provenance must match the new companion")
        try require(replaced.note == "An explicitly changed journal note.", "an explicit journal-note edit must be retained")
        try assertSourceMetadata(replaced, matches: source)
        try assertOnlyOneSource(in: store, id: source.id)
        try assertUnchangedNeighbors(in: store, manual: manual, manualPhoto: manualPhoto, manualBytes: manualPhotoBytes,
            neighbor: neighbor, neighborMedia: neighborMedia, neighborBytes: neighborBytes)
        let replacementColdLoad = RelayStore(directory: root, importCatalog: false)
        try require(replacementColdLoad.storageError == nil && replacementColdLoad.observations.first(where: { $0.id == source.id }) == replaced,
            "replacement source entry must survive cold reload")
        print("PASS: replacing artwork cleans the old file, retains new bytes/provenance/note, keeps one source entry, and leaves other records/media unchanged.")
        print("PASS: real RelayStore checks completed using a temporary directory only; no app journal, live API, or catalog import was used.")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw StoreCheckFailure(description: message) }
    }

    private static func fileURL(_ name: String?, in media: URL) throws -> URL {
        guard let name else { throw StoreCheckFailure(description: "expected a saved media filename") }
        return media.appendingPathComponent(name)
    }

    @MainActor private static func makeImage(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }

    @MainActor private static func assertOnlyOneSource(in store: RelayStore, id: UUID) throws {
        try require(store.observations.count == 3 && store.observations.filter { $0.id == id }.count == 1, "repeated source saves must keep one source ID and both unrelated records")
    }

    private static func assertSourceMetadata(_ actual: NatureObservation, matches source: NatureObservation) throws {
        try require(actual.id == source.id && actual.commonName == source.commonName && actual.scientificName == source.scientificName,
            "public-source species identity must remain intact")
        try require(actual.author == source.author && actual.observedAt == source.observedAt && actual.latitude == source.latitude && actual.longitude == source.longitude,
            "public-source observer, date, and coordinates must remain intact")
        try require(actual.sourceURL == source.sourceURL && actual.sourcePhotoURL == source.sourcePhotoURL && actual.sourceAttribution == source.sourceAttribution
            && actual.photoLicense == source.photoLicense && actual.photoLicenseURL == source.photoLicenseURL,
            "public-source photo attribution and license must remain intact")
        try require(actual.sourcePhotoID == source.sourcePhotoID && actual.sourceRecordID == source.sourceRecordID && actual.sourceObservedOn == source.sourceObservedOn
            && actual.hasSourceObservationTime == source.hasSourceObservationTime && actual.locality == source.locality && actual.coordinateAccuracyMeters == source.coordinateAccuracyMeters,
            "public-source IDs, date precision, locality, and coordinate accuracy must remain intact")
    }

    @MainActor private static func assertUnchangedNeighbors(in store: RelayStore, manual: NatureObservation, manualPhoto: URL, manualBytes: Data,
        neighbor: NatureObservation, neighborMedia: [URL], neighborBytes: [Data]) throws {
        try require(store.observations.first(where: { $0.id == manual.id }) == manual && store.observations.first(where: { $0.id == neighbor.id }) == neighbor,
            "resaving one public source must not mutate unrelated records")
        try require(try Data(contentsOf: manualPhoto) == manualBytes, "manual neighbor photo must remain unchanged")
        for (url, bytes) in zip(neighborMedia, neighborBytes) {
            try require(try Data(contentsOf: url) == bytes, "neighbor media bytes must remain unchanged")
        }
    }
}
