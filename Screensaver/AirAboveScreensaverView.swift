import AppKit
import Combine
import ScreenSaver
import AirAboveScreensaverCore
import os
import SwiftUI
import MapKit

private let screensaverLogger = Logger(subsystem: "com.airabove.screensaver", category: "screensaver")

@MainActor
class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        return false
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

@objc(AirAboveScreensaverView)
@MainActor
public final class AirAboveScreensaverView: ScreenSaverView, NSWindowDelegate {
    private let flightFeedClient = FlightFeedClient()
    private let routeHydrationController = RouteHydrationController()
    private let rotationController = RotationController(flights: [])
    private let viewModel: ScreensaverViewModel
    private let hostingView: TransparentHostingView<AirAboveScreensaverRootView>
    private var refreshTimer: Timer?
    private var rotationTimer: Timer?
    private var activeDataTask: URLSessionDataTask?
    private var routeHydrationTask: Task<Void, Never>?
    private var loadingWatchdog: DispatchWorkItem?
    private var requestSequence = 0
    private var currentFlights: [Flight] = []
    private var configSheetWindow: NSWindow?
    private let previewMode: Bool

    public override init?(frame: NSRect, isPreview: Bool) {
        previewMode = isPreview
        let viewModel = ScreensaverViewModel()
        let settings = SettingsManager.shared
        viewModel.homeLatitude = settings.latitude
        viewModel.homeLongitude = settings.longitude
        viewModel.geofenceRadiusKm = Double(settings.radiusNm) * 1.852
        self.viewModel = viewModel
        hostingView = TransparentHostingView(rootView: AirAboveScreensaverRootView(viewModel: viewModel))
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 30.0

        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        screensaverLogger.info("init preview=\(isPreview, privacy: .public)")
        startRefreshLoopIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func startAnimation() {
        screensaverLogger.info("startAnimation")
        super.startAnimation()
        startRefreshLoopIfNeeded()
    }

    public override func stopAnimation() {
        screensaverLogger.info("stopAnimation")
        refreshTimer?.invalidate()
        refreshTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        activeDataTask?.cancel()
        activeDataTask = nil
        routeHydrationTask?.cancel()
        routeHydrationTask = nil
        loadingWatchdog?.cancel()
        loadingWatchdog = nil
        super.stopAnimation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        screensaverLogger.info("viewDidMoveToWindow window=\(self.window != nil, privacy: .public)")
        startRefreshLoopIfNeeded()
        
        let scale = window?.backingScaleFactor ?? 2.0
        triggerMapSnapshot(width: bounds.width, height: bounds.height, scale: scale)
    }

    private func triggerMapSnapshot(width: CGFloat, height: CGFloat, scale: CGFloat) {
        let settings = SettingsManager.shared
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(
            latitude: settings.latitude,
            longitude: settings.longitude
        )
        let spanDelta = (Double(settings.radiusNm) * 2.4) / 60.0
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )
        options.size = NSSize(width: width, height: height)

        if #available(macOS 13.0, *) {
            switch settings.mapStyle {
            case .standard:
                let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
                configuration.pointOfInterestFilter = .excludingAll
                configuration.showsTraffic = false
                options.preferredConfiguration = configuration
            case .satellite:
                let configuration = MKImageryMapConfiguration(elevationStyle: .flat)
                options.preferredConfiguration = configuration
            case .hybrid:
                let configuration = MKHybridMapConfiguration(elevationStyle: .flat)
                configuration.pointOfInterestFilter = .excludingAll
                configuration.showsTraffic = false
                options.preferredConfiguration = configuration
            }
        } else {
            switch settings.mapStyle {
            case .standard:
                options.mapType = .mutedStandard
            case .satellite:
                options.mapType = .satellite
            case .hybrid:
                options.mapType = .hybrid
            }
        }

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    screensaverLogger.error("Map snapshot failed: \(error.localizedDescription)")
                    return
                }
                if let snapshot = snapshot {
                    screensaverLogger.info("Map snapshot succeeded")
                    self?.viewModel.mapSnapshot = snapshot
                    let bounds = NSRect(origin: .zero, size: snapshot.image.size)
                    let annotatedImage = self?.drawAirports(on: snapshot, bounds: bounds) ?? snapshot.image
                    self?.viewModel.backgroundImage = annotatedImage
                }
            }
        }
    }

    private func drawAirports(on snapshot: MKMapSnapshotter.Snapshot, bounds: NSRect) -> NSImage {
        let baseImage = snapshot.image
        let newImage = NSImage(size: baseImage.size)

        newImage.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: baseImage.size))

        let activeAirports = AirportDatabase.shared.projectedAirports(in: snapshot, bounds: bounds)

        for airport in activeAirports {
            let drawPoint = airport.point

            // Draw marker circle
            let markerSize: CGFloat = 20.0
            let markerRect = NSRect(
                x: drawPoint.x - markerSize / 2,
                y: drawPoint.y - markerSize / 2,
                width: markerSize,
                height: markerSize
            )

            let path = NSBezierPath(ovalIn: markerRect)
            // Premium light blue airport color
            NSColor(red: 0.18, green: 0.58, blue: 0.95, alpha: 0.9).setFill()
            path.fill()

            // Draw a subtle border
            NSColor.white.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1.5
            path.stroke()

            // Draw airplane symbol inside
            if let airplane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil) {
                let tintedAirplane = airplane.tinted(with: .white)
                let iconSize: CGFloat = 12.0
                let iconRect = NSRect(
                    x: drawPoint.x - iconSize / 2,
                    y: drawPoint.y - iconSize / 2,
                    width: iconSize,
                    height: iconSize
                )
                tintedAirplane.draw(in: iconRect)
            }

            // Draw airport name and code (e.g. "Sydney (YSSY)")
            let text = "\(airport.name) (\(airport.code))"
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .shadow: {
                    let s = NSShadow()
                    s.shadowColor = NSColor.black
                    s.shadowOffset = NSSize(width: 0, height: -1)
                    s.shadowBlurRadius = 2.0
                    return s
                }()
            ]

            let size = text.size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: drawPoint.x - size.width / 2,
                y: drawPoint.y - markerSize / 2 - size.height - 4
            )

            // Draw a tiny dark background capsule for the text to ensure legibility over any map terrain
            let bgRect = NSRect(
                x: textPoint.x - 4,
                y: textPoint.y - 2,
                width: size.width + 8,
                height: size.height + 4
            )
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
            NSColor.black.withAlphaComponent(0.6).setFill()
            bgPath.fill()

            text.draw(at: textPoint, withAttributes: attributes)
        }

        newImage.unlockFocus()
        return newImage
    }

    public func render(state: ScreensaverState) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            viewModel.state = state
        }
    }

    public override func draw(_ rect: NSRect) {
        // No-op: Drawing is handled entirely by layer-backed subviews
    }

    public override func animateOneFrame() {
        // No-op: Disable legacy animation tick redrawing, letting SwiftUI and MapKit manage frames
    }

    // Map delegation and renderer now handled natively by SwiftUI BackgroundMapView coordinator

    // MARK: - Screensaver Configuration Sheet
    
    public override var hasConfigureSheet: Bool {
        return true
    }
    
    public override var configureSheet: NSWindow? {
        if let existingWindow = configSheetWindow {
            return existingWindow
        }

        weak var weakSelf = self
        
        let settingsView = SettingsView(presentAsDraftSheet: true) {
            weakSelf?.dismissConfigureSheet()
        }
        .frame(width: 320, height: 460)
        
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.delegate = self
        window.isReleasedWhenClosed = true
        self.configSheetWindow = window
        
        return window
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window == configSheetWindow else { return }
        configSheetWindow = nil
        reloadSettingsAndSnapshot()
    }

    private func dismissConfigureSheet() {
        guard let window = configSheetWindow else { return }
        window.sheetParent?.endSheet(window)
    }
    
    private func reloadSettingsAndSnapshot() {
        let settings = SettingsManager.shared
        viewModel.homeLatitude = settings.latitude
        viewModel.homeLongitude = settings.longitude
        viewModel.geofenceRadiusKm = Double(settings.radiusNm) * 1.852
        
        let scale = window?.backingScaleFactor ?? 2.0
        triggerMapSnapshot(width: bounds.width, height: bounds.height, scale: scale)
        
        // Reset and rebuild timers with new configurations
        refreshTimer?.invalidate()
        refreshTimer = nil
        rotationTimer?.invalidate()
        rotationTimer = nil
        startRefreshLoopIfNeeded()
    }

    private func startRefreshLoopIfNeeded() {
        guard refreshTimer == nil || (previewMode && rotationTimer == nil) else { return }

        if previewMode {
            screensaverLogger.info("showing preview data")
            showPreviewData()
        } else {
            screensaverLogger.info("requesting flights immediately")
            requestFlights()
            
            let refreshInterval = SettingsManager.shared.refreshInterval
            let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestFlights()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        }

        if rotationTimer == nil {
            let rotationInterval = SettingsManager.shared.rotationInterval
            let timer = Timer(timeInterval: rotationInterval, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.advanceCard()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            rotationTimer = timer
        }
    }

    private func requestFlights() {
        requestSequence += 1
        let requestID = requestSequence
        let isRefreshingLiveContent = isShowingLiveContent

        activeDataTask?.cancel()
        routeHydrationTask?.cancel()
        loadingWatchdog?.cancel()
        loadingWatchdog = nil

        let url: URL
        let settings = SettingsManager.shared
        do {
            url = try FlightFeedRequest.flightsURL(
                baseURL: flightFeedClient.baseURL,
                homeLatitude: settings.latitude,
                homeLongitude: settings.longitude,
                radiusNm: settings.radiusNm
            )
            screensaverLogger.info("fetching flights url=\(url.absoluteString, privacy: .public)")
        } catch {
            screensaverLogger.error("failed to build flights url")
            if !isRefreshingLiveContent {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    viewModel.state = .offline(message: "Unable to load aircraft data")
                }
            }
            return
        }

        activeDataTask = flightFeedClient.session.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                guard self.requestSequence == requestID else { return }
                self.loadingWatchdog?.cancel()
                self.loadingWatchdog = nil

                if let urlError = error as? URLError, urlError.code == .cancelled {
                    return
                }

                if let error {
                    screensaverLogger.error("request failed error=\(error.localizedDescription, privacy: .public)")
                    if !isRefreshingLiveContent {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            self.viewModel.state = .offline(message: error.localizedDescription)
                        }
                    } else {
                        screensaverLogger.info("keeping existing live card after refresh failure")
                    }
                    return
                }

                guard let data else {
                    screensaverLogger.error("request completed without data")
                    if !isRefreshingLiveContent {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            self.viewModel.state = .offline(message: "Unable to load aircraft data")
                        }
                    } else {
                        screensaverLogger.info("keeping existing live card after empty refresh response")
                    }
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(ProxyFlightResponse.self, from: data)
                    let flights = decoded.flights
                    screensaverLogger.info("request succeeded flights=\(flights.count, privacy: .public)")
                    self.currentFlights = flights
                    let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
                    let insideCircleFlights = flights.filter { $0.isInsideGeofence(radiusKm: maxDistanceKm) }
                    self.rotationController.update(flights: insideCircleFlights)
                    self.updateState(with: flights)
                    self.viewModel.updateStats(with: flights)
                } catch {
                    screensaverLogger.error("decode failed error=\(error.localizedDescription, privacy: .public)")
                    if !isRefreshingLiveContent {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            self.viewModel.state = .offline(message: "Unable to load aircraft data")
                        }
                    } else {
                        screensaverLogger.info("keeping existing live card after decode failure")
                    }
                }
            }
        }

        activeDataTask?.resume()

        let watchdog = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.requestSequence == requestID else { return }
            guard self.viewModel.state == .loading else { return }
            screensaverLogger.info("loading watchdog expired")
            if !isRefreshingLiveContent {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    self.viewModel.state = .noFlights
                }
            } else {
                screensaverLogger.info("keeping existing live card after refresh watchdog expiry")
            }
        }
        loadingWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: watchdog)
    }

    private var isShowingLiveContent: Bool {
        if case .live = viewModel.state {
            return true
        }
        return false
    }

    private func updateState(with flights: [Flight], shouldHydrateRoutes: Bool = true) {
        viewModel.updateTrails(with: flights)

        guard let currentFlight = rotationController.currentFlight else {
            screensaverLogger.info("updateState no current flight total=\(flights.count, privacy: .public)")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                viewModel.state = .noFlights
            }
            return
        }

        let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
        let activeFlights = FlightOrderer.closestFirst(flights.filter { $0.isInsideGeofence(radiusKm: maxDistanceKm) })

        guard let index = activeFlights.firstIndex(where: { $0.id == currentFlight.id }) else {
            screensaverLogger.info(
                "updateState current flight missing id=\(currentFlight.id, privacy: .public) total=\(flights.count, privacy: .public)"
            )
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                viewModel.state = .noFlights
            }
            return
        }

        screensaverLogger.info(
            "updateState showing card=\(index + 1, privacy: .public)/\(activeFlights.count, privacy: .public) callsign=\(currentFlight.callsign, privacy: .public)"
        )
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            viewModel.state = .live(activeFlights, index: index)
        }

        if shouldHydrateRoutes {
            scheduleRouteHydration(flights: activeFlights, focusIndex: index)
        }
    }

    private func advanceCard() {
        let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
        let insideCircleCount = self.currentFlights.filter { $0.distanceKm <= maxDistanceKm }.count
        guard insideCircleCount > 1 else {
            screensaverLogger.info("advanceCard skipped insideCircleCount=\(insideCircleCount, privacy: .public)")
            return
        }

        let previousFlight = self.rotationController.currentFlight
        self.rotationController.advance()
        if let currentFlight = self.rotationController.currentFlight {
            screensaverLogger.info(
                "advanceCard previous=\(previousFlight?.callsign ?? "nil", privacy: .public) current=\(currentFlight.callsign, privacy: .public) total=\(self.currentFlights.count, privacy: .public)"
            )
        } else {
            screensaverLogger.info("advanceCard current flight became nil total=\(self.currentFlights.count, privacy: .public)")
        }
        self.updateState(with: self.currentFlights)
    }

    private func scheduleRouteHydration(flights: [Flight], focusIndex: Int) {
        guard !previewMode else { return }

        routeHydrationTask?.cancel()
        let requestID = requestSequence

        routeHydrationTask = Task { [weak self] in
            guard let self else { return }
            let hydrated = await self.routeHydrationController.hydrate(flights: flights, focusIndex: focusIndex)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.requestSequence == requestID else { return }

                self.currentFlights = hydrated
                let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
                let insideCircleFlights = hydrated.filter { $0.isInsideGeofence(radiusKm: maxDistanceKm) }
                self.rotationController.update(flights: insideCircleFlights)
                self.viewModel.updateStats(with: hydrated)
                self.updateState(with: hydrated, shouldHydrateRoutes: false)
            }
        }
    }

    private func showPreviewData() {
        let flights = [
            Flight(
                id: "preview-1",
                callsign: "QFA1",
                airline: "Qantas",
                aircraftType: "A332",
                registration: "VH-EBL",
                originCity: "Sydney",
                destinationCity: "Perth",
                altitudeFt: 36000,
                speedKt: 480,
                distanceKm: 2.4,
                phase: .cruising,
                squawk: nil
            ),
            Flight(
                id: "preview-2",
                callsign: "JQ42",
                airline: "Jetstar",
                aircraftType: "A320",
                registration: "VH-VQF",
                originCity: "Melbourne",
                destinationCity: "Gold Coast",
                altitudeFt: 12400,
                speedKt: 305,
                distanceKm: 4.8,
                phase: .descending,
                squawk: nil
            )
        ]

        let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
        let insideCircleFlights = flights.filter { $0.distanceKm <= maxDistanceKm }
        rotationController.update(flights: insideCircleFlights)
        currentFlights = flights
        updateState(with: flights, shouldHydrateRoutes: false)
    }
}

