//
//  BackgroundLocationService.swift
//  ClipNote
//
//  Based on Clip's LocationManager by Riley Testut.
//

import Combine
import CoreLocation

// Keeps ClipNote running in the background by receiving coarse location updates.
// The location itself is never used or stored.
class BackgroundLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = BackgroundLocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var shouldRun = false

    override private init() {
        super.init()
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    func start() {
        shouldRun = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Updates start once authorized
            locationManager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Ask once to upgrade to Always. While Using also works as long as updates start in the foreground.
            locationManager.requestAlwaysAuthorization()
            locationManager.startUpdatingLocation()
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        shouldRun = false
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if shouldRun {
                manager.startUpdatingLocation()
            }
        case .denied, .restricted:
            manager.stopUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Background location error: \(error)")
    }
}
