import XCTest
@testable import AirAboveScreensaverCore

final class FlightFeedRequestTests: XCTestCase {
    func testBuildsFlightsURLWithLocationQueryParameters() throws {
        let url = try FlightFeedRequest.flightsURL(
            baseURL: URL(string: "overhead-tracker-flight-api.cyberkallen.workers.dev")!,
            homeLatitude: -33.8530,
            homeLongitude: 151.1410,
            radiusNm: 20
        )
        
        XCTAssertEqual(url.absoluteString, "https://overhead-tracker-flight-api.cyberkallen.workers.dev/v1/flights?lat=-33.853&lon=151.141&radius=20")
    }
}
