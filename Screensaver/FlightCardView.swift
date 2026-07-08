import AppKit
import CryptoKit
import SwiftUI
import MapKit
import AirAboveScreensaverCore
import Ip2LocationIataIcao
import IataUtils
import AirlineLogos

private func findSPMBundle(named name: String) -> Bundle? {
    // 1. Check all loaded bundles for the package name
    for bundle in Bundle.allBundles {
        if let ident = bundle.bundleIdentifier, ident.lowercased().contains(name.lowercased()) {
            return bundle
        }
        if bundle.bundlePath.lowercased().contains(name.lowercased()) {
            return bundle
        }
    }
    for bundle in Bundle.allFrameworks {
        if bundle.bundlePath.lowercased().contains(name.lowercased()) {
            return bundle
        }
    }

    // 2. If running inside the companion App, the bundle is located inside AirAbove.saver/Contents/Resources/
    if let saverURL = Bundle.main.resourceURL?.appendingPathComponent("AirAbove.saver"),
       let saverBundle = Bundle(url: saverURL) {
        if let url = saverBundle.url(forResource: name, withExtension: "bundle") {
            if let b = Bundle(url: url) { return b }
        }
        if let url = saverBundle.url(forResource: "\(name)_\(name)", withExtension: "bundle") {
            if let b = Bundle(url: url) { return b }
        }
    }

    // 3. Search inside the screensaver bundle if it is loaded (e.g. under System Settings)
    for bundle in Bundle.allBundles {
        if bundle.bundlePath.contains("AirAbove.saver") {
            if let url = bundle.url(forResource: name, withExtension: "bundle") {
                if let b = Bundle(url: url) { return b }
            }
            if let url = bundle.url(forResource: "\(name)_\(name)", withExtension: "bundle") {
                if let b = Bundle(url: url) { return b }
            }
        }
    }

    // 4. Fallback search inside AirlineDatabase class bundle
    let classBundle = Bundle(for: AirlineDatabase.self)
    if let url = classBundle.url(forResource: name, withExtension: "bundle") {
        if let b = Bundle(url: url) { return b }
    }
    if let url = classBundle.url(forResource: "\(name)_\(name)", withExtension: "bundle") {
        if let b = Bundle(url: url) { return b }
    }

    return nil
}

@MainActor
struct FlightCardView: View {
    let flight: Flight
    let positionText: String?

    @State private var logoImage: NSImage?

    init(flight: Flight, positionText: String?) {
        self.flight = flight
        self.positionText = positionText
        
        let prefix = airlinePrefix(from: flight.callsign)
        let icao = icaoPrefix(from: prefix)
        let key = "logo:\(icao)"
        if let cached = FlightImageCache.shared.image(for: key) {
            _logoImage = State(initialValue: cached)
        } else {
            _logoImage = State(initialValue: nil)
        }
    }

    private var prefix: String {
        airlinePrefix(from: flight.callsign)
    }

    private var icao: String {
        icaoPrefix(from: prefix)
    }

    private var isAustralianAmbulance: Bool {
        let trimmed = flight.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasPrefix("AM") else { return false }
        let suffix = trimmed.dropFirst(2)
        guard !suffix.isEmpty && suffix.allSatisfy({ $0.isNumber }) else { return false }
        
        let homeLat = FlightFeedClient.defaultHomeLatitude
        let homeLon = FlightFeedClient.defaultHomeLongitude
        let isNearAustralia = (homeLat < 0 && homeLat > -45) && (homeLon > 110 && homeLon < 155)
        
        return isNearAustralia
    }

    private func isAustralianAirport(_ code: String) -> Bool {
        guard let coords = AirportDatabase.shared.airportCoordinates(for: code) else {
            return false
        }
        let lat = coords.latitude
        let lon = coords.longitude
        return (lat < 0 && lat > -45) && (lon > 110 && lon < 155)
    }

    private var logoKey: String {
        "logo:\(icao)"
    }

    private var accentColor: Color {
        if flight.isEmergency {
            return .red
        }

        switch flight.phase {
        case .landing, .takeoff:
            return .orange
        case .approach:
            return .yellow
        case .descending:
            return .cyan
        case .climbing:
            return .green
        case .cruising:
            return .teal
        case .overhead:
            return .white
        case .unknown:
            return .gray
        }
    }

    private var phaseLabel: String {
        flight.isEmergency ? "EMERGENCY" : flight.phase.rawValue.uppercased()
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(formatCallsign(flight.callsign))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        HStack(alignment: .center, spacing: 12) {
                            if isAustralianAmbulance {
                                Image(systemName: "staroflife.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 22)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 8)
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            } else if let logoImage {
                                Image(nsImage: logoImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 24)
                                    .padding(.horizontal, 8)
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                            }

                            let airlineText: String = {
                                if isAustralianAmbulance {
                                    return "NSW Ambulance"
                                }
                                if let resolved = lookupAirlineName(for: prefix) {
                                    return resolved
                                }
                                let raw = flight.airline.trimmingCharacters(in: .whitespacesAndNewlines)
                                if raw == "Unknown" || raw.isEmpty {
                                    return "Private Operator"
                                }
                                return raw
                            }()
                            Text(airlineText)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.88))
                        }