@MainActor
final class ScreensaverViewModel: ObservableObject {
    struct SessionStats {
        var uniqueAircraftHexes: Set<String> = []
        var maxCapacity: Int = 0
        var largestAircraftType: String = "None"
        var maxAltitudeFt: Int = 0
        var maxSpeedKt: Int = 0
        var maxDistanceOriginName: String = "None"
        var maxDistanceOriginKm: Double = 0.0
    }

    @Published var state: ScreensaverState = .loading
    @Published var backgroundImage: NSImage? = nil
    @Published var mapSnapshot: MKMapSnapshotter.Snapshot? = nil
    @Published var flightTrails: [String: [CLLocationCoordinate2D]] = [:]
    @Published var sessionStats = SessionStats()
    var homeLatitude: Double = FlightFeedClient.defaultHomeLatitude
    var homeLongitude: Double = FlightFeedClient.defaultHomeLongitude
    var geofenceRadiusKm: Double = Double(FlightFeedClient.defaultRadiusNm) * 1.852

    func updateStats(with flights: [Flight]) {
        var stats = sessionStats
        let maxDistanceCircleKm = geofenceRadiusKm

        for flight in flights {
            guard flight.isInsideGeofence(radiusKm: maxDistanceCircleKm) else { continue }

            let hex = flight.hex ?? flight.callsign
            stats.uniqueAircraftHexes.insert(hex)

            let capacity = flight.passengerCapacity
            if capacity > stats.maxCapacity {
                stats.maxCapacity = capacity
                stats.largestAircraftType = flight.aircraftType
            }

            if flight.altitudeFt > stats.maxAltitudeFt {
                stats.maxAltitudeFt = flight.altitudeFt
            }

            if flight.speedKt > stats.maxSpeedKt {
                stats.maxSpeedKt = flight.speedKt
            }

            if !flight.originCity.isEmpty && flight.originCity != "Unknown" {
                if let originCoords = AirportDatabase.shared.airportCoordinates(for: flight.originCity) {
                    let distance = Flight.distanceKm(
                        fromLatitude: homeLatitude,
                        longitude: homeLongitude,
                        toLatitude: originCoords.latitude,
                        longitude: originCoords.longitude
                    )
                    if distance > stats.maxDistanceOriginKm {
                        stats.maxDistanceOriginKm = distance
                        stats.maxDistanceOriginName = AirportDatabase.shared.airportName(for: flight.originCity) ?? flight.originCity
                    }
                }
            }
        }
        self.sessionStats = stats
    }

