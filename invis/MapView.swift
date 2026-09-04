//
//  MapView.swift
//  invis
//
//  Native Apple Maps (MapKit) view utilizing Apple's official controls:
//  UserAnnotation(), MapUserLocationButton(), MapCompass(), MapPitchToggle(),
//  and automatic physical user coordinate centering.
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
    @ObservedObject var locationManager: UserLocationManager = .shared
    @StateObject private var searchCompleter = MapSearchCompleter()

    // Map camera
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020),
            distance: 2000,
            heading: 0,
            pitch: 0
        )
    ))
    @Namespace private var mapScope
    @State private var hasCenteredInitialUser: Bool = false

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
            // Apple Native MapKit with UserAnnotation
            MapReader { proxy in
                Map(position: $cameraPosition, scope: mapScope) {
                    // Apple Real Native Physical GPS User Dot
                    UserAnnotation()

                    // Target Pin
                    Annotation("Target", coordinate: targetCoordinate) {
                        TargetMarkerPin(coordinate: targetCoordinate)
                    }

                    // Active Hardware Simulated Location Pin
                    if let spoofed = connectionManager.currentSpoofedLocation {
                        Annotation("Simulated GPS", coordinate: spoofed) {
                            SimulatedBeaconPin()
                        }
                    }

                    // Route Polyline
                    if routeCoordinates.count >= 2 {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 5
                            )
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapScope(mapScope)
                .onTapGesture { screenCoord in
                    if let newCoord = proxy.convert(screenCoord, from: .local) {
                        HapticFeedback.selection()
                        targetCoordinate = newCoord
                        connectionManager.log(tag: "MAP", message: "Target pinned -> (\(String(format: "%.6f", newCoord.latitude)), \(String(format: "%.6f", newCoord.longitude)))")
                    }
                }
            }
            .ignoresSafeArea()

            // Top Floating Search Bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("Search address, landmark, or city...", text: $searchCompleter.queryFragment)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit {
                                performDirectSearch()
                            }

                        if !searchCompleter.queryFragment.isEmpty {
                            Button {
                                searchCompleter.queryFragment = ""
                                searchCompleter.suggestions = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)

                    // Target Pin Focus Button
                    Button {
                        HapticFeedback.selection()
                        centerCamera(on: targetCoordinate)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 64) // Below top status bar

                // Search Results Dropdown
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
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.title)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.primary)
                                            if !suggestion.subtitle.isEmpty {
                                                Text(suggestion.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)

                                    Divider()
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.16), radius: 12, x: 0, y: 4)
                    .padding(.horizontal, 16)
                }

                Spacer()

                // Bottom Telemetry Bar for iPad / Landscape
                if showBottomInfoBar {
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("LAT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.5f°", targetCoordinate.latitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        Divider()
                            .frame(height: 12)

                        HStack(spacing: 6) {
                            Text("LON")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.5f°", targetCoordinate.longitude))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }

                        Divider()
                            .frame(height: 12)

                        HStack(spacing: 6) {
                            Text("ALT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                Text("Simulate Here")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        .disabled(!connectionManager.status.isConnected)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }

            // Apple Real Native Floating Map Controls (Compass, Pitch 3D, and User GPS Location Button)
            VStack(spacing: 8) {
                Spacer()
                    .frame(height: 120)

                HStack {
                    Spacer()

                    VStack(spacing: 8) {
                        MapUserLocationButton(scope: mapScope)
                        MapCompass(scope: mapScope)
                        MapPitchToggle(scope: mapScope)
                    }
                    .padding(.trailing, 16)
                    .buttonBorderShape(.circle)
                }

                Spacer()
            }
        }
        .onReceive(locationManager.$userLocation) { userCoord in
            guard let coord = userCoord, !hasCenteredInitialUser else { return }
            hasCenteredInitialUser = true
            centerCamera(on: coord)
        }
    }

    private func centerCamera(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.6)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 1800,
                    heading: 0,
                    pitch: 0
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
                    .fill(Color.blue.opacity(0.20))
                    .frame(width: 30, height: 30)

                Circle()
                    .fill(Color.blue)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))

                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9))
                .foregroundColor(.blue)
                .offset(y: -2)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Simulated Beacon Pin (Native Amber Beacon)
fileprivate struct SimulatedBeaconPin: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 36, height: 36)
                .scaleEffect(isPulsing ? 1.4 : 0.9)
                .opacity(isPulsing ? 0.0 : 0.8)
                .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: isPulsing)

            Circle()
                .fill(Color.green.opacity(0.35))
                .frame(width: 22, height: 22)

            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
        }
        .onAppear {
            isPulsing = true
        }
    }
}