                        let routeText: String = {
                            let origin = flight.originCity
                            let destination = flight.destinationCity
                            let originCode = flight.originAirportCode
                            let destinationCode = flight.destinationAirportCode
                            let hasOrigin = origin != "Unknown" && !origin.isEmpty
                            let hasDestination = destination != "Unknown" && !destination.isEmpty
                            
                            func formatAirport(city: String, code: String?) -> String {
                                let cleanedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
                                let cleanedCode = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""

                                if let codeName = AirportDatabase.shared.airportName(for: cleanedCity) {
                                    if !cleanedCode.isEmpty {
                                        return "\(codeName) (\(cleanedCode))"
                                    }
                                    return codeName
                                }

                                if let airportName = AirportDatabase.shared.airportName(for: cleanedCode) {
                                    return cleanedCode.isEmpty ? airportName : "\(airportName) (\(cleanedCode))"
                                }

                                if !cleanedCode.isEmpty && cleanedCity.uppercased() != cleanedCode {
                                    return "\(cleanedCity) (\(cleanedCode))"
                                }

                                if !cleanedCity.isEmpty {
                                    return cleanedCity
                                }
                                return cleanedCode.isEmpty ? "Unknown" : cleanedCode
                            }
                            
                            if isAustralianAmbulance {
                                if hasOrigin && hasDestination && isAustralianAirport(origin) && isAustralianAirport(destination) {
                                    return "\(formatAirport(city: origin, code: originCode)) to \(formatAirport(city: destination, code: destinationCode))"
                                } else if hasOrigin && isAustralianAirport(origin) {
                                    return "Departing \(formatAirport(city: origin, code: originCode))"
                                } else if hasDestination && isAustralianAirport(destination) {
                                    return "Arriving at \(formatAirport(city: destination, code: destinationCode))"
                                } else {
                                    return "Air Ambulance Mission"
                                }
                            }
                            
                            if !hasOrigin && !hasDestination {
                                return "Route unavailable"
                            } else if hasOrigin && !hasDestination {
                                return "Departing \(formatAirport(city: origin, code: originCode))"
                            } else if !hasOrigin && hasDestination {
                                return "Arriving at \(formatAirport(city: destination, code: destinationCode))"
                            } else {
                                return "\(formatAirport(city: origin, code: originCode)) to \(formatAirport(city: destination, code: destinationCode))"
                            }
                        }()

                        Text(routeText)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundStyle(isAustralianAmbulance ? .red : accentColor)
                    }

                    Spacer(minLength: 12)

                    FlightArtworkTileView(flight: flight, accentColor: accentColor)
                        .frame(width: 240, height: 172)
                }

                Text("\(flight.aircraftType)  \(flight.registration)")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(alignment: .top, spacing: 20) {
                    statView(title: "ALT", value: "\(flight.altitudeFt) FT")
                    statView(title: "SPD", value: "\(flight.speedKt) KT")
                    statView(title: "DST", value: String(format: "%.1f KM", flight.distanceKm))
                    statView(title: "PHASE", value: phaseLabel)
                }

                if flight.isEmergency {
                    Text("EMERGENCY SQUAWK")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.red, lineWidth: 1)
                        )
                }
            }
            .padding(48)
            .frame(maxWidth: 980, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.72), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
                    .shadow(color: accentColor.opacity(0.18), radius: 12, x: 0, y: 4)
            )
            .padding(48)
            .foregroundStyle(.white)
            .overlay(alignment: .topTrailing) {
                if let positionText {
                    Text(positionText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.48))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.75), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(22)
                }
            }
        }
        .task(id: logoKey) {
            if isAustralianAmbulance {
                logoImage = nil
                return
            }
            guard !icao.isEmpty else {
                logoImage = nil
                return
            }

            if let cachedLogo = FlightImageCache.shared.image(for: logoKey) {
                logoImage = cachedLogo
            } else {
                logoImage = nil
                if let loadedLogo = await FlightArtworkFetcher.loadAirlineLogo(prefix: icao) {
                    logoImage = loadedLogo
                    FlightImageCache.shared.store(loadedLogo, for: logoKey)
                }
            }
        }
    }

    private func statView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: value)
        }
        .frame(minWidth: 110, alignment: .leading)
    }
}

@MainActor
private struct FlightArtworkTileView: View {
    let flight: Flight
    let accentColor: Color

    @State private var photoImage: NSImage?
    @State private var photoAttribution: String?

    init(flight: Flight, accentColor: Color) {
        self.flight = flight
        self.accentColor = accentColor

        let cacheResult = Self.cachedPhoto(for: flight)
        _photoImage = State(initialValue: cacheResult.artwork?.image)
        _photoAttribution = State(initialValue: cacheResult.artwork?.attribution)
    }

    private var prefix: String {
        airlinePrefix(from: flight.callsign)
    }

    private var brandColor: Color {
        let trimmed = flight.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isAmbulance: Bool = {
            guard trimmed.hasPrefix("AM") else { return false }
            let suffix = trimmed.dropFirst(2)
            guard !suffix.isEmpty && suffix.allSatisfy({ $0.isNumber }) else { return false }
            let homeLat = FlightFeedClient.defaultHomeLatitude
            let homeLon = FlightFeedClient.defaultHomeLongitude
            return (homeLat < 0 && homeLat > -45) && (homeLon > 110 && homeLon < 155)
        }()
        if isAmbulance {
            return .red
        }
        return airlineBrandColor(for: prefix) ?? accentColor
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(brandColor.opacity(0.48), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 8)

            if let photoImage {
                Image(nsImage: photoImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 240, height: 172)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        if let photoAttribution, !photoAttribution.isEmpty {
                            Text(photoAttribution)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.48))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "airplane")
                        .font(.system(size: 40))
                        .foregroundStyle(brandColor.opacity(0.6))
                    Text("NO PHOTO")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(width: 240, height: 172, alignment: .center)
            }
        }
        .task(id: artworkKey) {
            guard !artworkKey.isEmpty else {
                photoImage = nil
                photoAttribution = nil
                return
            }

            let cacheResult = Self.cachedPhoto(for: flight)
            photoImage = cacheResult.artwork?.image
            photoAttribution = cacheResult.artwork?.attribution

            if cacheResult.needsSearch {
                if let loadedPhoto = await FlightArtworkFetcher.loadAircraftPhoto(flight: flight) {
                    photoImage = loadedPhoto.image
                    photoAttribution = loadedPhoto.attribution
                }
            }
        }
    }

    private var artworkKey: String {
        [
            flight.id,
            flight.callsign,
            prefix,
            flight.hex ?? "",
            flight.registration,
            flight.aircraftType
        ].joined(separator: "|")
    }

    private static func cachedPhoto(for flight: Flight) -> (artwork: CachedArtwork?, needsSearch: Bool) {
        var bestArtwork: CachedArtwork? = nil
        var hasUnsearchedSpecific = false

        for candidate in FlightArtworkFetcher.photoSearchCandidates(for: flight) {
            if let cached = FlightImageCache.shared.artwork(for: candidate.cacheKey) {
                if !cached.notFound {
                    bestArtwork = cached
                    break
                }
            } else {
                if bestArtwork == nil {
                    hasUnsearchedSpecific = true
                }
            }
        }

        return (bestArtwork, hasUnsearchedSpecific)
    }
}

