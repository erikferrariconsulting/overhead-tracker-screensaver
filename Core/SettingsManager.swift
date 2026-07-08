import Foundation
#if canImport(ScreenSaver)
import ScreenSaver
#endif

public enum LocationMode: String, Codable {
    case gps
    case custom
}

public enum RadarMapStyle: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    
    public var id: String { self.rawValue }
}

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    private let defaults: UserDefaults? = {
        #if canImport(ScreenSaver)
        let bundleId = (Bundle.main.bundleIdentifier ?? "").lowercased()
        if bundleId == "com.erikferrari.airabove.app" {
            return UserDefaults.standard
        } else {
            return ScreenSaverDefaults(forModuleWithName: "com.erikferrari.airabove.screensaver")
        }
        #else
        return UserDefaults.standard
        #endif
    }()
    
    // Keys
    private let keyLocationMode = "locationMode"
    private let keyLatitude = "latitude"
    private let keyLongitude = "longitude"
    private let keyRadius = "radius"
    private let keyRefreshInterval = "refreshInterval"
    private let keyRotationInterval = "rotationInterval"
    private let keyMapStyle = "mapStyle"
    
    @Published public var locationMode: LocationMode = .gps {
        didSet { save(locationMode.rawValue, forKey: keyLocationMode) }
    }
    @Published public var mapStyle: RadarMapStyle = .standard {
        didSet { save(mapStyle.rawValue, forKey: keyMapStyle) }
    }
    @Published public var latitude: Double = -33.7749 {
        didSet { save(latitude, forKey: keyLatitude) }
    }
    @Published public var longitude: Double = 151.28783 {
        didSet { save(longitude, forKey: keyLongitude) }
    }
    @Published public var radiusNm: Int = 20 {
        didSet { save(radiusNm, forKey: keyRadius) }
    }
    @Published public var refreshInterval: Double = 8.0 {
        didSet { save(refreshInterval, forKey: keyRefreshInterval) }
    }
    @Published public var rotationInterval: Double = 10.0 {
        didSet { save(rotationInterval, forKey: keyRotationInterval) }
    }
    
    private init() {
        // Load initial values from defaults
        if let rawMode = defaults?.string(forKey: keyLocationMode),
           let mode = LocationMode(rawValue: rawMode) {
            self.locationMode = mode
        }
        
        let lat = defaults?.double(forKey: keyLatitude) ?? 0.0
        if lat != 0.0 { self.latitude = lat }
        
        let lon = defaults?.double(forKey: keyLongitude) ?? 0.0
        if lon != 0.0 { self.longitude = lon }
        
        let rad = defaults?.integer(forKey: keyRadius) ?? 0
        if rad != 0 { self.radiusNm = rad }
        
        let ref = defaults?.double(forKey: keyRefreshInterval) ?? 0.0
        if ref != 0.0 { self.refreshInterval = ref }
        
        let rot = defaults?.double(forKey: keyRotationInterval) ?? 0.0
        if rot != 0.0 { self.rotationInterval = rot }
        
        if let rawStyle = defaults?.string(forKey: keyMapStyle),
           let style = RadarMapStyle(rawValue: rawStyle) {
            self.mapStyle = style
        }
    }
    
    private func save(_ value: Any, forKey key: String) {
        defaults?.set(value, forKey: key)
        defaults?.synchronize()
    }
}