    func updateTrails(with flights: [Flight]) {
        var newTrails: [String: [CLLocationCoordinate2D]] = [:]
        for flight in flights {
            guard let lat = flight.latitude, let lon = flight.longitude else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

            var existing = flightTrails[flight.id] ?? []
            if let last = existing.last, last.latitude == lat, last.longitude == lon {
                // No-op to avoid duplicates
            } else {
                existing.append(coord)
            }

            if existing.count > 30 {
                existing.removeFirst(existing.count - 30)
            }
            newTrails[flight.id] = existing
        }
        self.flightTrails = newTrails
    }

    func mapHeadingDegrees(for flight: Flight) -> Double {
        let heading: Double = {
            if let track = flight.track {
                return track
            }

            guard let trail = flightTrails[flight.id], trail.count >= 2,
                  let previous = trail.dropLast().last,
                  let current = trail.last else {
                return 0.0
            }

            return Flight.bearingDegrees(
                fromLatitude: previous.latitude,
                longitude: previous.longitude,
                toLatitude: current.latitude,
                longitude: current.longitude
            )
        }()

        screensaverLogger.error("mapHeadingDegrees callsign=\(flight.callsign, privacy: .public) track=\(flight.track ?? -999.0, privacy: .public) heading=\(heading, privacy: .public)")
        return heading - 90
    }
}