@MainActor
private final class FlightImageCache {
    static let shared = FlightImageCache()
    private var artworks: [String: CachedArtwork] = [:]
    private let diskCacheVersion = "v1"

    func image(for key: String) -> NSImage? {
        artworks[key]?.image
    }

    func artwork(for key: String) -> CachedArtwork? {
        if let memoryArtwork = artworks[key] {
            return memoryArtwork
        }
        if let diskArtwork = loadArtworkFromDisk(for: key) {
            artworks[key] = diskArtwork
            return diskArtwork
        }
        return nil
    }

    func store(_ artwork: CachedArtwork, for key: String) {
        artworks[key] = artwork
        saveArtworkToDisk(artwork, for: key)
    }

    func store(_ image: NSImage, attribution: String? = nil, for key: String) {
        store(CachedArtwork(image: image, attribution: attribution, notFound: false), for: key)
    }

    private func loadArtworkFromDisk(for key: String) -> CachedArtwork? {
        let attributionURL = artworkMetadataURL(for: key)
        guard let metaData = try? Data(contentsOf: attributionURL),
              let metadata = try? JSONDecoder().decode(ArtworkMetadata.self, from: metaData) else {
            return nil
        }

        if metadata.notFound == true {
            return CachedArtwork(image: nil, attribution: nil, notFound: true)
        }

        let imageURL = artworkImageURL(for: key)
        guard let data = try? Data(contentsOf: imageURL),
              let image = NSImage(data: data) else {
            return nil
        }

        return CachedArtwork(image: image, attribution: metadata.attribution, notFound: false)
    }

    private func saveArtworkToDisk(_ artwork: CachedArtwork, for key: String) {
        let imageURL = artworkImageURL(for: key)
        let metadataURL = artworkMetadataURL(for: key)
        do {
            try FileManager.default.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            
            if artwork.notFound {
                let metadata = ArtworkMetadata(attribution: nil, notFound: true)
                let metadataData = try JSONEncoder().encode(metadata)
                try metadataData.write(to: metadataURL, options: .atomic)
                try? FileManager.default.removeItem(at: imageURL)
            } else if let image = artwork.image, let pngData = image.overheadPNGData() {
                try pngData.write(to: imageURL, options: .atomic)
                let metadata = ArtworkMetadata(attribution: artwork.attribution, notFound: false)
                let metadataData = try JSONEncoder().encode(metadata)
                try metadataData.write(to: metadataURL, options: .atomic)
            }
        } catch {
            return
        }
    }

