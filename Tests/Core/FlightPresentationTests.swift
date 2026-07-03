import XCTest
@testable import OverheadTrackerScreensaverCore

final class FlightPresentationTests: XCTestCase {
    func testIsInsideGeofenceTreatsBoundaryAsInside() {
        let flight = Flight(
            id: "1",
            callsign: "QFA1",
            airline: "Qantas",
            aircraftType: "B789",
            registration: "VH-ZNA",
            originCity: "Sydney",
            destinationCity: "Melbourne",
            altitudeFt: 36000,
            speedKt: 470,
            distanceKm: 5.0,
            phase: .cruising,
            squawk: nil
        )

        XCTAssertTrue(flight.isInsideGeofence(radiusKm: 5.0))
        XCTAssertFalse(flight.isInsideGeofence(radiusKm: 4.99))
    }

    func testMapHeadingDegreesOffsetsTheAirplaneSymbolToTrueNorth() {
        let flight = Flight(
            id: "1",
            callsign: "QFA1",
            airline: "Qantas",
            aircraftType: "B789",
            registration: "VH-ZNA",
            originCity: "Sydney",
            destinationCity: "Melbourne",
            altitudeFt: 36000,
            speedKt: 470,
            distanceKm: 5.0,
            phase: .cruising,
            squawk: nil,
            track: 0
        )

        XCTAssertEqual(flight.mapHeadingDegrees, -90)
    }

    func testBearingDegreesMatchesCardinalDirections() {
        XCTAssertEqual(
            Flight.bearingDegrees(
                fromLatitude: 0,
                longitude: 0,
                toLatitude: 1,
                longitude: 0
            ),
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            Flight.bearingDegrees(
                fromLatitude: 0,
                longitude: 0,
                toLatitude: 0,
                longitude: 1
            ),
            90,
            accuracy: 0.0001
        )
    }

    func testFlightPassengerCapacity() {
        let f1 = Flight(id: "1", callsign: "QFA1", airline: "Qantas", aircraftType: "A380", registration: "VH-ZNA", originCity: "SYD", destinationCity: "LHR", altitudeFt: 36000, speedKt: 470, distanceKm: 5.0, phase: .cruising, squawk: nil)
        XCTAssertEqual(f1.passengerCapacity, 850)

        let f2 = Flight(id: "2", callsign: "QFA2", airline: "Qantas", aircraftType: "B738", registration: "VH-ZNB", originCity: "SYD", destinationCity: "MEL", altitudeFt: 25000, speedKt: 380, distanceKm: 5.0, phase: .cruising, squawk: nil)
        XCTAssertEqual(f2.passengerCapacity, 180)

        let f3 = Flight(id: "3", callsign: "QFA3", airline: "Qantas", aircraftType: "C172", registration: "VH-ZNC", originCity: "SYD", destinationCity: "CNB", altitudeFt: 5000, speedKt: 110, distanceKm: 5.0, phase: .cruising, squawk: nil)
        XCTAssertEqual(f3.passengerCapacity, 20)
    }

    func testFlightDistanceKm() {
        // Distance between London (51.5074, -0.1278) and Paris (48.8566, 2.3522) is approx 344 km
        let dist = Flight.distanceKm(
            fromLatitude: 51.5074,
            longitude: -0.1278,
            toLatitude: 48.8566,
            longitude: 2.3522
        )
        XCTAssertEqual(dist, 344.0, accuracy: 2.0)
    }
}