@MainActor
struct CardOverlayView: View {
    @ObservedObject var viewModel: ScreensaverViewModel

    var body: some View {
        switch viewModel.state {
        case .loading:
            LoadingStatusView()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .noFlights:
            NoFlightsStatusView()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .offline(let message):
            OfflineStatusView(message: message)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        case .live(let flights, let index):
            if flights.indices.contains(index) {
                let flight = flights[index]
                let alignToRight = (flight.longitude ?? 0.0) < viewModel.homeLongitude

                ZStack {
                    HStack {
                        if alignToRight {
                            Spacer()
                        }

                        FlightCardView(
                            flight: flight,
                            positionText: "\(index + 1) / \(flights.count)"
                        )
                        .padding(.horizontal, 80)

                        if !alignToRight {
                            Spacer()
                        }
                    }
                    .id(flight.id)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.98))
                                .combined(with: .offset(x: alignToRight ? 50 : -50)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98))
                                .combined(with: .offset(x: alignToRight ? -50 : 50))
                        )
                    )
                }
            } else {
                NoFlightsStatusView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

struct MapSnapshotView: View {
    @ObservedObject var viewModel: ScreensaverViewModel

    var body: some View {
        GeometryReader { geometry in
            let minDimension = min(geometry.size.width, geometry.size.height)
            ZStack {
                if let bgImage = viewModel.backgroundImage {
                    Image(nsImage: bgImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }

                // Draw circular geofence ring in the center of the screen
                Circle()
                    .stroke(Color.orange.opacity(0.35), lineWidth: 2)
                    .frame(width: minDimension * 0.72, height: minDimension * 0.72)

                if let mapSnapshot = viewModel.mapSnapshot {
                    let activeId: String? = {
                        if case .live(let flights, let index) = viewModel.state, flights.indices.contains(index) {
                            return flights[index].id
                        }
                        return nil
                    }()

                    // 1. Draw trailing paths in aviation yellow with a smooth gradient opacity (fading out towards the tail)
                    ForEach(Array(viewModel.flightTrails.keys), id: \.self) { flightId in
                         if let trail = viewModel.flightTrails[flightId], trail.count > 1 {
                             let points = trail.map { coord -> CGPoint in
                                 let pt = mapSnapshot.point(for: coord)
                                 return CGPoint(x: pt.x, y: geometry.size.height - pt.y)
                             }
                             
                             let tail = points.first ?? .zero
                             let nose = points.last ?? .zero
                             
                             let startPoint = UnitPoint(
                                 x: geometry.size.width > 0 ? tail.x / geometry.size.width : 0.5,
                                 y: geometry.size.height > 0 ? tail.y / geometry.size.height : 0.5
                             )
                             let endPoint = UnitPoint(
                                 x: geometry.size.width > 0 ? nose.x / geometry.size.width : 0.5,
                                 y: geometry.size.height > 0 ? nose.y / geometry.size.height : 0.5
                             )
                             
                             Path { path in
                                 path.move(to: tail)
                                 for point in points.dropFirst() {
                                     path.addLine(to: point)
                                 }
                             }
                             .stroke(
                                 LinearGradient(
                                     colors: [Color.yellow.opacity(0.0), Color.yellow.opacity(0.65)],
                                     startPoint: startPoint,
                                     endPoint: endPoint
                                 ),
                                 style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                             )
                         }
                    }

                    // 2. Draw anchor line from the featured plane to the card position (in black/grey).
                    if case .live(let flights, _) = viewModel.state,
                       let activeFlight = flights.first(where: {
                           $0.id == activeId && $0.isInsideGeofence(radiusKm: viewModel.geofenceRadiusKm)
                       }),
                       let lat = activeFlight.latitude, let lon = activeFlight.longitude {
                        let pt = mapSnapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        let projectedY = geometry.size.height - pt.y
                        let alignToRight = (activeFlight.longitude ?? 0.0) < viewModel.homeLongitude
                        let cardAnchorX = alignToRight ? (geometry.size.width - 80 - 240) : (80 + 240)
                        let cardAnchor = CGPoint(x: cardAnchorX, y: geometry.size.height / 2)

                        Path { path in
                            path.move(to: CGPoint(x: pt.x, y: projectedY))
                            path.addLine(to: cardAnchor)
                        }
                        .stroke(
                            Color.black.opacity(0.65),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                    }

                    // Draw plane icons oriented to their actual motion when history exists.
                    if case .live(let flights, _) = viewModel.state {
                        ForEach(flights, id: \.id) { flight in
                            if let lat = flight.latitude, let lon = flight.longitude {
                                let pt = mapSnapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                                let projectedY = geometry.size.height - pt.y
                                let isActive = flight.id == activeId && flight.isInsideGeofence(radiusKm: viewModel.geofenceRadiusKm)

                                ZStack {
                                    if isActive {
                                        Circle()
                                            .fill(Color.yellow.opacity(0.25))
                                            .frame(width: 32, height: 32)
                                    }

                                    Image(systemName: "airplane")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: isActive ? 22 : 16, height: isActive ? 22 : 16)
                                        .foregroundColor(Color.yellow)
                                        .rotationEffect(.degrees(viewModel.mapHeadingDegrees(for: flight)))
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                                    Text(flight.callsign)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.black.opacity(0.65))
                                        .cornerRadius(3)
                                        .offset(y: isActive ? -22 : -18)
                                }
                                .position(x: pt.x, y: projectedY)
                            }
                        }
                    }
                }

                // Home marker pin in the center (Standard Apple user location blue/white dot)
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

@MainActor
struct AirAboveScreensaverRootView: View {
    @ObservedObject var viewModel: ScreensaverViewModel

    var body: some View {
        ZStack {
            MapSnapshotView(viewModel: viewModel)
                .ignoresSafeArea()

            CardOverlayView(viewModel: viewModel)

            if shouldShowStats {
                VStack {
                    HStack {
                        SessionStatsCardView(stats: viewModel.sessionStats)
                            .padding(.top, 40)
                            .padding(.leading, 40)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .background(Color.clear)
    }

    private var shouldShowStats: Bool {
        switch viewModel.state {
        case .live, .noFlights:
            return true
        default:
            return false
        }
    }
}

struct SessionStatsCardView: View {
    let stats: ScreensaverViewModel.SessionStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHILE YOU WERE AWAY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .tracking(1.5)

            Text("\(stats.uniqueAircraftHexes.count) Aircraft")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 2)

            Divider()
                .background(Color.white.opacity(0.15))
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Largest:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .leading)
                    Text(stats.largestAircraftType != "None" ? stats.largestAircraftType : "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    Text("Highest:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .leading)
                    Text(stats.maxAltitudeFt > 0 ? "FL\(stats.maxAltitudeFt / 100)" : "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    Text("Fastest:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .leading)
                    Text(stats.maxSpeedKt > 0 ? "\(stats.maxSpeedKt) kts" : "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 8) {
                    Text("Furthest:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .leading)
                    Text(stats.maxDistanceOriginName != "None" ? "\(stats.maxDistanceOriginName)" : "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 210)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let tintedImage = NSImage(size: size)
        tintedImage.lockFocus()
        
        let rect = NSRect(origin: .zero, size: size)
        draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        color.set()
        rect.fill(using: .sourceAtop)
        
        tintedImage.unlockFocus()
        return tintedImage
    }
}