    private var cacheDirectoryURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.airabove.screensaver", isDirectory: true)
            .appendingPathComponent("flight-artwork-cache-\(diskCacheVersion)", isDirectory: true)
    }

    private func artworkImageURL(for key: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(diskCacheKey(for: key)).appendingPathExtension("png")
    }

    private func artworkMetadataURL(for key: String) -> URL {
        cacheDirectoryURL.appendingPathComponent(diskCacheKey(for: key)).appendingPathExtension("json")
    }

    private func diskCacheKey(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private enum FlightArtworkFetcher {
    static func loadAirlineLogo(prefix: String) async -> NSImage? {
        let code = prefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 2 else { return nil }

        // 1. Try custom local SPM package first (AirlineLogos)
        if let bundle = findSPMBundle(named: "AirlineLogos"),
           let logoURL = bundle.url(forResource: code, withExtension: "png", subdirectory: "logos"),
           let image = NSImage(contentsOf: logoURL) {
            return image
        }

        return nil
    }

    static func loadAircraftPhoto(flight: Flight) async -> CachedArtwork? {
        for candidate in photoSearchCandidates(for: flight) {
            if let cached = FlightImageCache.shared.artwork(for: candidate.cacheKey) {
                if cached.notFound {
                    continue
                }
                return cached
            }

            if let fetched = await fetchCommonsPhoto(searchTerm: candidate.searchTerm) {
                FlightImageCache.shared.store(fetched, for: candidate.cacheKey)
                return fetched
            } else {
                let negativeArtwork = CachedArtwork(image: nil, attribution: nil, notFound: true)
                FlightImageCache.shared.store(negativeArtwork, for: candidate.cacheKey)
            }
        }

        return nil
    }

    static func photoSearchCandidates(for flight: Flight) -> [PhotoSearchCandidate] {
        var candidates: [PhotoSearchCandidate] = []
        let reg = flight.registration.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reg.isEmpty && reg != "---" && reg != "Unknown" {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:reg:\(reg.uppercased())",
                searchTerm: "\"\(reg)\""
            ))
        }

        if let hex = flight.hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:hex:\(hex.uppercased())",
                searchTerm: "\"\(hex)\""
            ))
        }

        let airline = flight.airline.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = flight.aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = aircraftFamilyLabel(for: type)

        if !airline.isEmpty, let family = family {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:airline_family:\(airline.uppercased()):\(family.uppercased())",
                searchTerm: "\"\(airline)\" \(family)"
            ))
        }

        if !airline.isEmpty, !type.isEmpty {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:airline_type:\(airline.uppercased()):\(type.uppercased())",
                searchTerm: "\"\(airline)\" \(type)"
            ))
        }

        if let family = family {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:family:\(family.uppercased())",
                searchTerm: family
            ))
        } else if !type.isEmpty {
            candidates.append(PhotoSearchCandidate(
                cacheKey: "commons:type:\(type.uppercased())",
                searchTerm: type
            ))
        }

        return candidates
    }

    private static func fetchCommonsPhoto(searchTerm: String) async -> CachedArtwork? {
        guard let url = commonsSearchURL(for: searchTerm) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("AirAboveScreensaver/1.0 (+https://airabove.com)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                return nil
            }

            let decoded = try JSONDecoder().decode(WikimediaCommonsSearchResponse.self, from: data)
            guard let page = decoded.bestPage,
                  let imageInfo = page.imageinfo?.first,
                  let photoURL = imageInfo.bestImageURL else {
                return nil
            }

            let attribution = imageInfo.bestAttribution

            var photoRequest = URLRequest(url: photoURL)
            photoRequest.setValue("AirAboveScreensaver/1.0 (+https://airabove.com)", forHTTPHeaderField: "User-Agent")

            let (photoData, photoResponse) = try await URLSession.shared.data(for: photoRequest)
            if let httpPhotoResponse = photoResponse as? HTTPURLResponse, !(200...299).contains(httpPhotoResponse.statusCode) {
                return nil
            }

            guard let image = NSImage(data: photoData) else { return nil }
            return CachedArtwork(image: image, attribution: attribution, notFound: false)
        } catch {
            return nil
        }
    }
}

private struct CachedArtwork {
    let image: NSImage?
    let attribution: String?
    let notFound: Bool
}

private struct ArtworkMetadata: Codable {
    let attribution: String?
    let notFound: Bool?
}

private struct PhotoSearchCandidate {
    let cacheKey: String
    let searchTerm: String
}

private struct WikimediaCommonsSearchResponse: Decodable {
    let query: WikimediaCommonsQuery?

    var bestPage: WikimediaCommonsPage? {
        guard let query else { return nil }
        if let pageids = query.pageids {
            for pageid in pageids {
                if let page = query.pages[pageid] {
                    return page
                }
            }
        }
        return query.pages.values.first
    }
}

private struct WikimediaCommonsQuery: Decodable {
    let pageids: [String]?
    let pages: [String: WikimediaCommonsPage]
}

private struct WikimediaCommonsPage: Decodable {
    let pageid: Int?
    let title: String?
    let imageinfo: [WikimediaCommonsImageInfo]?
}

private struct WikimediaCommonsImageInfo: Decodable {
    let thumburl: URL?
    let url: URL?
    let descriptionurl: URL?
    let extmetadata: [String: WikimediaCommonsMetadata]?

    var bestImageURL: URL? {
        thumburl ?? url
    }

    var bestAttribution: String? {
        let artist = extmetadata?["Artist"]?.plainTextValue
        let license = extmetadata?["LicenseShortName"]?.plainTextValue ?? extmetadata?["UsageTerms"]?.plainTextValue
        guard artist != nil || license != nil else { return nil }
        let title = extmetadata?["ObjectName"]?.plainTextValue
        var parts: [String] = []

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            parts.append(title)
        }
        if let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            parts.append("by \(artist)")
        }
        if let license = license?.trimmingCharacters(in: .whitespacesAndNewlines), !license.isEmpty {
            parts.append(license)
        }
        parts.append("Wikimedia Commons")

        return parts.joined(separator: " • ")
    }
}

private struct WikimediaCommonsMetadata: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
            return
        }

        if let stringValue = try? container.decode(String.self) {
            value = stringValue
            return
        }

        if let doubleValue = try? container.decode(Double.self) {
            value = String(doubleValue)
            return
        }

        if let intValue = try? container.decode(Int.self) {
            value = String(intValue)
            return
        }

        if let boolValue = try? container.decode(Bool.self) {
            value = String(boolValue)
            return
        }

        value = nil
    }

    var plainTextValue: String? {
        guard let value else { return nil }
        return value.htmlToPlainText()
    }
}

private extension String {
    func htmlToPlainText() -> String {
        guard let data = data(using: .utf8) else { return self }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension NSImage {
    func overheadPNGData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension WikimediaCommonsSearchResponse {
    static func searchURL(for term: String) -> URL? {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: term),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: "10"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "480")
        ]
        return components?.url
    }
}

private extension FlightArtworkFetcher {
    static func commonsSearchURL(for term: String) -> URL? {
        WikimediaCommonsSearchResponse.searchURL(for: term)
    }
}

