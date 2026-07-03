import Foundation
#if canImport(ScreenSaver)
import ScreenSaver
#endif

public enum LocationMode: String, Codable {
    case gps
    case custom
}

public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    private let defaults: UserDefaults? = {
        #if canImport(ScreenSaver)
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        if bundleId.contains("ScreenSaver") || bundleId.contains("legacyScreenSaver") {
            return ScreenSaverDefaults(forModuleWithName: "com.erikferrari.overheadradar.screensaver")
        }
        #endif
        return UserDefaults.standard
    }()
    
    private init() {}
    
    // Keys
    private let keyLocationMode = "locationMode"
    private let keyLatitude = "latitude"
    private let keyLongitude = "longitude"
    private let keyRadius = "radius"
    private let keyRefreshInterval = "refreshInterval"
    private let keyRotationInterval = "rotationInterval"
    
    @MainActor
    public var locationMode: LocationMode {
        get {
            guard let raw = defaults?.string(forKey: keyLocationMode),
                  let mode = LocationMode(rawValue: raw) else {
                return .gps
            }
            return mode
        }
        set {
            defaults?.set(newValue.rawValue, forKey: keyLocationMode)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
    
    @MainActor
    public var latitude: Double {
        get {
            let val = defaults?.double(forKey: keyLatitude) ?? 0.0
            return val == 0.0 ? -33.7749 : val // Sydney default fallback
        }
        set {
            defaults?.set(newValue, forKey: keyLatitude)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
    
    @MainActor
    public var longitude: Double {
        get {
            let val = defaults?.double(forKey: keyLongitude) ?? 0.0
            return val == 0.0 ? 151.28783 : val // Sydney default fallback
        }
        set {
            defaults?.set(newValue, forKey: keyLongitude)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
    
    @MainActor
    public var radiusNm: Int {
        get {
            let val = defaults?.integer(forKey: keyRadius) ?? 0
            return val == 0 ? 20 : val
        }
        set {
            defaults?.set(newValue, forKey: keyRadius)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
    
    @MainActor
    public var refreshInterval: Double {
        get {
            let val = defaults?.double(forKey: keyRefreshInterval) ?? 0.0
            return val == 0.0 ? 8.0 : val
        }
        set {
            defaults?.set(newValue, forKey: keyRefreshInterval)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
    
    @MainActor
    public var rotationInterval: Double {
        get {
            let val = defaults?.double(forKey: keyRotationInterval) ?? 0.0
            return val == 0.0 ? 10.0 : val
        }
        set {
            defaults?.set(newValue, forKey: keyRotationInterval)
            defaults?.synchronize()
            objectWillChange.send()
        }
    }
}
