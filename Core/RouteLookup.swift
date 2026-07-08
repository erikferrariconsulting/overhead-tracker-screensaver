import Foundation

public enum RouteLookupRequest {
    public static func routeURL(baseURL: URL, callsign: String) throws -> URL {
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

        components.path = components.path.appending("/v1/route")
        components.queryItems = [
            URLQueryItem(name: "callsign", value: normalizeCallsign(callsign))
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        return url
    }

    public static func normalizeCallsign(_ callsign: String) -> String {
        callsign
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .uppercased()
    }
}

public struct RouteLookupResponse: Decodable, Equatable, Sendable {
    public let callsign: String
    public let dep: String?
    public let arr: String?
    public let originCity: String
    public let destinationCity: String
    public let unknown: Bool

    public init(
        callsign: String,
        dep: String?,
        arr: String?,
        originCity: String,
        destinationCity: String,
        unknown: Bool
    ) {
        self.callsign = callsign
        self.dep = dep
        self.arr = arr
        self.originCity = originCity
        self.destinationCity = destinationCity
        self.unknown = unknown
    }

    private enum CodingKeys: String, CodingKey {
        case callsign
        case dep
        case arr
        case originCity
        case destinationCity
        case unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawCallsign = try container.decodeIfPresent(String.self, forKey: .callsign) ?? "UNKNOWN"
        let rawDep = try container.decodeIfPresent(String.self, forKey: .dep)
        let rawArr = try container.decodeIfPresent(String.self, forKey: .arr)
        let rawOriginCity = try container.decodeIfPresent(String.self, forKey: .originCity)
        let rawDestinationCity = try container.decodeIfPresent(String.self, forKey: .destinationCity)

        callsign = rawCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        dep = Self.trimmed(rawDep)
        arr = Self.trimmed(rawArr)
        originCity = Self.trimmed(rawOriginCity) ?? dep ?? "Unknown"
        destinationCity = Self.trimmed(rawDestinationCity) ?? arr ?? "Unknown"
        unknown = try container.decodeIfPresent(Bool.self, forKey: .unknown) ?? false
    }

    private static func trimmed(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let result, !result.isEmpty else { return nil }
        return result
    }
}

public protocol RouteLookupFetching: Sendable {
    func fetchRoute(callsign: String) async throws -> RouteLookupResponse?
}

public struct RouteLookupClient: RouteLookupFetching, Sendable {
    public static let defaultBaseURL = URL(string: "https://overhead-tracker-flight-api.cyberkallen.workers.dev")!

    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            return URLSession(configuration: configuration)
        }(),
        baseURL: URL = defaultBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        let url = try RouteLookupRequest.routeURL(baseURL: baseURL, callsign: callsign)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(RouteLookupResponse.self, from: data)
        return decoded.unknown ? nil : decoded
    }
}

public struct AdsbdbRouteLookupClient: RouteLookupFetching, Sendable {
    public static let defaultBaseURL = URL(string: "https://api.adsbdb.com/v0/callsign")!

    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            return URLSession(configuration: configuration)
        }(),
        baseURL: URL = defaultBaseURL
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        let normalizedCallsign = RouteLookupRequest.normalizeCallsign(callsign)
        guard !normalizedCallsign.isEmpty else { return nil }

        let url = baseURL.appendingPathComponent(normalizedCallsign)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                return nil
            }
            throw URLError(.badServerResponse)
        }

        return try AdsbdbRouteResponseDecoder.decode(from: data, callsign: normalizedCallsign)
    }
}

private enum AdsbdbRouteResponseDecoder {
    private struct Airport: Decodable {
        let municipality: String?
        let icao_code: String?
        let iata_code: String?
        let name: String?
    }

    private struct FlightRoute: Decodable {
        let origin: Airport?
        let destination: Airport?
    }

    private struct Envelope: Decodable {
        let response: ResponsePayload?

        struct ResponsePayload: Decodable {
            let flightroute: FlightRoute?
            let flightRoute: FlightRoute?
            let route: FlightRoute?
        }
    }

    static func decode(from data: Data, callsign: String) throws -> RouteLookupResponse? {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: data)
        let route = envelope.response?.flightroute ?? envelope.response?.flightRoute ?? envelope.response?.route
        guard let route else { return nil }

        let originCity = formatAirportLabel(route.origin)
        let destinationCity = formatAirportLabel(route.destination)
        guard !originCity.isEmpty || !destinationCity.isEmpty else {
            return nil
        }