private func aircraftFamilyLabel(for aircraftType: String) -> String? {
    let type = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    switch type {
    case "A318", "A319", "A320", "A20N", "A321", "A21N":
        return "Airbus A320 family"
    case "A220", "BCS1", "BCS3":
        return "Airbus A220 family"
    case "A330", "A332", "A333", "A339", "A33X":
        return "Airbus A330 family"
    case "A350", "A359", "A35K":
        return "Airbus A350 family"
    case "B737", "B38M", "B739", "B738", "B737-700", "B737-800", "B737-900":
        return "Boeing 737 family"
    case "B747", "B748":
        return "Boeing 747 family"
    case "B757":
        return "Boeing 757 family"
    case "B767":
        return "Boeing 767 family"
    case "B777", "B77L", "B77W", "B772", "B773":
        return "Boeing 777 family"
    case "B787", "B788", "B789", "B78X":
        return "Boeing 787 Dreamliner"
    case "E190", "E195", "E170", "E175", "E2", "E190-E2", "E195-E2":
        return "Embraer E-Jet family"
    case "CRJ7", "CRJ9", "CRJX", "CRJ2":
        return "Bombardier CRJ family"
    case "DH8A", "DH8B", "DH8C", "DH8D":
        return "De Havilland Canada Dash 8 family"
    default:
        return nil
    }
}

private func airlinePrefix(from callsign: String) -> String {
    let prefix = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return prefix.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? ""
}

private func icaoPrefix(from prefix: String) -> String {
    let clean = prefix.uppercased()
    if clean.count == 3 {
        return clean
    }
    for (icao, iata) in icaoToIataCallsignMap {
        if iata == clean {
            return icao
        }
    }
    return AirlineDatabase.shared.icaoCode(forIata: clean) ?? clean
}

private func airlineBrandColor(for prefix: String) -> Color? {
    switch prefix.uppercased() {
    case "QFA", "QLK", "JAL", "JST", "CCA", "QXE", "BAW", "AFR":
        return Color(red: 1.0, green: 0.125, blue: 0.129)
    case "VOZ", "MAS", "QTR", "THY", "VJC", "CRK", "DAL", "PDT", "PSA":
        return Color(red: 1.0, green: 0.271, blue: 0.549)
    case "RXA", "FJI", "ANZ", "SIA", "TGW", "ANG", "WJA", "UPS":
        return Color(red: 0.129, green: 0.875, blue: 0.259)
    case "UAE", "ETD", "DLH", "AIC", "FRE", "HND", "NKS":
        return Color(red: 1.0, green: 0.835, blue: 0.0)
    case "THA", "PAL", "EVA", "ASA", "JBU", "SWA", "AAL", "UAL", "FDM":
        return Color(red: 0.259, green: 0.667, blue: 1.0)
    case "CPA", "CSN", "CES", "KAL", "AAR", "ACA", "CAV", "SKW", "RPA", "EDV", "GJS", "SCX", "MES", "VOI":
        return Color(red: 0.647, green: 0.396, blue: 1.0)
    case "HAL", "LAN", "CHH", "CXA", "CEB", "FDX", "GTI", "CLX", "DHK", "TAY", "NJT", "PEL", "UTY":
        return Color(red: 1.0, green: 0.647, blue: 0.0)
    default:
        return nil
    }
}

private let icaoToIataCallsignMap: [String: String] = [
    "ASA": "AS",
    "QFA": "QF",
    "QLK": "QF",
    "UAL": "UA",
    "AAL": "AA",
    "DLH": "LH",
    "DAL": "DL",
    "BAW": "BA",
    "AFR": "AF",
    "ANZ": "NZ",
    "SIA": "SQ",
    "UAE": "EK",
    "ETD": "EY",
    "VOZ": "VA",
    "JST": "JQ",
    "CPA": "CX",
    "CSN": "CZ",
    "CES": "MU",
    "CCA": "CA",
    "HAL": "HA",
    "WJA": "WS",
    "AIC": "AI",
    "JAL": "JL",
    "ANA": "NH",
    "THY": "TK",
    "QTR": "QR"
]

private func formatCallsign(_ callsign: String) -> String {
    let trimmed = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let letters = trimmed.prefix(while: { $0.isLetter })
    let suffix = trimmed.dropFirst(letters.count)
    let key = String(letters)
    if let iata = AirlineDatabase.shared.iataCode(foricao: key) {
        return "\(iata)\(suffix)"
    }
    if let iata = icaoToIataCallsignMap[key] {
        return "\(iata)\(suffix)"
    }
    return trimmed
}

private func lookupAirlineName(for prefix: String) -> String? {
    let code = prefix.uppercased()
    if let name = AirlineDatabase.shared.airlineName(foricao: code) {
        return name
    }
    switch code {
    // Australia & Pacific
    case "QLK": return "QantasLink"
    case "QFA": return "Qantas"
    case "VOZ": return "Virgin Australia"
    case "JST": return "Jetstar"
    case "RXA": return "Regional Express"
    case "NZM": return "Air New Zealand Link"
    case "ANZ": return "Air New Zealand"
    case "FJI": return "Fiji Airways"
    case "ANG": return "Air Niugini"
    case "UTY": return "Alliance Airlines"
    case "PEL": return "Pel-Air"
    // North America
    case "ASA": return "Alaska Airlines"
    case "QXE": return "Horizon Air"
    case "UAL": return "United Airlines"
    case "AAL": return "American Airlines"
    case "DAL": return "Delta Air Lines"
    case "JBU": return "JetBlue"
    case "SWA": return "Southwest Airlines"
    case "WJA": return "WestJet"
    case "ACA": return "Air Canada"
    case "SKW": return "SkyWest Airlines"
    case "RPA": return "Republic Airways"
    case "EDV": return "Endeavor Air"
    case "GJS": return "GoJet Airlines"
    case "SCX": return "Sun Country Airlines"
    case "MES": return "Mesaba Airlines"
    case "PDT": return "Piedmont Airlines"
    case "PSA": return "PSA Airlines"
    case "HAL": return "Hawaiian Airlines"
    // Europe
    case "BAW": return "British Airways"
    case "AFR": return "Air France"
    case "DLH": return "Lufthansa"
    case "THY": return "Turkish Airlines"
    // Asia & Middle East
    case "SIA": return "Singapore Airlines"
    case "QTR": return "Qatar Airways"
    case "UAE": return "Emirates"
    case "ETD": return "Etihad Airways"
    case "TGW": return "Scoot"
    case "MAS": return "Malaysia Airlines"
    case "VJC": return "VietJet Air"
    case "PAL": return "Philippine Airlines"
    case "EVA": return "EVA Air"
    case "CPA": return "Cathay Pacific"
    case "CSN": return "China Southern"
    case "CES": return "China Eastern"
    case "CCA": return "Air China"
    case "FDM": return "Flyadeal"
    case "KAL": return "Korean Air"
    case "AAR": return "Asiana Airlines"
    case "CHH": return "Hainan Airlines"
    case "CXA": return "XiamenAir"
    case "CEB": return "Cebu Pacific"
    case "JAL": return "Japan Airlines"
    case "ANA": return "All Nippon Airways"
    case "AIC": return "Air India"
    case "CRK": return "Hong Kong Airlines"
    // Cargo & others
    case "FDX": return "FedEx Express"
    case "UPS": return "UPS Airlines"
    case "GTI": return "Atlas Air"
    case "CLX": return "Cargolux"
    case "DHK": return "DHL Air UK"
    case "TAY": return "ASL Airlines Belgium"
    case "NJT": return "NetJets"
    default: return nil
    }
}

