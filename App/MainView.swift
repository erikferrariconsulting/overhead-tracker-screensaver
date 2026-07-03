import SwiftUI
import MapKit
import OverheadTrackerScreensaverCore

struct MainView: View {
    @StateObject private var viewModel = ScreensaverViewModel()
    @State private var showingSettings = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""
    @State private var currentFlights: [Flight] = []
    
    private let flightFeedClient = FlightFeedClient()
    private let rotationController = RotationController(flights: [])
    
    // Timers
    private let refreshTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    private let rotationTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            // Re-use MapSnapshotView
            MapSnapshotView(viewModel: viewModel)
                .ignoresSafeArea()
            
            // Re-use CardOverlayView
            CardOverlayView(viewModel: viewModel)
            
            // Session Stats Card Overlay
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
            
            // Top Right Controls (Settings/Installer toggle)
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            showingSettings.toggle()
                        }
                    }) {
                        Image(systemName: showingSettings ? "xmark.circle.fill" : "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .padding(.trailing, 20)
                }
                Spacer()
            }
            
            // Settings and Installer Drawer
            if showingSettings {
                HStack {
                    Spacer()
                    installerSettingsPanel
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                .background(Color.black.opacity(0.3).onTapGesture {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showingSettings = false
                    }
                })
            }
        }
        .frame(minWidth: 1024, minHeight: 768)
        .onAppear {
            setupInitialState()
        }
        .onReceive(refreshTimer) { _ in
            requestFlights()
        }
        .onReceive(rotationTimer) { _ in
            advanceCard()
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private var shouldShowStats: Bool {
        switch viewModel.state {
        case .live, .noFlights:
            return true
        default:
            return false
        }
    }
    
    // Initial setup
    private func setupInitialState() {
        viewModel.homeLatitude = flightFeedClient.homeLatitude
        viewModel.homeLongitude = flightFeedClient.homeLongitude
        viewModel.geofenceRadiusKm = Double(flightFeedClient.radiusNm) * 1.852
        
        // Trigger map snapshot
        triggerMapSnapshot()
        
        // Initial flight request
        requestFlights()
    }
    
    // Map snapshot drawing
    private func triggerMapSnapshot() {
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(
            latitude: flightFeedClient.homeLatitude,
            longitude: flightFeedClient.homeLongitude
        )
        let spanDelta = (Double(flightFeedClient.radiusNm) * 2.4) / 60.0
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )
        options.size = CGSize(width: 1024, height: 768) // Base size
        
        if #available(macOS 13.0, *) {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            configuration.pointOfInterestFilter = .excludingAll
            configuration.showsTraffic = false
            options.preferredConfiguration = configuration
        } else {
            options.mapType = .mutedStandard
        }
        
        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start { snapshot, error in
            DispatchQueue.main.async {
                guard error == nil, let snapshot = snapshot else { return }
                viewModel.mapSnapshot = snapshot
                let bounds = NSRect(origin: .zero, size: snapshot.image.size)
                let annotatedImage = drawAirports(on: snapshot, bounds: bounds)
                viewModel.backgroundImage = annotatedImage
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
            let markerSize: CGFloat = 20.0
            let markerRect = NSRect(
                x: drawPoint.x - markerSize / 2,
                y: drawPoint.y - markerSize / 2,
                width: markerSize,
                height: markerSize
            )
            
            let path = NSBezierPath(ovalIn: markerRect)
            NSColor(red: 0.18, green: 0.58, blue: 0.95, alpha: 0.9).setFill()
            path.fill()
            
            NSColor.white.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1.5
            path.stroke()
            
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
    
    // Fetch live flights
    private func requestFlights() {
        let isRefreshingLiveContent = isShowingLiveContent
        
        Task {
            do {
                let flights = try await flightFeedClient.fetchFlights()
                
                await MainActor.run {
                    self.currentFlights = flights
                    let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
                    let insideCircleFlights = flights.filter { $0.isInsideGeofence(radiusKm: maxDistanceKm) }
                    
                    self.rotationController.update(flights: insideCircleFlights)
                    self.updateState(with: flights)
                    self.viewModel.updateStats(with: flights)
                }
            } catch {
                await MainActor.run {
                    if !isRefreshingLiveContent {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            self.viewModel.state = .offline(message: error.localizedDescription)
                        }
                    }
                }
            }
        }
    }
    
    private var isShowingLiveContent: Bool {
        if case .live = viewModel.state {
            return true
        }
        return false
    }
    
    private func updateState(with flights: [Flight]) {
        viewModel.updateTrails(with: flights)
        
        guard let currentFlight = rotationController.currentFlight else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                viewModel.state = .noFlights
            }
            return
        }
        
        let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
        let activeFlights = FlightOrderer.closestFirst(flights.filter { $0.isInsideGeofence(radiusKm: maxDistanceKm) })
        
        guard let index = activeFlights.firstIndex(where: { $0.id == currentFlight.id }) else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                viewModel.state = .noFlights
            }
            return
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            viewModel.state = .live(activeFlights, index: index)
        }
    }
    
    private func advanceCard() {
        let maxDistanceKm = Double(self.flightFeedClient.radiusNm) * 1.852
        let insideCircleCount = self.currentFlights.filter { $0.distanceKm <= maxDistanceKm }.count
        guard insideCircleCount > 1 else { return }
        
        self.rotationController.advance()
        self.updateState(with: self.currentFlights)
    }
    
    // Installer Settings Drawer View
    private var installerSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("OVERHEAD TRACKER")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .tracking(2.0)
            
            Text("Screen Saver Companion")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Enjoy real-time aircraft tracking directly on your desktop or install it as your system screensaver.")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
                .background(Color.white.opacity(0.15))
            
            // Installation Steps (Instruction panel similar to FlipClock UI)
            VStack(alignment: .leading, spacing: 14) {
                Text("INSTALLATION INSTRUCTIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1.5)
                
                HStack(alignment: .top, spacing: 10) {
                    Text("1")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 18, height: 18)
                        .background(Color.orange)
                        .clipShape(Circle())
                    
                    Text("Click the **Install Screensaver** button below. The screensaver bundle will be exported to your **Downloads** directory.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                HStack(alignment: .top, spacing: 10) {
                    Text("2")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(width: 18, height: 18)
                        .background(Color.orange)
                        .clipShape(Circle())
                    
                    Text("Double-click `OverheadTrackerScreensaver.saver` inside your Downloads folder to install it in macOS System Settings.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            
            Spacer()
            
            // Install Button
            Button(action: {
                do {
                    try ScreensaverInstaller.install()
                    alertTitle = "Success!"
                    alertMessage = "The screensaver has been copied to your Downloads folder and the installer has been launched."
                    showingAlert = true
                } catch {
                    alertTitle = "Installation Failed"
                    alertMessage = error.localizedDescription
                    showingAlert = true
                }
            }) {
                HStack {
                    Spacer()
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Install Screensaver")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(width: 380)
        .background(
            Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.95)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1),
            alignment: .leading
        )
    }
}
