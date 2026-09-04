//
//  MapView.swift
//  invis
//
//  Liquid Glass MapKit View for iOS.
//  Strictly conforms to iOS Human Interface Guidelines:
//  Subtle specular borders, translucent ultra-thin materials,
//  clean typography, semantic SF Symbols, and zero emojis.
//

import SwiftUI
import MapKit
import Combine

// MARK: - Search Completer Observable Object
@MainActor
public final class MapSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published public var queryFragment: String = ""
    @Published public var suggestions: [MKLocalSearchCompletion] = []
    @Published public var isSearching: Bool = false

    private let completer = MKLocalSearchCompleter()
    private var cancellable: AnyCancellable?

    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]

        cancellable = $queryFragment
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.suggestions = []
                    self.isSearching = false
                    self.completer.cancel()
                } else {
                    self.isSearching = true
                    self.completer.queryFragment = query
                }
            }
    }

    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.suggestions = completer.results
        self.isSearching = false
    }

    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        self.isSearching = false
    }

    public func selectSuggestion(_ suggestion: MKLocalSearchCompletion, completion: @escaping (CLLocationCoordinate2D?, String) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: suggestion)
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, _ in
            if let coordinate = response?.mapItems.first?.placemark.coordinate {
                completion(coordinate, suggestion.title)
            } else {
                completion(nil, suggestion.title)
            }
        }
    }
}

// MARK: - Map View
public struct MapView: View {
    @Binding public var targetCoordinate: CLLocationCoordinate2D
    @Binding public var targetAltitude: Double
    public var routeCoordinates: [CLLocationCoordinate2D]
    public var showBottomInfoBar: Bool

    @ObservedObject var connectionManager: WiredConnectionManager = .shared
    @StateObject private var searchCompleter = MapSearchCompleter()

    // Map camera state
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020),
            distance: 2200,
            heading: 0,
            pitch: 0
        )
    )
    @State private var is3DPitchEnabled: Bool = false
    @State private var isPulsingPin: Bool = false

    public init(
        targetCoordinate: Binding<CLLocationCoordinate2D>,
        targetAltitude: Binding<Double> = .constant(15.0),
        routeCoordinates: [CLLocationCoordinate2D] = [],
        showBottomInfoBar: Bool = true
    ) {
        self._targetCoordinate = targetCoordinate
        self._targetAltitude = targetAltitude
        self.routeCoordinates = routeCoordinates
        self.showBottomInfoBar = showBottomInfoBar
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // MapKit Surface
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    // Target Coordinate Pin
                    Annotation("Target", coordinate: targetCoordinate) {
                        TargetMarkerPin(coordinate: targetCoordinate)
                    }

                    // Active Simulated Location Beacon
                    if let spoofed = connectionManager.currentSpoofedLocation {
                        Annotation("Simulated GPS", coordinate: spoofed) {
                            SimulatedBeaconPin(pulse: isPulsingPin)
                        }
                    }

                    // Polyline
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 4.5
                            )
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onTapGesture { screenCoord in
                    if let newCoord = proxy.convert(screenCoord, from: .local) {
                        HapticFeedback.selection()
                        targetCoordinate = newCoord
                        connectionManager.log(tag: "MAP", message: "Target -> (\(String(format: "%.6f", newCoord.latitude)), \(String(format: "%.6f", newCoord.longitude)))")
                    }
                }
            }
            .ignoresSafeArea()

            // Floating Top Controls Bar (Search + Quick Tools)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Glass Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("Search address, city, or landmark...", text: $searchCompleter.queryFragment)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit {
                                performDirectSearch()
                            }

                        if !searchCompleter.queryFragment.isEmpty {
                            Button {
                                searchCompleter.queryFragment = ""
                                searchCompleter.suggestions = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .liquidGlassCard(cornerRadius: 12)

                    // Re-center on Pin
                    Button {
                        HapticFeedback.selection()
                        centerCamera(on: targetCoordinate)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassCapsule()

                    // 3D Elevation Toggle
                    Button {
                        HapticFeedback.selection()
                        toggle3DPitch()
                    } label: {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(is3DPitchEnabled ? .blue : .primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .liquidGlassCapsule()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Search Autocomplete Dropdown
                if !searchCompleter.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(searchCompleter.suggestions, id: \.self) { suggestion in
                                    Button {
                                        HapticFeedback.selection()
                                        searchCompleter.selectSuggestion(suggestion) { coordinate, title in
                                            if let coordinate = coordinate {
                                                targetCoordinate = coordinate
                                                centerCamera(on: coordinate)
                                                searchCompleter.queryFragment = title
                                                searchCompleter.suggestions = []
                                            }
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(suggestion.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.primary)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                    .liquidGlassCard(cornerRadius: 12)
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Landscape / iPad Floating Bottom Pill
                if showBottomInfoBar {
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Text("LAT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.5f°", targetCoordinate.latitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        Divider()
                            .frame(height: 10)

                        HStack(spacing: 5) {
                            Text("LON")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.5f°", targetCoordinate.longitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        Divider()
                            .frame(height: 10)

                        HStack(spacing: 5) {
                            Text("ALT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f m", targetAltitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        Spacer()

                        Button {
                            HapticFeedback.impact(.medium)
                            connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                Text("Simulate Here")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(!connectionManager.status.isConnected)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .liquidGlassCapsule()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear {
            isPulsingPin = true
        }
    }

    private func centerCamera(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 1800,
                    heading: 0,
                    pitch: is3DPitchEnabled ? 55 : 0
                )
            )
        }
    }

    private func toggle3DPitch() {
        is3DPitchEnabled.toggle()
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: targetCoordinate,
                    distance: 1800,
                    heading: 0,
                    pitch: is3DPitchEnabled ? 55 : 0
                )
            )
        }
    }

    private func performDirectSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchCompleter.queryFragment
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            if let item = response?.mapItems.first {
                targetCoordinate = item.placemark.coordinate
                centerCamera(on: item.placemark.coordinate)
                searchCompleter.suggestions = []
            }
        }
    }
}

// MARK: - Target Marker Pin
fileprivate struct TargetMarkerPin: View {
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 28, height: 28)

                Circle()
                    .fill(Color.blue)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))

                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
            }

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundColor(.blue)
                .offset(y: -2)
        }
    }
}

// MARK: - Simulated Beacon Pin (Native Blue Halo)
fileprivate struct SimulatedBeaconPin: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.20))
                .frame(width: 38, height: 38)
                .scaleEffect(pulse ? 1.35 : 0.95)
                .opacity(pulse ? 0.0 : 0.8)
                .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)

            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 22, height: 22)

            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
    }
}