private let defaultAirports: [String: String] = [
    // Australia — major
    "YSSY": "Sydney", "YSAY": "Sydney", "YMLB": "Melbourne", "YMML": "Melbourne", "YBBN": "Brisbane",
    "YPPH": "Perth", "YPAD": "Adelaide", "YSCB": "Canberra", "YBCS": "Cairns", "YBHM": "Hamilton Is",
    "YBTL": "Townsville", "YBAS": "Alice Springs", "YBDG": "Bendigo", "YDBY": "Derby",
    "YSNF": "Norfolk Is", "YAGD": "Aganda", "YMHB": "Hobart", "YMLT": "Launceston",
    "SYD": "Sydney", "MEL": "Melbourne", "BNE": "Brisbane", "PER": "Perth", "ADL": "Adelaide",
    "CBR": "Canberra", "CNS": "Cairns", "OOL": "Gold Coast", "TSV": "Townsville", "DRW": "Darwin",
    "HBA": "Hobart", "LST": "Launceston", "MKY": "Mackay", "ROK": "Rockhampton",
    // Australia — NSW regional
    "YWLM": "Newcastle", "NTL": "Newcastle",
    "YBNA": "Ballina", "BNK": "Ballina",
    "YCFS": "Coffs Harbour", "CFS": "Coffs Harbour",
    "YPMQ": "Port Macquarie", "PQQ": "Port Macquarie",
    "YSDU": "Dubbo", "DBO": "Dubbo",
    "YSWG": "Wagga Wagga", "WGA": "Wagga Wagga",
    "YSTW": "Tamworth", "TMW": "Tamworth",
    "YARM": "Armidale", "ARM": "Armidale",
    "YORG": "Orange", "OAG": "Orange",
    "YMRY": "Moruya", "MYA": "Moruya",
    "YMER": "Merimbula", "MIM": "Merimbula",
    "YBHI": "Broken Hill", "BHQ": "Broken Hill",
    "YLHI": "Lord Howe Is", "LDH": "Lord Howe Is",
    "YGTH": "Griffith", "GFF": "Griffith",
    "YLIS": "Lismore", "LSY": "Lismore",
    "YDPO": "Devonport", "DPO": "Devonport",
    // International
    "NZAA": "Auckland", "NZCH": "Christchurch", "NZWN": "Wellington", "NZQN": "Queenstown",
    "AKL": "Auckland", "CHC": "Christchurch", "WLG": "Wellington", "ZQN": "Queenstown",
    "WSSS": "Singapore", "WSAP": "Singapore", "SIN": "Singapore",
    "VHHH": "Hong Kong", "HKG": "Hong Kong",
    "RJAA": "Tokyo", "RJTT": "Tokyo", "NRT": "Tokyo", "HND": "Tokyo",
    "RJBB": "Osaka", "RJOO": "Osaka", "KIX": "Osaka", "ITM": "Osaka",
    "RKSI": "Seoul", "RKSS": "Seoul", "ICN": "Seoul", "GMP": "Seoul",
    "RCTP": "Taipei", "RCSS": "Taipei", "TPE": "Taipei", "TSA": "Taipei",
    "VTBS": "Bangkok", "VTBD": "Bangkok", "BKK": "Bangkok", "DMK": "Bangkok",
    "WMKK": "Kuala Lumpur", "KUL": "Kuala Lumpur",
    "WADD": "Bali", "WIII": "Jakarta", "DPS": "Bali", "CGK": "Jakarta",
    "VMMC": "Macau", "MFM": "Macau",
    "VVTS": "Ho Chi Minh City", "SGN": "Ho Chi Minh City",
    "VVNB": "Hanoi", "HAN": "Hanoi",
    "VTCC": "Chiang Mai", "CNX": "Chiang Mai",
    "VTSP": "Phuket", "HKT": "Phuket",
    "RPLL": "Manila", "MNL": "Manila",
    "VDPP": "Phnom Penh", "PNH": "Phnom Penh",
    "VDSR": "Siem Reap", "REP": "Siem Reap",
    "KLAX": "Los Angeles", "LAX": "Los Angeles",
    "KSFO": "San Francisco", "SFO": "San Francisco",
    "KJFK": "New York", "JFK": "New York",
    "KEWR": "Newark", "EWR": "Newark",
    "KORD": "Chicago", "ORD": "Chicago",
    "KDFW": "Dallas", "DFW": "Dallas",
    "KIAH": "Houston", "IAH": "Houston",
    "KMIA": "Miami", "MIA": "Miami",
    "EGLL": "London", "EGKK": "London", "EGSS": "London", "EGLC": "London",
    "LHR": "London", "LGW": "London", "STN": "London", "LCY": "London", "LTN": "London",
    "LFPG": "Paris", "LFPO": "Paris", "CDG": "Paris", "ORY": "Paris",
    "EHAM": "Amsterdam", "AMS": "Amsterdam",
    "EDDF": "Frankfurt", "FRA": "Frankfurt",
    "EDDM": "Munich", "MUC": "Munich",
    "LEMD": "Madrid", "MAD": "Madrid",
    "LEBL": "Barcelona", "BCN": "Barcelona",
    "LIRF": "Rome", "LIMC": "Milan", "FCO": "Rome", "MXP": "Milan", "LIN": "Milan",
    "EGPH": "Edinburgh", "EGPF": "Glasgow", "EDI": "Edinburgh", "GLA": "Glasgow",
    "EIDW": "Dublin", "DUB": "Dublin",
    "EBBR": "Brussels", "BRU": "Brussels",
    "EKCH": "Copenhagen", "CPH": "Copenhagen",
    "ESSA": "Stockholm", "ARN": "Stockholm",
    "ENGM": "Oslo", "OSL": "Oslo",
    "EFHK": "Helsinki", "HEL": "Helsinki",
    "LSZH": "Zurich", "ZRH": "Zurich",
    "LSGG": "Geneva", "GVA": "Geneva",
    "LOWW": "Vienna", "VIE": "Vienna",
    "EPWA": "Warsaw", "WAW": "Warsaw",
    "LKPR": "Prague", "PRG": "Prague",
    "LHBP": "Budapest", "BUD": "Budapest",
    "LGAV": "Athens", "ATH": "Athens",
    "LTFM": "Istanbul", "LTBA": "Istanbul", "IST": "Istanbul", "SAW": "Istanbul",
]

