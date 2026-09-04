//
//  UserLocationManager.swift
//  invis
//
//  Manages the user's authentic device location via CoreLocation.
//  Requests WhenInUse permissions and defaults the map and target pin
//  to the user's real physical coordinates upon launch.
//

import Foundation
import CoreLocation
import Combine

@MainActor
public final class UserLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = UserLocationManager()

    private let clManager = CLLocationManager()

    @Published public var userLocation: CLLocationCoordinate2D? = nil
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var hasCenteredOnUser: Bool = false

    public override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBest
        clManager.distanceFilter = 5.0
        self.authorizationStatus = clManager.authorizationStatus

        requestAuthorization()
    }

    public func requestAuthorization() {
        if clManager.authorizationStatus == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        } else if clManager.authorizationStatus == .authorizedWhenInUse || clManager.authorizationStatus == .authorizedAlways {
            clManager.startUpdatingLocation()
        }
    }

    public func requestLocationOnce() {
        clManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.userLocation = location.coordinate
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failure or simulated pause
    }
}
