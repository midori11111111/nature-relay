import Foundation

extension CommunityPost {
    /// A transient map annotation. Shared records must never be imported into the private journal.
    var mapObservation: NatureObservation? {
        guard let id = UUID(uuidString: id),
              let latitude, let longitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        var observation = NatureObservation(id: id, name: name, kind: kind, note: note,
            author: author.nickname, latitude: latitude, longitude: longitude, observedAt: observedAt)
        observation.sharedPostID = self.id
        observation.commonName = commonName
        observation.scientificName = scientificName
        observation.sourcePhotoURL = displayImageURL
        observation.locality = locality
        observation.coordinateAccuracyMeters = 1000
        observation.locationSource = "Public community map point, rounded to 0.01°"
        observation.isSourceArchive = isReference
        observation.sourceURL = sourceURL
        observation.sourceAttribution = sourceAttribution
        return observation
    }
}
