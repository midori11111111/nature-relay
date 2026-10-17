import Foundation
import CoreLocation
import Combine

/// A foreground-only, one-shot location fix. No location is uploaded by this service.
@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isLocating = false
    @Published private(set) var message: String?
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var isApproximate = false
    @Published private(set) var lastUpdatedAt: Date?

    private let manager = CLLocationManager()
    private var timeoutTask: Task<Void, Never>?

    var canOpenSettings: Bool { status == .denied || status == .restricted }

    var accuracyDescription: String? {
        guard let accuracy = horizontalAccuracy else { return nil }
        let distance = accuracy < 1_000 ? "\(Int(accuracy.rounded(.up))) m" : String(format: "%.1f km", accuracy / 1_000)
        return isApproximate ? "Approximate location · ±\(distance)" : "Location accuracy · ±\(distance)"
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        status = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
    }

    func requestLocation() {
        guard !isLocating else { return }
        message = nil
        status = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        guard CLLocationManager.locationServicesEnabled() else {
            message = "Location Services are off. Turn them on in iPhone Settings, or choose a spot on the map."
            return
        }
        switch status {
        case .notDetermined:
            isLocating = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestFix()
        case .denied, .restricted:
            isLocating = false
            message = "Location access is off. You can allow it in Settings, or move the map and search for a place."
        @unknown default:
            isLocating = false
            message = "Choose a place on the map to continue."
        }
    }

    private func requestFix() {
        isLocating = true
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) }
            catch { return }
            guard let self, self.isLocating else { return }
            self.isLocating = false
            self.message = "Finding a location is taking a while. Try again outdoors, or choose a spot on the map."
        }
        manager.requestLocation()
    }

    /// Distances are calculated on-device against public map coordinates.
    func distance(to target: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let coordinate, CLLocationCoordinate2DIsValid(target) else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
    }

    func distanceDescription(to target: CLLocationCoordinate2D) -> String? {
        guard let distance = distance(to: target) else { return nil }
        let prefix = isApproximate ? "About " : ""
        if distance < 1_000 { return "\(prefix)\(Int((distance / 10).rounded()) * 10) m away" }
        return String(format: "%@%.1f km away", prefix, distance / 1_000)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        if isLocating {
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                requestFix()
            case .denied, .restricted:
                timeoutTask?.cancel()
                isLocating = false
                message = "Location access is off. You can allow it in Settings, or choose a spot on the map."
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocating else { return }
        // A stale cached fix must not be presented as the user's current position.
        let now = Date()
        guard let fix = locations.last(where: {
            $0.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid($0.coordinate)
                && now.timeIntervalSince($0.timestamp) < 120
                && $0.timestamp.timeIntervalSince(now) < 30
        }) else {
            timeoutTask?.cancel()
            isLocating = false
            message = "A fresh location wasn't available. Try again, or choose a spot on the map."
            return
        }
        timeoutTask?.cancel()
        isLocating = false
        coordinate = fix.coordinate
        horizontalAccuracy = fix.horizontalAccuracy
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        lastUpdatedAt = fix.timestamp
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        timeoutTask?.cancel()
        isLocating = false
        message = "We couldn't find your location. Move the map or search for a place instead."
    }
}
