import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    private static let maximumReasonableGreenDistanceMeters = 2_500

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAuthorizationIfNeeded() {
        authorizationStatus = manager.authorizationStatus

        guard authorizationStatus == .notDetermined else {
            startIfAuthorized()
            return
        }

        manager.requestWhenInUseAuthorization()
    }

    func startIfAuthorized() {
        authorizationStatus = manager.authorizationStatus

        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }

        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func currentDistanceMeters(to hole: Hole?) -> Int? {
        guard let hole, let currentLocation else { return nil }

        let green = CLLocation(latitude: hole.greenLatitude, longitude: hole.greenLongitude)
        let distance = Int(currentLocation.distance(from: green).rounded())
        guard distance <= Self.maximumReasonableGreenDistanceMeters else {
            return nil
        }
        return distance
    }

    func bestAvailableLocation() -> CLLocation? {
        currentLocation
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            startIfAuthorized()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let bestLocation = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .sorted(by: { $0.horizontalAccuracy < $1.horizontalAccuracy })
            .first else {
            return
        }

        Task { @MainActor in
            currentLocation = bestLocation
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location update failed: \(error.localizedDescription)")
        #endif
    }
}
