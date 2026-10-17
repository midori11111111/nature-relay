import Foundation
import Photos
import CoreLocation

/// Optional catalog lookup for the photo the user selected. Call only from an explicit user action.
@MainActor
enum PhotoLibraryMetadataService {
    enum MetadataError: LocalizedError {
        case accessDenied
        case selectionUnavailable
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Photo Library access is unavailable. Allow access to the selected photo in Settings, or choose a spot on the map."
            case .selectionUnavailable:
                return "The selected photo couldn't be found in your accessible photos. Choose it again, or choose a spot on the map."
            case .locationUnavailable:
                return "This photo has no saved location. Choose a spot on the map."
            }
        }
    }

    static func metadata(for localIdentifier: String) async throws -> PhotoMetadata? {
        guard !localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MetadataError.selectionUnavailable
        }
        try Task.checkCancellation()
        var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        try Task.checkCancellation()
        guard authorization == .authorized || authorization == .limited else {
            throw MetadataError.accessDenied
        }

        // Never enumerate the library or request image downloads. Limited access is sufficient.
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject,
              asset.mediaType == .image else {
            throw MetadataError.selectionUnavailable
        }
        let takenAt = asset.creationDate.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil }
        if let coordinate = asset.location?.coordinate,
           coordinate.latitude.isFinite, coordinate.longitude.isFinite,
           CLLocationCoordinate2DIsValid(coordinate) {
            return PhotoMetadata(latitude: coordinate.latitude, longitude: coordinate.longitude, takenAt: takenAt)
        }
        // A date can still help the user, but it must never imply that a location was found.
        if let takenAt { return PhotoMetadata(latitude: nil, longitude: nil, takenAt: takenAt) }
        throw MetadataError.locationUnavailable
    }
}