struct AirportInfo: Codable {
    let iata: String
    let icao: String
    let name: String
    let latitude: Double
    let longitude: Double
}

private let defaultAirportsWithCoordinates: [AirportInfo] = [
    AirportInfo(iata: "SYD", icao: "YSSY", name: "Sydney", latitude: -33.9461, longitude: 151.177),
    AirportInfo(iata: "MEL", icao: "YMML", name: "Melbourne", latitude: -37.6733, longitude: 144.843),
    AirportInfo(iata: "BNE", icao: "YBBN", name: "Brisbane", latitude: -27.3842, longitude: 153.117),
    AirportInfo(iata: "PER", icao: "YPPH", name: "Perth", latitude: -31.9403, longitude: 115.967),
    AirportInfo(iata: "ADL", icao: "YPAD", name: "Adelaide", latitude: -34.945, longitude: 138.531),
    AirportInfo(iata: "CBR", icao: "YSCB", name: "Canberra", latitude: -35.3069, longitude: 149.195),
    AirportInfo(iata: "CNS", icao: "YBCS", name: "Cairns", latitude: -16.8858, longitude: 145.755),
    AirportInfo(iata: "OOL", icao: "YBCG", name: "Gold Coast", latitude: -28.1644, longitude: 153.505),
    AirportInfo(iata: "TSV", icao: "YBTL", name: "Townsville", latitude: -19.2525, longitude: 146.765),
    AirportInfo(iata: "DRW", icao: "YPDN", name: "Darwin", latitude: -12.4147, longitude: 130.877),
    AirportInfo(iata: "HBA", icao: "YMHB", name: "Hobart", latitude: -42.8361, longitude: 147.51),
    AirportInfo(iata: "LST", icao: "YMLT", name: "Launceston", latitude: -41.5456, longitude: 147.214),
]

class AirportDatabase {
    static let shared = AirportDatabase()

    private var lookupTable: [String: String] = [:]
    private var airportsList: [AirportInfo] = []
    private let lock = NSLock()

    private init() {
        loadCachedData()
        Task {
            await fetchIfNeeded()
        }
    }

    func airportName(for code: String) -> String? {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return lookupTable[cleaned]
    }

    func airportCoordinates(for code: String) -> CLLocationCoordinate2D? {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        return lock.withLock {
            if let airport = airportsList.first(where: { $0.iata == cleaned || $0.icao == cleaned }) {
                return CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
            }
            return nil
        }
    }

    struct ProjectedAirport {
        let name: String
        let code: String
        let point: NSPoint
    }

    // Projects coordinates using MapKit snapshot instance to check bounding box
    func projectedAirports(in snapshot: AnyObject, bounds: NSRect) -> [ProjectedAirport] {
        lock.lock()
        let list = airportsList
        lock.unlock()

        guard let mapSnapshot = snapshot as? MKMapSnapshotter.Snapshot else { return [] }

        var result: [ProjectedAirport] = []
        for airport in list {
            let coord = CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
            let point = mapSnapshot.point(for: coord)
            if bounds.contains(point) {
                let code = !airport.icao.isEmpty ? airport.icao : airport.iata
                result.append(ProjectedAirport(name: airport.name, code: code, point: point))
            }
        }
        return result
    }

    private var cacheFileURL: URL? {
        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let appCacheDir = cachesDir.appendingPathComponent("com.airabove.screensaver", isDirectory: true)
        try? fileManager.createDirectory(at: appCacheDir, withIntermediateDirectories: true, attributes: nil)
        return appCacheDir.appendingPathComponent("airports_cache_v2.json")
    }

