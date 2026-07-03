import Foundation
import OverheadTrackerScreensaverCore

public struct FlightFeedClient {
    public static let defaultHomeLatitude = -33.7749
    public static let defaultHomeLongitude = 151.28783
    //got
    //public static let defaultHomeLatitude = 57.7075
    //public static let defaultHomeLongitude = 11.9675
    //abu
    //public static let defaultHomeLatitude = 24.466667
    //public static let defaultHomeLongitude = 54.366667
    //maryland
    //public static let defaultHomeLatitude = 39.431111
    //public static let defaultHomeLongitude = -77.397222
    public static let defaultRadiusNm = 20
    public static let defaultBaseURL = URL(string: "https://overhead-tracker-flight-api.cyberkallen.workers.dev")!

    let session: URLSession
    let baseURL: URL
    let homeLatitude: Double
    let homeLongitude: Double
    let radiusNm: Int

    public init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            return URLSession(configuration: configuration)
        }(),
        baseURL: URL = defaultBaseURL,
        homeLatitude: Double = defaultHomeLatitude,
        homeLongitude: Double = defaultHomeLongitude,
        radiusNm: Int = defaultRadiusNm
    ) {
        self.session = session
        self.baseURL = baseURL
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.radiusNm = radiusNm
    }

    public func fetchFlights() async throws -> [Flight] {
        let url = try FlightFeedRequest.flightsURL(
            baseURL: baseURL,
            homeLatitude: homeLatitude,
            homeLongitude: homeLongitude,
            radiusNm: radiusNm
        )
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(ProxyFlightResponse.self, from: data)
        return decoded.flights
    }
}
