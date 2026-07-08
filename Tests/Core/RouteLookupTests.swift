import Foundation
import XCTest
@testable import AirAboveScreensaverCore

final class RouteLookupTests: XCTestCase {
    func test_builds_route_url() throws {
        let url = try RouteLookupRequest.routeURL(
            baseURL: URL(string: "https://example.com")!,
            callsign: " qfa 1 "
        )

        XCTAssertEqual(url.absoluteString, "https://example.com/v1/route?callsign=QFA1")
    }

    func test_decodes_known_route() throws {
        let data = """
        {
          "callsign": "QFA1",
          "dep": "YSSY",
          "arr": "YMML",
          "originCity": "Sydney",
          "destinationCity": "Melbourne",
          "unknown": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RouteLookupResponse.self, from: data)

        XCTAssertEqual(decoded.callsign, "QFA1")
        XCTAssertEqual(decoded.dep, "YSSY")
        XCTAssertEqual(decoded.arr, "YMML")
        XCTAssertEqual(decoded.originCity, "Sydney")
        XCTAssertEqual(decoded.destinationCity, "Melbourne")
        XCTAssertFalse(decoded.unknown)
    }

    func test_hydrates_only_the_visible_window_and_uses_cache() async throws {
        let fetcher = StubRouteFetcher()
        let controller = RouteHydrationController(fetcher: fetcher)

        let flights = [
            flight(id: "1", callsign: "QFA1", distanceKm: 1),
            flight(id: "2", callsign: "QFA2", distanceKm: 2),
            flight(id: "3", callsign: "QFA3", distanceKm: 3),
            flight(id: "4", callsign: "QFA4", distanceKm: 4),
            flight(id: "5", callsign: "QFA5", distanceKm: 5)
        ]

        let first = await controller.hydrate(flights: flights, focusIndex: 0, prefetchCount: 4)
        let second = await controller.hydrate(flights: first, focusIndex: 0, prefetchCount: 4)

        let recordedCalls = await fetcher.recordedCalls()
        XCTAssertEqual(recordedCalls, ["QFA1", "QFA2", "QFA3", "QFA4"])
        XCTAssertEqual(first[0].originCity, "Sydney")
        XCTAssertEqual(first[0].destinationCity, "Melbourne")
        XCTAssertEqual(first[4].originCity, "Unknown")
        XCTAssertEqual(second[0].originCity, "Sydney")
    }

    func test_dedupes_in_flight_lookups() async throws {
        let fetcher = StubRouteFetcher(delayNanoseconds: 100_000_000)
        let controller = RouteHydrationController(fetcher: fetcher)

        let flights = [
            flight(id: "1", callsign: "QFA1", distanceKm: 1),
            flight(id: "2", callsign: "QFA1", distanceKm: 2)
        ]

        async let first = controller.hydrate(flights: flights, focusIndex: 0, prefetchCount: 2)
        async let second = controller.hydrate(flights: flights, focusIndex: 1, prefetchCount: 2)

        _ = await (first, second)

        let qfa1Count = await fetcher.count(for: "QFA1")
        XCTAssertEqual(qfa1Count, 1)
    }

    func test_uses_fallback_route_fetcher_when_primary_returns_no_route() async throws {
        let primary = NilRouteFetcher()
        let fallback = SuccessRouteFetcher()
        let controller = RouteHydrationController(
            fetcher: CompositeRouteLookupClient(primary: primary, fallback: fallback)
        )

        let flights = [
            flight(id: "1", callsign: "QFA1", distanceKm: 1)
        ]

        let hydrated = await controller.hydrate(flights: flights, focusIndex: 0, prefetchCount: 1)
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()

        XCTAssertEqual(hydrated[0].originCity, "Sydney")
        XCTAssertEqual(hydrated[0].destinationCity, "Melbourne")
        XCTAssertEqual(primaryCalls, ["QFA1"])
        XCTAssertEqual(fallbackCalls, ["QFA1"])
    }

    private func flight(id: String, callsign: String, distanceKm: Double) -> Flight {
        Flight(
            id: id,
            callsign: callsign,
            airline: "Qantas",
            aircraftType: "B789",
            registration: "VH-ZNA",
            originCity: "Unknown",
            destinationCity: "Unknown",
            altitudeFt: 35000,
            speedKt: 460,
            distanceKm: distanceKm,
            phase: .cruising,
            squawk: nil
        )
    }
}

private actor StubRouteFetcher: RouteLookupFetching {
    private(set) var calls: [String] = []
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        calls.append(callsign)

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return RouteLookupResponse(
            callsign: callsign,
            dep: "YSSY",
            arr: "YMML",
            originCity: "Sydney",
            destinationCity: "Melbourne",
            unknown: false
        )
    }

    func recordedCalls() -> [String] {
        calls
    }

    func count(for callsign: String) -> Int {
        calls.filter { $0 == callsign }.count
    }
}

private actor NilRouteFetcher: RouteLookupFetching {
    private(set) var recordedCalls: [String] = []

    func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        recordedCalls.append(callsign)
        return nil
    }

    func calls() -> [String] {
        recordedCalls
    }
}

private actor SuccessRouteFetcher: RouteLookupFetching {
    private(set) var recordedCalls: [String] = []

    func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        recordedCalls.append(callsign)
        return RouteLookupResponse(
            callsign: callsign,
            dep: "YSSY",
            arr: "YMML",
            originCity: "Sydney",
            destinationCity: "Melbourne",
            unknown: false
        )
    }

    func calls() -> [String] {
        recordedCalls
    }
}