    private func loadCachedData() {
        lock.lock()
        defer { lock.unlock() }

        // 1. Try loading from SPM package first (highest priority)
        if let bundle = findSPMBundle(named: "Ip2LocationIataIcao"),
           let csvURL = bundle.url(forResource: "iata-icao", withExtension: "csv"),
           let csvString = try? String(contentsOf: csvURL, encoding: .utf8) {
            
            let lines = csvString.components(separatedBy: .newlines)
            var list: [AirportInfo] = []
            var dict: [String: String] = [:]

            for line in lines {
                let cols = parseCSVRow(line)
                guard cols.count >= 7 else { continue }

                let iata = cols[2].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let icao = cols[3].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let airportRaw = cols[4]
                let latRaw = cols[5]
                let lonRaw = cols[6]

                guard let latitude = Double(latRaw),
                      let longitude = Double(lonRaw) else {
                    continue
                }

                let cleanName = cleanAirportName(airportRaw)
                guard !cleanName.isEmpty else { continue }

                let info = AirportInfo(iata: iata, icao: icao, name: cleanName, latitude: latitude, longitude: longitude)
                list.append(info)

                if !iata.isEmpty && iata != "IATA" {
                    dict[iata] = cleanName
                }
                if !icao.isEmpty && icao != "ICAO" {
                    dict[icao] = cleanName
                }
            }

            if !list.isEmpty {
                self.airportsList = list
                self.lookupTable = dict
                return
            }
        }

        // 2. Fall back to cached JSON file
        if let url = cacheFileURL,
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([AirportInfo].self, from: data) {
            self.airportsList = list
            var dict: [String: String] = [:]
            for airport in list {
                if !airport.iata.isEmpty { dict[airport.iata] = airport.name }
                if !airport.icao.isEmpty { dict[airport.icao] = airport.name }
            }
            self.lookupTable = dict
            return
        }

        // 3. Fall back to static defaults
        self.lookupTable = defaultAirports
        self.airportsList = defaultAirportsWithCoordinates
    }

    private func fetchIfNeeded() async {
        // No-op: all data is loaded locally from SPM package
    }

    private func cleanAirportName(_ rawName: String) -> String {
        var name = rawName
        if let range = name.range(of: "\\s*\\([^)]*\\)", options: .regularExpression) {
            name.removeSubrange(range)
        }
        let suffixes = [" International Airport", " Regional Airport", " Airport", " Intl Airport"]
        for suffix in suffixes {
            if name.lowercased().hasSuffix(suffix.lowercased()) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        let chars = Array(row)
        var i = 0
        while i < chars.count {
            let char = chars[i]
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
            i += 1
        }
        result.append(current)
        return result
    }
}

public final class AirlineDatabase: @unchecked Sendable {
    public static let shared = AirlineDatabase()

    private let lock = NSLock()
    private var icaoToName: [String: String] = [:]
    private var icaoToIata: [String: String] = [:]
    private var isLoaded = false

    private init() {
        loadCachedData()
        Task {
            await fetchRemoteData()
        }
    }

    public func airlineName(foricao icao: String) -> String? {
        let cleaned = icao.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        return lock.withLock { icaoToName[cleaned] }
    }

    public func iataCode(foricao icao: String) -> String? {
        let cleaned = icao.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        return lock.withLock { icaoToIata[cleaned] }
    }

    public func icaoCode(forIata iata: String) -> String? {
        let cleaned = iata.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleaned.isEmpty else { return nil }
        return lock.withLock {
            for (icao, iataCode) in icaoToIata {
                if iataCode == cleaned {
                    return icao
                }
            }
            return nil
        }
    }

    private var cacheFileURL: URL? {
        let fileManager = FileManager.default
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let appCacheDir = cachesDir.appendingPathComponent("com.airabove.screensaver", isDirectory: true)
        try? fileManager.createDirectory(at: appCacheDir, withIntermediateDirectories: true, attributes: nil)
        return appCacheDir.appendingPathComponent("airlines_cache_v1.json")
    }

    private func loadCachedData() {
        // 1. Try loading from SPM package first (highest priority)
        if let bundle = findSPMBundle(named: "IataUtils"),
           let csvURL = bundle.url(forResource: "iata_airlines", withExtension: "csv"),
           let csvString = try? String(contentsOf: csvURL, encoding: .utf8) {
            parseCSV(csvString)
            return
        }

        // 2. Fall back to cached JSON file
        guard let cacheURL = cacheFileURL,
              let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode(CacheStructure.self, from: data) else {
            return
        }

        lock.withLock {
            self.icaoToName = dict.icaoToName
            self.icaoToIata = dict.icaoToIata
            self.isLoaded = true
        }
    }

    private func fetchRemoteData() async {
        // No-op: all data is loaded locally from SPM package
    }

    private func parseCSV(_ csv: String) {
        var tempName: [String: String] = [:]
        var tempIata: [String: String] = [:]

        let lines = csv.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: "^")
            guard fields.count >= 3 else { continue }

            let iata = fields[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let icao = fields[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let name = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !icao.isEmpty else { continue }

            if !name.isEmpty {
                tempName[icao] = name
            }
            if !iata.isEmpty {
                tempIata[icao] = iata
            }
        }

        lock.withLock {
            self.icaoToName = tempName
            self.icaoToIata = tempIata
            self.isLoaded = true
        }

        if let cacheURL = cacheFileURL {
            let cacheObj = CacheStructure(icaoToName: tempName, icaoToIata: tempIata)
            if let data = try? JSONEncoder().encode(cacheObj) {
                try? data.write(to: cacheURL)
            }
        }
    }

    private struct CacheStructure: Codable {
        let icaoToName: [String: String]
        let icaoToIata: [String: String]
    }
}
