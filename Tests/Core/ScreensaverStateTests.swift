import XCTest
@testable import AirAboveScreensaverCore

final class ScreensaverStateTests: XCTestCase {
    func testNoFlightsProducesNoFlightsState() {
        let state = ScreensaverState.liveOrEmpty(flights: [])
        XCTAssertEqual(state, .noFlights)
    }
}
