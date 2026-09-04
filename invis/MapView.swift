//
//  MapView.swift
//  invis
//
//  Native Apple Maps (MapKit) view with pin placement, MapReader tap-to-set,
//  autocomplete place search, 3D terrain pitch, and route polyline rendering.
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
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
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
        search.start { response, error in
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

    @ObservedObject var connectionManager: WiredConnectionManager = .shared
    @StateObject private var searchCompleter = MapSearchCompleter()

    // Map state
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020),
            distance: 2500,
            heading: 0,
            pitch: 0
        )
    )
    @State private var is3DPitchEnabled: Bool = false
    @State private var showSearchResults: Bool = false
    @State private var pulseSimulatedPin: Bool = false

    public init(
        targetCoordinate: Binding<CLLocationCoordinate2D>,
        targetAltitude: Binding<Double> = .constant(15.0),
        routeCoordinates: [CLLocationCoordinate2D] = []
    ) {
        self._targetCoordinate = targetCoordinate
        self._targetAltitude = targetAltitude
        self.routeCoordinates = routeCoordinates
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Modern MapKit with MapReader for click/tap detection
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    // Target Coordinate Pin
                    Annotation("Target Pin", coordinate: targetCoordinate) {
                        TargetMarkerPin(coordinate: targetCoordinate, altitude: targetAltitude)
                    }

                    // Simulated GPS Location Pin (Active Spoofed position from Dongle)
                    if let spoofed = connectionManager.currentSpoofedLocation {
                        Annotation("Spoofed GPS", coordinate: spoofed) {
                            SpoofedBeaconPin(pulse: pulseSimulatedPin)
                        }
                    }

                    // Render Route Polyline if planned
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue, .cyan, .teal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 5
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
                        targetCoordinate = newCoord
                        connectionManager.log(tag: "MAP", message: "Target pinned to (\(String(format: "%.6f", newCoord.latitude)), \(String(format: "%.6f", newCoord.longitude)))")
                    }
                }
            }
            .ignoresSafeArea()

            // Floating Top Controls Bar: Search & Utilities
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Autocomplete Search Bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search address, landmark, or city...", text: $searchCompleter.queryFragment)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                performDirectSearch()
                            }

                        if !searchCompleter.queryFragment.isEmpty {
                            Button {
                                searchCompleter.queryFragment = ""
                                showSearchResults = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)

                    // Center to Target Pin
                    Button {
                        centerCamera(on: targetCoordinate)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .clipShape(Circle())
                    .help("Center to Target Pin")

                    // 3D Terrain Pitch Toggle
                    Button {
                        toggle3DPitch()
                    } label: {
                        Text("3D")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .tint(is3DPitchEnabled ? .cyan : .secondary)
                    .clipShape(Circle())
                    .help("Toggle 3D Terrain Pitch")
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                // Search Results Dropdown
                if !searchCompleter.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(searchCompleter.suggestions, id: \.self) { suggestion in
                                    Button {
                                        searchCompleter.selectSuggestion(suggestion) { coordinate, title in
                                            if let coordinate = coordinate {
                                                targetCoordinate = coordinate
                                                centerCamera(on: coordinate)
                                                searchCompleter.queryFragment = title
                                                searchCompleter.suggestions = []
                                            }
                                        }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
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
                        .frame(maxHeight: 200)
                    }
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Floating Bottom Info Bar (Coordinates & Altitude Readouts)
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("LAT:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.6f°", targetCoordinate.latitude))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }

                    Divider()
                        .frame(height: 12)

                    HStack(spacing: 6) {
                        Text("LON:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.6f°", targetCoordinate.longitude))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }

                    Divider()
                        .frame(height: 12)

                    HStack(spacing: 6) {
                        Text("ALT:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f m", targetAltitude))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }

                    Spacer()

                    // Quick Teleport Trigger on Pin
                    Button {
                        connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text("Spoof Here")
                        }
                        .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                    .disabled(!connectionManager.status.isConnected)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            pulseSimulatedPin = true
        }
        .onChange(of: targetCoordinate.latitude) { _, _ in
            // Keep centered if desired
        }
    }

    private func centerCamera(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.8)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 1800,
                    heading: 0,
                    pitch: is3DPitchEnabled ? 60 : 0
                )
            )
        }
    }

    private func toggle3DPitch() {
        is3DPitchEnabled.toggle()
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: targetCoordinate,
                    distance: 1800,
                    heading: 0,
                    pitch: is3DPitchEnabled ? 60 : 0
                )
            )
        }
    }

    private func performDirectSearch() {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchCompleter.queryFragment
        let search = MKLocalSearch(request: request)
        search.start { response, error in
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
    let altitude: Double

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.25))
                    .frame(width: 32, height: 32)
                Circle()
                    .fill(Color.orange)
                    .frame(width: 18, height: 18)
                Image(systemName: "target")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .offset(y: -3)
        }
    }
}

// MARK: - Spoofed Beacon Pin (Active Hardware Output)
fileprivate struct SpoofedBeaconPin: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 44, height: 44)
                .scaleEffect(pulse ? 1.4 : 0.9)
                .opacity(pulse ? 0.0 : 1.0)
                .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)

            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 26, height: 26)

            Circle()
                .fill(Color.blue)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
    }
}
