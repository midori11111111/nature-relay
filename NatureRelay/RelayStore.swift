import SwiftUI
import UIKit

@MainActor
final class RelayStore: ObservableObject {
    @Published var observations: [NatureObservation] = []
    @Published var storageError: String?
    private let includesSamples = CommandLine.arguments.contains("--sample-mode")

    /// Keep the complete saved journal intact while excluding fixtures from normal use.
    var displayObservations: [NatureObservation] {
        includesSamples ? observations : observations.filter { !$0.isSample }
    }
    static var mediaDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NatureRelayMedia", isDirectory: true)
    }
    private let mediaURL: URL
    private let dataURL: URL
    /// Defaults keep the app journal unchanged; checks can use a separate temporary directory.
    init(directory: URL? = nil, importCatalog: Bool = true) {
        let journalDirectory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        mediaURL = journalDirectory.appendingPathComponent("NatureRelayMedia", isDirectory: true)
        dataURL = journalDirectory.appendingPathComponent("nature-relay.json")
        var journalOpened = false
        do {
            try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dataURL.path) {
                observations = try JSONDecoder().decode([NatureObservation].self, from: Data(contentsOf: dataURL))
            } else {
                observations = includesSamples ? Self.samples : []
                try persist()
            }
            journalOpened = true
        } catch {
            storageError = "Your journal could not be opened: \(error.localizedDescription)"
            observations = includesSamples ? Self.samples : []
        }
        if journalOpened && importCatalog {
            do { try installCaliforniaCatalog() }
            catch { storageError = "California photos could not be loaded: \(error.localizedDescription)" }
        }
    }

    private func installCaliforniaCatalog() throws {
        guard let (catalog, directory) = try CaliforniaCatalog.load() else { return }
        let previous = observations
        var changed = false
        for record in catalog.records {
            guard record.photoLicense == "cc-by" || record.photoLicense == "cc0",
                  (-90...90).contains(record.latitude), (-180...180).contains(record.longitude),
                  let date = CaliforniaCatalog.date(record.observedAt) else { continue }
            let sourceFile = directory.appendingPathComponent(record.imageName).standardizedFileURL
            guard sourceFile.path.hasPrefix(directory.standardizedFileURL.path + "/") else { continue }
            let photoName = "catalog-\(sourceFile.lastPathComponent)"
            let photoDestination = mediaURL.appendingPathComponent(photoName)
            if !FileManager.default.fileExists(atPath: photoDestination.path) {
                try FileManager.default.copyItem(at: sourceFile, to: photoDestination)
            }
            var companionName: String?
            if let filename = record.companionImageName {
                let file = directory.appendingPathComponent(filename).standardizedFileURL
                if file.path.hasPrefix(directory.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: file.path) {
                    let name = "catalog-\(file.lastPathComponent)"
                    let destination = mediaURL.appendingPathComponent(name)
                    if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: file, to: destination) }
                    companionName = name
                }
            }
            if let index = observations.firstIndex(where: { $0.id == record.id || $0.sourceRecordID == record.sourceRecordID }) {
                // Preserve personal notes, likes, saved stories, and any existing generated art.
                let samePhoto = record.sourcePhotoID.map { photoID in
                    observations[index].sourcePhotoID == photoID
                        || observations[index].sourcePhotoURL?.contains("/photos/\(photoID)/") == true
                } ?? false
                if samePhoto {
                    let before = observations[index]
                    if observations[index].locality == nil { observations[index].locality = record.locality }
                    if observations[index].commonName == nil { observations[index].commonName = record.name }
                    if observations[index].scientificName == nil { observations[index].scientificName = record.scientificName }
                    if observations[index].photoLicense == nil { observations[index].photoLicense = record.photoLicense }
                    if observations[index].photoLicenseURL == nil { observations[index].photoLicenseURL = record.photoLicenseURL }
                    if observations[index].sourceObservedOn == nil { observations[index].sourceObservedOn = record.observedOn }
                    if observations[index].hasSourceObservationTime == nil { observations[index].hasSourceObservationTime = record.hasSourceObservationTime }
                    if observations[index].sourcePhotoID == nil { observations[index].sourcePhotoID = record.sourcePhotoID }
                    if observations[index].isSourceArchive == nil { observations[index].isSourceArchive = true }
                    changed = changed || observations[index] != before
                }
                if observations[index].isSourceArchive == true, observations[index].companionImageName == nil, let companionName {
                    observations[index].companionImageName = companionName
                    observations[index].aiProvider = record.aiProvider
                    observations[index].aiModel = record.aiModel
                    changed = true
                }
                continue
            }
            var entry = NatureObservation(id: record.id, name: record.name, kind: record.kind,
                note: "A recorded discovery from California. The map shows an approximate area; the organism may no longer be there.",
                author: record.author, latitude: record.latitude, longitude: record.longitude, observedAt: date)
            entry.originalImageName = photoName
            entry.sourceURL = record.sourceURL
            entry.sourceRecordID = record.sourceRecordID
            entry.sourcePhotoID = record.sourcePhotoID
            entry.sourceObservedOn = record.observedOn
            entry.hasSourceObservationTime = record.hasSourceObservationTime
            entry.sourcePhotoURL = record.sourcePhotoURL
            entry.sourceAttribution = record.sourceAttribution
            entry.locality = record.locality
            entry.commonName = record.name
            entry.scientificName = record.scientificName
            entry.photoLicense = record.photoLicense
            entry.photoLicenseURL = record.photoLicenseURL
            entry.coordinateAccuracyMeters = record.coordinateAccuracyMeters
            entry.locationSource = record.locationSource ?? "Approximate area from a public iNaturalist observation"
            entry.isSourceArchive = true
            entry.companionImageName = companionName
            entry.aiProvider = companionName == nil ? nil : record.aiProvider
            entry.aiModel = companionName == nil ? nil : record.aiModel
            observations.append(entry)
            changed = true
        }
        if changed {
            do { try persist() }
            catch { observations = previous; throw error }
        }
    }
    var collected: [NatureObservation] { displayObservations.filter(\.collected) }
    var personalCount: Int { displayObservations.filter { !$0.isSample && !$0.isCommunity }.count }
    func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: mediaURL.appendingPathComponent(name).path)
    }
    func persist() throws {
        try JSONEncoder().encode(observations).write(to: dataURL, options: .atomic)
    }
    func update(_ id: UUID, action: (inout NatureObservation) -> Void) {
        guard let index = observations.firstIndex(where: { $0.id == id }) else { return }
        let before = observations[index]
        action(&observations[index])
        do { try persist() } catch { observations[index] = before; storageError = error.localizedDescription }
    }
    func importCommunity(_ entries: [NatureObservation]) throws {
        let previous = observations
        let ids = Set(observations.compactMap(\.sourceRecordID))
        observations.append(contentsOf: entries.filter { entry in
            guard let id = entry.sourceRecordID else { return false }
            return !ids.contains(id)
        })
        do { try persist() } catch { observations = previous; throw error }
    }
    func toggleLike(_ id: UUID) { update(id) { $0.liked.toggle() } }
    func toggleCollection(_ id: UUID) { update(id) { $0.collected.toggle() } }
    func story(for entry: NatureObservation) -> [NatureObservation] {
        displayObservations.filter { $0.storyID == entry.storyID }.sorted { $0.observedAt > $1.observedAt }
    }
    func toggleFollow(_ id: UUID) {
        guard let item = displayObservations.first(where: { $0.id == id }) else { return }
        let next = !item.followed
        let previous = observations
        let visibleStoryIDs = Set(story(for: item).map(\.id))
        for index in observations.indices where visibleStoryIDs.contains(observations[index].id) { observations[index].followed = next }
        do { try persist() } catch { observations = previous; storageError = error.localizedDescription }
    }
    @discardableResult
    func add(name: String, kind: NatureKind, note: String, author: String, latitude: Double, longitude: Double, observedAt: Date, image: UIImage, recognition: RecognitionResult?, isSample: Bool = false, profileID: UUID? = nil, sourceObservation: NatureObservation? = nil, companion: GeneratedCompanion? = nil, locationSource: String? = nil, commonName: String? = nil, scientificName: String? = nil, identificationMethod: String? = nil) throws -> NatureObservation {
        let previous = observations
        var entry = NatureObservation(name: name.isEmpty ? kind.friendName : name, kind: kind, note: note, author: author.isEmpty ? "You" : author, latitude: latitude, longitude: longitude, observedAt: observedAt, isSample: isSample, visionLabel: recognition?.label, confidence: recognition?.confidence, collected: true)
        entry.locationSource = locationSource
        entry.commonName = commonName
        entry.scientificName = scientificName
        entry.identificationMethod = identificationMethod
        if let source = sourceObservation {
            entry.id = source.id
            entry.sourceURL = source.sourceURL
            entry.sourceAttribution = source.sourceAttribution
            entry.sourcePhotoURL = source.sourcePhotoURL
            entry.sourceRecordID = source.sourceRecordID
            entry.sourcePhotoID = source.sourcePhotoID
            entry.sourceObservedOn = source.sourceObservedOn
            entry.hasSourceObservationTime = source.hasSourceObservationTime
            entry.locality = source.locality
            entry.commonName = source.commonName
            entry.scientificName = source.scientificName
            entry.identificationMethod = source.identificationMethod ?? "Name from the original iNaturalist record"
            entry.photoLicense = source.photoLicense
            entry.photoLicenseURL = source.photoLicenseURL
            entry.coordinateAccuracyMeters = source.coordinateAccuracyMeters
            entry.isSourceArchive = source.isSourceArchive
            entry.author = source.author
            entry.observedAt = source.observedAt
            entry.latitude = source.latitude
            entry.longitude = source.longitude
            entry.locationSource = source.locationSource ?? "Original iNaturalist observation location"
            if let existing = observations.first(where: { $0.id == source.id }) {
                entry.liked = existing.liked
                entry.followed = existing.followed
                if companion == nil {
                    entry.companionImageName = existing.companionImageName
                    entry.aiProvider = existing.aiProvider
                    entry.aiModel = existing.aiModel
                }
                let defaultNote = "A companion inspired by \(source.name). iNaturalist observation by \(source.author); original photo credit below."
                if note == defaultNote || note == source.note { entry.note = existing.note }
            }
        }
        entry.paletteHex = recognition?.paletteHex ?? PhotoRecognitionService.paletteHex(from: image, kind: kind)
        entry.profileID = profileID
        if let profileID, let parent = displayObservations.first(where: { $0.storyID == profileID }) { entry.followed = parent.followed }
        let mediaID = UUID().uuidString
        let original = "\(mediaID)-original.jpg"
        var writtenFiles: [String] = []
        do {
        guard let bytes = image.jpegData(compressionQuality: 0.82) else { throw CocoaError(.fileWriteUnknown) }
        try bytes.write(to: mediaURL.appendingPathComponent(original), options: .atomic)
        writtenFiles.append(original)
        entry.originalImageName = original
        if let png = recognition?.sticker?.pngData() {
            let filename = "\(mediaID)-sticker.png"
            try png.write(to: mediaURL.appendingPathComponent(filename), options: .atomic)
            writtenFiles.append(filename)
            entry.stickerImageName = filename
        }
        if let companion {
            guard let png = companion.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            let filename = "\(mediaID)-companion.png"
            try png.write(to: mediaURL.appendingPathComponent(filename), options: .atomic)
            writtenFiles.append(filename)
            entry.companionImageName = filename
            entry.aiProvider = companion.provider
            entry.aiModel = companion.model
        }
        let replaced = observations.first { $0.id == entry.id }
        observations.removeAll { $0.id == entry.id }
        observations.insert(entry, at: 0)
        try persist()
        if let replaced {
            let retained = Set([entry.originalImageName, entry.stickerImageName, entry.companionImageName].compactMap { $0 })
            for file in [replaced.originalImageName, replaced.stickerImageName, replaced.companionImageName].compactMap({ $0 }) {
                if !retained.contains(file) { try? FileManager.default.removeItem(at: mediaURL.appendingPathComponent(file)) }
            }
        }
        } catch {
            observations = previous
            for file in writtenFiles { try? FileManager.default.removeItem(at: mediaURL.appendingPathComponent(file)) }
            throw error
        }
        return entry
    }
    func delete(_ id: UUID) {
        guard let item = observations.first(where: { $0.id == id }), !item.isSample else { return }
        let previous = observations
        observations.removeAll { $0.id == id }
        do {
            try persist()
            for file in [item.originalImageName, item.stickerImageName, item.companionImageName].compactMap({ $0 }) { try? FileManager.default.removeItem(at: mediaURL.appendingPathComponent(file)) }
        } catch { observations = previous; storageError = error.localizedDescription }
    }
    static var samples: [NatureObservation] {
        let rows: [(String, NatureKind, String, Double, Double)] = [
            ("Petal", .flower, "A tiny reason to take the long way to class.", 37.32005, -122.0455),
            ("Oakie", .tree, "A little shade. A lot of character.", 37.3190, -122.0463),
            ("Pip", .bird, "Look up. Your campus has a soundtrack.", 37.3185, -122.0445),
            ("Flutter", .butterfly, "Some friends never sit still for a photo.", 37.3208, -122.0444),
            ("Sprout", .plant, "Small leaves, main-character energy.", 37.3196, -122.0436)
        ]
        return rows.enumerated().map { i, row in
            NatureObservation(id: UUID(uuidString: "10000000-0000-0000-0000-00000000000\(i)")!, name: row.0, kind: row.1, note: row.2, author: "Nature Relay demo", latitude: row.3, longitude: row.4, observedAt: Date(timeIntervalSince1970: 1792184400 - Double(i * 3600)), isSample: true, collected: i == 0)
        }
    }
}
