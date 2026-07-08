import Foundation

public struct Flight: Equatable, Sendable {
    public let id: String
    public let callsign: String
    public let airline: String
    public let aircraftType: String
    public let registration: String
    public let originCity: String
    public let destinationCity: String
    public let originAirportCode: String?
    public let destinationAirportCode: String?
    public let altitudeFt: Int
    public let speedKt: Int
    public let distanceKm: Double
    public let phase: FlightPhase
    public let squawk: String?
    public let hex: String?
    public let category: String?
    public let latitude: Double?
    public let longitude: Double?
    public let track: Double?

    public init(
        id: String,
        callsign: String,
        airline: String,
        aircraftType: String,
        registration: String,
        originCity: String,
        destinationCity: String,
        originAirportCode: String? = nil,
        destinationAirportCode: String? = nil,
        altitudeFt: Int,
        speedKt: Int,
        distanceKm: Double,
        phase: FlightPhase,
        squawk: String?,
        hex: String? = nil,
        category: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        track: Double? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.airline = airline
        self.aircraftType = aircraftType
        self.registration = registration
        self.originCity = originCity
        self.destinationCity = destinationCity
        self.originAirportCode = originAirportCode
        self.destinationAirportCode = destinationAirportCode
        self.altitudeFt = altitudeFt
        self.speedKt = speedKt
        self.distanceKm = distanceKm
        self.phase = phase
        self.squawk = squawk
        self.hex = hex
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.track = track
    }

    public var isEmergency: Bool {
        squawk == "7700" || squawk == "7600" || squawk == "7500"
    }

    public var isGroundVehicle: Bool {
        guard let cat = category?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return false
        }
        return cat.hasPrefix("C")
    }

    public var isNonAircraft: Bool {
        guard let h = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return h.hasPrefix("~")
    }
}

public extension Flight {
    func isInsideGeofence(radiusKm: Double) -> Bool {
        distanceKm <= radiusKm
    }

    var mapHeadingDegrees: Double {
        guard let track else { return -90 }
        return track - 90
    }

    static func bearingDegrees(
        fromLatitude startLatitude: Double,
        longitude startLongitude: Double,
        toLatitude endLatitude: Double,
        longitude endLongitude: Double
    ) -> Double {
        let startLat = startLatitude * .pi / 180
        let endLat = endLatitude * .pi / 180
        let deltaLon = (endLongitude - startLongitude) * .pi / 180

        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    static func distanceKm(
        fromLatitude startLatitude: Double,
        longitude startLongitude: Double,
        toLatitude endLatitude: Double,
        longitude endLongitude: Double
    ) -> Double {
        let earthRadiusKm = 6371.0
        let lat1 = startLatitude * .pi / 180
        let lat2 = endLatitude * .pi / 180
        let deltaLat = (endLatitude - startLatitude) * .pi / 180
        let deltaLon = (endLongitude - startLongitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    var passengerCapacity: Int {
        let u = aircraftType.uppercased()
        if u.contains("380") || u.contains("388") { return 850 }
        if u.contains("747") || u.contains("744") || u.contains("748") { return 600 }
        if u.contains("777") || u.contains("77W") || u.contains("772") || u.contains("773") { return 400 }
        if u.contains("350") || u.contains("359") || u.contains("35K") { return 380 }
        if u.contains("787") || u.contains("789") || u.contains("788") || u.contains("78X") { return 330 }
        if u.contains("330") || u.contains("332") || u.contains("333") { return 300 }
        if u.contains("737") || u.contains("738") || u.contains("739") || u.contains("73H") || u.contains("320") || u.contains("321") || u.contains("A20N") || u.contains("A21N") { return 180 }
        if u.contains("DH8") || u.contains("AT7") { return 78 }
        if u.contains("E90") || u.contains("E19") { return 100 }
        return 20
    }
}
