//
//  LocationManager.swift
//  Medora
//
//  Manages CoreLocation permission and location fetching.
//

import Foundation
import CoreLocation
import Combine

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var location: CLLocation?
    @Published var placemark: CLPlacemark?
    @Published var isRequesting = false
    @Published var errorMsg: String?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestLocation() {
        isRequesting = true
        errorMsg = nil
        
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else {
            isRequesting = false
            errorMsg = "Location permission denied. Please enable it in Settings."
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if isRequesting {
                manager.requestLocation()
            }
        } else if status == .denied || status == .restricted {
            if isRequesting {
                isRequesting = false
                errorMsg = "Location permission denied."
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else {
            isRequesting = false
            return
        }
        
        self.location = location
        
        // Reverse geocode to get city/state name for display in textfield
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let firstPlacemark = placemarks.first {
                    self.placemark = firstPlacemark
                }
            } catch {
                self.errorMsg = "Failed to determine address name, but coordinates retrieved."
            }
            self.isRequesting = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.errorMsg = error.localizedDescription
        self.isRequesting = false
    }
}
