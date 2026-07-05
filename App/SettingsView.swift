import SwiftUI
import MapKit
import Combine
import OverheadTrackerScreensaverCore

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
    
    @State private var latText = ""
    @State private var lonText = ""
    @State private var showSearchList = false
    
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("Radar Configurations")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if let onDismiss = onDismiss {
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
                                    settings.locationMode = .gps
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: settings.locationMode == .gps ? "location.fill" : "location")
                                    Text("Automatic (GPS)")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(settings.locationMode == .gps ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.locationMode == .gps ? Color.blue.opacity(0.85) : Color.white.opacity(0.06))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    settings.locationMode = .custom
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: settings.locationMode == .custom ? "mappin.circle.fill" : "mappin.circle")
                                    Text("Custom Coords")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(settings.locationMode == .custom ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(settings.locationMode == .custom ? Color.blue.opacity(0.85) : Color.white.opacity(0.06))
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if settings.locationMode == .custom {
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
                                                    settings.latitude = val
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
                                                    settings.longitude = val
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
                                Text("\(settings.radiusNm) NM")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: Binding(
                                get: { Double(settings.radiusNm) },
                                set: { settings.radiusNm = Int($0) }
                            ), in: 10...100, step: 5)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Telemetry Update Frequency")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(settings.refreshInterval)) seconds")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $settings.refreshInterval, in: 5...30, step: 1)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Flight Card Rotation Time")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(settings.rotationInterval)) seconds")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            Slider(value: $settings.rotationInterval, in: 5...30, step: 1)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.98))
        .colorScheme(.dark)
        .onAppear {
            latText = String(format: "%.5f", settings.latitude)
            lonText = String(format: "%.5f", settings.longitude)
        }
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        searchViewModel.selectCompletion(completion) { coordinate in
            guard let coordinate = coordinate else { return }
            DispatchQueue.main.async {
                settings.latitude = coordinate.latitude
                settings.longitude = coordinate.longitude
                latText = String(format: "%.5f", coordinate.latitude)
                lonText = String(format: "%.5f", coordinate.longitude)
                searchViewModel.searchQuery = ""
                showSearchList = false
            }
        }
    }
}
