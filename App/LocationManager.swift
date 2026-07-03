import Foundation
import CoreLocation

public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @MainActor @Published public var currentLocation: CLLocationCoordinate2D? = nil
    @MainActor @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    @MainActor private var completionHandler: ((CLLocationCoordinate2D?) -> Void)?
    
    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        // Read initial status on main thread
        DispatchQueue.main.async {
            self.authorizationStatus = self.manager.authorizationStatus
        }
    }
    
    @MainActor
    public func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completionHandler = completion
        
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .denied || status == .restricted {
            completion(nil)
        } else {
            manager.requestLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status != .notDetermined && status != .denied && status != .restricted {
                manager.requestLocation()
            } else if status != .notDetermined {
                completionHandler?(nil)
                completionHandler = nil
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.first?.coordinate
        Task { @MainActor in
            self.currentLocation = coord
            completionHandler?(coord)
            completionHandler = nil
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
        Task { @MainActor in
            completionHandler?(nil)
            completionHandler = nil
        }
    }
}
