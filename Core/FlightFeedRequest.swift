import Foundation

public enum FlightFeedRequest {
    public static func flightsURL(
        baseURL: URL,
        homeLatitude: Double,
        homeLongitude: Double,
        radiusNm: Int
    ) throws -> URL {
        let normalizedBaseURL: URL
        if baseURL.scheme == nil, !baseURL.absoluteString.contains("://") {
            guard let httpsURL = URL(string: "https://\(baseURL.absoluteString)") else {
                throw URLError(.badURL)
            }
            normalizedBaseURL = httpsURL
        } else {
            normalizedBaseURL = baseURL
        }

        guard var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }

        components.path = components.path.appending("/v1/flights")
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(homeLatitude)),
            URLQueryItem(name: "lon", value: String(homeLongitude)),
            URLQueryItem(name: "radius", value: String(radiusNm))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return url
    }
}
