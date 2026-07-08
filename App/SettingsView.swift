import SwiftUI
import MapKit
import Combine
import AirAboveScreensaverCore

@MainActor
private struct SettingsDraft {
    var locationMode: LocationMode
    var latitude: Double
    var longitude: Double
    var radiusNm: Int
    var refreshInterval: Double
    var rotationInterval: Double
    var mapStyle: RadarMapStyle

    init(settings: SettingsManager) {
        locationMode = settings.locationMode
        latitude = settings.latitude
        longitude = settings.longitude
        radiusNm = settings.radiusNm
        refreshInterval = settings.refreshInterval
        rotationInterval = settings.rotationInterval
        mapStyle = settings.mapStyle
    }

    func apply(to settings: SettingsManager) {
        settings.locationMode = locationMode
        settings.latitude = latitude
        settings.longitude = longitude
        settings.radiusNm = radiusNm
        settings.refreshInterval = refreshInterval
        settings.rotationInterval = rotationInterval
        settings.mapStyle = mapStyle
    }
}

@MainActor
public final class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    
    @Published public var searchQuery = ""
    @Published public var completions: [MKLocalSearchCompletion] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        
        $searchQuery
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.isEmpty {
                    self.completions = []
                } else {
                    self.completer.queryFragment = query
                }
            }
            .store(in: &cancellables)
    }
    
    public func selectCompletion(_ completion: MKLocalSearchCompletion, completionHandler: @escaping (CLLocationCoordinate2D?) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            guard error == nil, let coordinate = response?.mapItems.first?.placemark.coordinate else {
                completionHandler(nil)
                return
            }
            completionHandler(coordinate)
        }
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    nonisolated public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor in
            self.completions = results
        }
    }
    
    nonisolated public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Local search completer failed: \(error.localizedDescription)")
    }
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @StateObject private var searchViewModel = LocationSearchViewModel()
    @State private var draft: SettingsDraft
    @FocusState private var searchFieldFocused: Bool
    
    @State private var latText = ""
    @State private var lonText = ""
    @State private var showSearchList = false
    
    private let presentAsDraftSheet: Bool
    var onDismiss: (() -> Void)? = nil

    init(presentAsDraftSheet: Bool = false, onDismiss: (() -> Void)? = nil) {
        self.presentAsDraftSheet = presentAsDraftSheet
        self.onDismiss = onDismiss
        _draft = State(initialValue: SettingsDraft(settings: SettingsManager.shared))
    }

    private var locationModeBinding: Binding<LocationMode> {
        if presentAsDraftSheet {
            return $draft.locationMode
        }
        return Binding(
            get: { settings.locationMode },
            set: { settings.locationMode = $0 }
        )
    }

    private var latitudeBinding: Binding<Double> {
        if presentAsDraftSheet {
            return $draft.latitude
        }
        return Binding(
            get: { settings.latitude },
            set: { settings.latitude = $0 }
        )
    }

    private var longitudeBinding: Binding<Double> {
        if presentAsDraftSheet {
            return $draft.longitude
        }
        return Binding(
            get: { settings.longitude },
            set: { settings.longitude = $0 }
        )
    }

    private var radiusBinding: Binding<Int> {
        if presentAsDraftSheet {
            return $draft.radiusNm
        }
        return Binding(
            get: { settings.radiusNm },
            set: { settings.radiusNm = $0 }
        )
    }

    private var refreshIntervalBinding: Binding<Double> {
        if presentAsDraftSheet {
            return $draft.refreshInterval
        }
        return Binding(
            get: { settings.refreshInterval },
            set: { settings.refreshInterval = $0 }
        )
    }

    private var rotationIntervalBinding: Binding<Double> {
        if presentAsDraftSheet {
            return $draft.rotationInterval
        }
        return Binding(
            get: { settings.rotationInterval },
            set: { settings.rotationInterval = $0 }
        )
    }

    private var mapStyleBinding: Binding<RadarMapStyle> {
        if presentAsDraftSheet {
            return $draft.mapStyle
        }
        return Binding(
            get: { settings.mapStyle },
            set: { settings.mapStyle = $0 }
        )
    }
    
    var body: some View {
        Group {
            if presentAsDraftSheet {
                nativeSheetBody
            } else {
                customSettingsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if presentAsDraftSheet {
                draft = SettingsDraft(settings: settings)
            }
            latText = String(format: "%.5f", presentAsDraftSheet ? draft.latitude : settings.latitude)
            lonText = String(format: "%.5f", presentAsDraftSheet ? draft.longitude : settings.longitude)
            searchFieldFocused = presentAsDraftSheet && locationModeBinding.wrappedValue == .custom
        }
        .onChange(of: locationModeBinding.wrappedValue) { _, newValue in
            if presentAsDraftSheet {
                searchFieldFocused = newValue == .custom
            }
        }
        .onExitCommand {
            if presentAsDraftSheet {
                onDismiss?()
            }
        }
    }

    private var nativeSheetBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Radar Configuration")
                .font(.title3.weight(.semibold))

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Radar Location")
                            .font(.headline)

                        Picker("Location Mode", selection: locationModeBinding) {
                            Text("Automatic (GPS)").tag(LocationMode.gps)
                            Text("Custom Coords").tag(LocationMode.custom)
                        }
                        .pickerStyle(.segmented)

                        if locationModeBinding.wrappedValue == .custom {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Search Location", text: $searchViewModel.searchQuery, onEditingChanged: { isEditing in
                                    showSearchList = isEditing || !searchViewModel.searchQuery.isEmpty
                                })
                                .textFieldStyle(.roundedBorder)
                                .focused($searchFieldFocused)

                                if showSearchList && !searchViewModel.completions.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(searchViewModel.completions.prefix(5), id: \.self) { completion in
                                            Button(action: { selectCompletion(completion) }) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(completion.title)
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text(completion.subtitle)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            if completion != searchViewModel.completions.prefix(5).last {
                                                Divider()
                                            }
                                        }
                                    }
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                                }

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Latitude")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("-33.77490", text: $latText)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: latText) { _, newValue in
                                                if let val = Double(newValue) {
                                                    latitudeBinding.wrappedValue = val
                                                }
                                            }
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Longitude")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("151.28783", text: $lonText)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: lonText) { _, newValue in
                                                if let val = Double(newValue) {
                                                    longitudeBinding.wrappedValue = val
                                                }
                                            }
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Radar Settings")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Radar Range")
                                Spacer()
                                Text("\(radiusBinding.wrappedValue) NM")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(
                                get: { Double(radiusBinding.wrappedValue) },
                                set: { radiusBinding.wrappedValue = Int($0) }
                            ), in: 10...100, step: 5)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Telemetry Update Frequency")
                                Spacer()
                                Text("\(Int(refreshIntervalBinding.wrappedValue)) seconds")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: refreshIntervalBinding, in: 5...30, step: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Flight Card Rotation Time")
                                Spacer()
                                Text("\(Int(rotationIntervalBinding.wrappedValue)) seconds")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: rotationIntervalBinding, in: 5...30, step: 1)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Map Style")
                            .font(.headline)

                        Picker("Style", selection: mapStyleBinding) {
                            ForEach(RadarMapStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(.top, 2)
                .padding(.trailing, 2)
                .padding(.bottom, 4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss?()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    draft.apply(to: settings)
                    onDismiss?()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var customSettingsBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("Radar Configurations")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if !presentAsDraftSheet, let onDismiss = onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white.opacity(0.6))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // Section 1: Location settings
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RADAR LOCATION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange.opacity(0.8))
                            .tracking(1.5)
                        
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    locationModeBinding.wrappedValue = .gps
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: locationModeBinding.wrappedValue == .gps ? "location.fill" : "location")
                                    Text("Automatic (GPS)")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(locationModeBinding.wrappedValue == .gps ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(locationModeBinding.wrappedValue == .gps ? Color.blue.opacity(0.85) : Color.white.opacity(0.06))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    locationModeBinding.wrappedValue = .custom
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: locationModeBinding.wrappedValue == .custom ? "mappin.circle.fill" : "mappin.circle")
                                    Text("Custom Coords")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(locationModeBinding.wrappedValue == .custom ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(locationModeBinding.wrappedValue == .custom ? Color.blue.opacity(0.85) : Color.white.opacity(0.06))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if locationModeBinding.wrappedValue == .custom {
                            VStack(alignment: .leading, spacing: 10) {
                                // Search Completer
                                Text("Search Location")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.white.opacity(0.5))
                                    TextField("e.g. Heathrow Airport", text: $searchViewModel.searchQuery, onEditingChanged: { isEditing in
                                        showSearchList = isEditing || !searchViewModel.searchQuery.isEmpty
                                    })
                                    .textFieldStyle(.plain)
                                    .foregroundColor(.white)
                                    .focused($searchFieldFocused)
                                    
                                    if !searchViewModel.searchQuery.isEmpty {
                                        Button(action: {
                                            searchViewModel.searchQuery = ""
                                            showSearchList = false
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15), lineWidth: 1))
                                
                                // Autocomplete dropdown results list
                                if showSearchList && !searchViewModel.completions.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(searchViewModel.completions.prefix(5), id: \.self) { completion in
                                            Button(action: {
                                                selectCompletion(completion)
                                            }) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(completion.title)
                                                        .font(.system(size: 11, weight: .bold))
                                                        .foregroundColor(.white)
                                                    Text(completion.subtitle)
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.white.opacity(0.6))
                                                }
                                                .padding(.vertical, 6)
                                                .padding(.horizontal, 8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            Divider()
                                                .background(Color.white.opacity(0.1))
                                        }
                                    }
                                    .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                                }
                                
                                // Lat Long TextFields
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Latitude")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            TextField("-33.77490", text: $latText)
                                                .textFieldStyle(.roundedBorder)
                                                .onChange(of: latText) { oldValue, newValue in
                                                    if let val = Double(newValue) {
                                                        latitudeBinding.wrappedValue = val
                                                    }
                                                }
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Longitude")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.6))
                                            TextField("151.28783", text: $lonText)
                                                .textFieldStyle(.roundedBorder)
                                                .onChange(of: lonText) { oldValue, newValue in
                                                    if let val = Double(newValue) {
                                                        longitudeBinding.wrappedValue = val
                                                    }
                                                }
                                    }
                                }
                            }
                            .padding(.leading, 4)
                            .transition(.opacity)
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.15))
                    
                    // Section 2: Range & Speed configurations
                    VStack(alignment: .leading, spacing: 14) {
                        Text("RADAR SETTINGS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange.opacity(0.8))
                            .tracking(1.5)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Radar Range")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(radiusBinding.wrappedValue) NM")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: Binding(
                                get: { Double(radiusBinding.wrappedValue) },
                                set: { radiusBinding.wrappedValue = Int($0) }
                            ), in: 10...100, step: 5)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Telemetry Update Frequency")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(refreshIntervalBinding.wrappedValue)) seconds")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: refreshIntervalBinding, in: 5...30, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Flight Card Rotation Time")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(rotationIntervalBinding.wrappedValue)) seconds")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: rotationIntervalBinding, in: 5...30, step: 1)
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.15))
                    
                    // Section 3: Map Style configuration
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MAP STYLE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange.opacity(0.8))
                            .tracking(1.5)
                        
                        Picker("Style", selection: mapStyleBinding) {
                            ForEach(RadarMapStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(.trailing, 8)
            }

            if presentAsDraftSheet {
                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") {
                        onDismiss?()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .keyboardShortcut(.cancelAction)

                    Button("OK") {
                        draft.apply(to: settings)
                        onDismiss?()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.98))
        .colorScheme(.dark)
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        searchViewModel.selectCompletion(completion) { coordinate in
            guard let coordinate = coordinate else { return }
            DispatchQueue.main.async {
                if presentAsDraftSheet {
                    draft.locationMode = .custom
                    draft.latitude = coordinate.latitude
                    draft.longitude = coordinate.longitude
                } else {
                    settings.locationMode = .custom
                    settings.latitude = coordinate.latitude
                    settings.longitude = coordinate.longitude
                }
                latText = String(format: "%.5f", coordinate.latitude)
                lonText = String(format: "%.5f", coordinate.longitude)
                searchViewModel.searchQuery = ""
                showSearchList = false
            }
        }
    }
}