        return RouteLookupResponse(
            callsign: callsign,
            dep: formatAirportCode(route.origin),
            arr: formatAirportCode(route.destination),
            originCity: originCity.isEmpty ? "Unknown" : originCity,
            destinationCity: destinationCity.isEmpty ? "Unknown" : destinationCity,
            unknown: false
        )
    }

    private static func formatAirportLabel(_ airport: Airport?) -> String {
        guard let airport else { return "" }
        return preferredTrimmedValue(
            airport.municipality,
            airport.iata_code,
            airport.icao_code,
            airport.name
        ) ?? ""
    }

    private static func formatAirportCode(_ airport: Airport?) -> String? {
        guard let airport else { return nil }
        return preferredTrimmedValue(
            airport.icao_code,
            airport.iata_code,
            airport.municipality,
            airport.name
        )
    }

    private static func preferredTrimmedValue(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

public struct CompositeRouteLookupClient: RouteLookupFetching, Sendable {
    private let primary: any RouteLookupFetching
    private let fallback: any RouteLookupFetching

    public init(
        primary: some RouteLookupFetching = RouteLookupClient(),
        fallback: some RouteLookupFetching = AdsbdbRouteLookupClient()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func fetchRoute(callsign: String) async throws -> RouteLookupResponse? {
        do {
            if let route = try await primary.fetchRoute(callsign: callsign) {
                return route
            }
        } catch {
            // Fall through to the direct provider.
        }

        return try await fallback.fetchRoute(callsign: callsign)
    }
}

public actor RouteHydrationController {
    private struct CacheEntry {
        let value: RouteLookupResponse?
        let storedAt: Date
    }

    private let fetcher: any RouteLookupFetching
    private let hitTTL: TimeInterval = 60 * 60 * 24 * 7
    // Route misses are usually transient upstream failures, not permanent truth.
    // Keep this short so a temporary 429 does not freeze the card in "unknown" for long.
    private let missTTL: TimeInterval = 60 * 5
    private var cache: [String: CacheEntry] = [:]
    private var inFlight: [String: Task<RouteLookupResponse?, Error>] = [:]

    public init(fetcher: some RouteLookupFetching = CompositeRouteLookupClient()) {
        self.fetcher = fetcher
    }

    public func hydrate(flights: [Flight], focusIndex: Int, prefetchCount: Int = 4) async -> [Flight] {
        guard !flights.isEmpty else { return flights }

        var hydratedFlights = flights
        for index in selectedIndexes(for: flights, focusIndex: focusIndex, prefetchCount: prefetchCount) {
            guard needsRouteData(flights[index]) else {
                continue
            }
            guard let route = try? await lookupRoute(for: flights[index]) else {
                continue
            }
            hydratedFlights[index] = merge(flight: flights[index], with: route)
        }

        return hydratedFlights
    }

    private func selectedIndexes(for flights: [Flight], focusIndex: Int, prefetchCount: Int) -> [Int] {
        guard !flights.isEmpty, prefetchCount > 0 else { return [] }

        let maxCount = min(prefetchCount, flights.count)
        let startingIndex = max(0, min(focusIndex, flights.count - 1))
        var indexes: [Int] = []

        var offset = 0
        while indexes.count < maxCount && offset < flights.count {
            let candidateIndex = (startingIndex + offset) % flights.count
            offset += 1

            indexes.append(candidateIndex)
        }

        return indexes
    }

    private func needsRouteData(_ flight: Flight) -> Bool {
        !isKnownLabel(flight.originCity) || !isKnownLabel(flight.destinationCity)
    }

    private func isKnownLabel(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.lowercased() != "unknown"
    }

    private func currentUTCDateKey() -> String {
        let calendar = Calendar(identifier: .gregorian)
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = utcCalendar.dateComponents([.year, .month, .day], from: Date())
        let year = components.year ?? 1970
        let month = String(format: "%02d", components.month ?? 1)
        let day = String(format: "%02d", components.day ?? 1)
        return "\(year)-\(month)-\(day)"
    }

    private func cacheKey(for callsign: String) -> String {
        let normalized = RouteLookupRequest.normalizeCallsign(callsign)
        return "route:\(normalized):\(currentUTCDateKey())"
    }

    private func isFresh(_ entry: CacheEntry, now: Date) -> Bool {
        let ttl = entry.value == nil ? missTTL : hitTTL
        return now.timeIntervalSince(entry.storedAt) <= ttl
    }

    private func lookupRoute(for flight: Flight) async throws -> RouteLookupResponse? {
        let normalizedCallsign = RouteLookupRequest.normalizeCallsign(flight.callsign)
        if normalizedCallsign.isEmpty || normalizedCallsign == "UNKNOWN" {
            return nil
        }

        let key = cacheKey(for: normalizedCallsign)
        let now = Date()
        if let cached = cache[key], isFresh(cached, now: now) {
            return cached.value
        }

        if let pending = inFlight[key] {
            return try await pending.value
        }

        let fetcher = fetcher
        let task = Task<RouteLookupResponse?, Error> {
            try await fetcher.fetchRoute(callsign: normalizedCallsign)
        }

        inFlight[key] = task
        defer {
            inFlight[key] = nil
        }

        let route = try await task.value
        cache[key] = CacheEntry(value: route, storedAt: now)
        return route
    }

    private func merge(flight: Flight, with route: RouteLookupResponse) -> Flight {
        func preferredLabel(existing: String, routeLabel: String?, code: String?) -> String {
            if isKnownLabel(existing) {
                return existing
            }
            if let routeLabel, isKnownLabel(routeLabel) {
                return routeLabel
            }
            if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return code
            }
            return existing
        }

        return Flight(
            id: flight.id,
            callsign: flight.callsign,
            airline: flight.airline,
            aircraftType: flight.aircraftType,
            registration: flight.registration,
            originCity: preferredLabel(existing: flight.originCity, routeLabel: route.originCity, code: route.dep),
            destinationCity: preferredLabel(existing: flight.destinationCity, routeLabel: route.destinationCity, code: route.arr),
            originAirportCode: preferredCode(existing: flight.originAirportCode, routeCode: route.dep),
            destinationAirportCode: preferredCode(existing: flight.destinationAirportCode, routeCode: route.arr),
            altitudeFt: flight.altitudeFt,
            speedKt: flight.speedKt,
            distanceKm: flight.distanceKm,
            phase: flight.phase,
            squawk: flight.squawk,
            hex: flight.hex,
            category: flight.category,
            latitude: flight.latitude,
            longitude: flight.longitude,
            track: flight.track
        )
    }

    private func preferredCode(existing: String?, routeCode: String?) -> String? {
        if let existing, !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        if let routeCode, !routeCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return routeCode
        }
        return nil
    }
}
