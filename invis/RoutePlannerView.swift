//
//  RoutePlannerView.swift
//  invis
//
//  Route Planning and Simulation Panel.
//  Uses MKDirections for realistic road routes, travel mode presets,
//  speed multiplier sliders, and route playback controls (start/pause/resume/stop/loop).
//

import SwiftUI
import MapKit
import CoreLocation

public struct RoutePlannerView: View {
    @Binding public var currentTarget: CLLocationCoordinate2D
    @Binding public var routeCoordinates: [CLLocationCoordinate2D]

    @ObservedObject var connectionManager: WiredConnectionManager = .shared

    // Route endpoints
    @State private var startAddress: String = "Current Pinned Location"
    @State private var destinationAddress: String = "Times Square, New York"
    @State private var destCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
    @State private var isCalculatingRoute: Bool = false
    @State private var routeCalculationError: String? = nil

    // Route settings
    @State private var selectedMode: TravelMode = .drive
    @State private var speedMultiplier: Double = 1.0 // 0.5x to 5.0x
    @State private var loopMode: Bool = false
    @State private var realisticTraffic: Bool = true
    @State private var totalDistanceMeters: Double = 0.0

    public init(
        currentTarget: Binding<CLLocationCoordinate2D>,
        routeCoordinates: Binding<[CLLocationCoordinate2D]>
    ) {
        self._currentTarget = currentTarget
        self._routeCoordinates = routeCoordinates
    }

    public var effectiveSpeedKmh: Double {
        selectedMode.baseSpeedKmh * speedMultiplier
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Route Endpoints Card
                endpointsCard

                // 2. Travel Mode & Speed Multiplier Card
                travelModeCard

                // 3. Simulation Playback Controls & Progress Card
                playbackControlsCard

                // 4. Quick Route Presets
                routePresetsCard
            }
            .padding(16)
        }
    }

    // MARK: - Endpoints Card
    private var endpointsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ROUTE DESTINATION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                // Start location
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("START")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(String(format: "Lat: %.5f, Lon: %.5f", currentTarget.latitude, currentTarget.longitude))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                }

                Divider()

                // Destination location
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DESTINATION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(String(format: "Lat: %.5f, Lon: %.5f", destCoordinate.latitude, destCoordinate.longitude))
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()

                    Button {
                        // Swap with target
                        let temp = destCoordinate
                        destCoordinate = currentTarget
                        currentTarget = temp
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Compute Route Button
            Button {
                calculateAppleMapsRoute()
            } label: {
                HStack {
                    if isCalculatingRoute {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    Text(isCalculatingRoute ? "Computing Road Geometry..." : "Calculate Turn-by-Turn Route")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(isCalculatingRoute)

            if let err = routeCalculationError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            if totalDistanceMeters > 0 {
                HStack {
                    Text("Total Distance:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f km", totalDistanceMeters / 1000.0))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Travel Mode & Speed Card
    private var travelModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAVEL PROFILE & SPEED")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            // Mode Selector
            HStack(spacing: 8) {
                ForEach(TravelMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 14))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            Text("\(Int(mode.baseSpeedKmh)) km/h")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedMode == mode ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.08))
                        .foregroundColor(selectedMode == mode ? .blue : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedMode == mode ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Speed Multiplier Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed Multiplier:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx (%d km/h)", speedMultiplier, Int(effectiveSpeedKmh)))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                }

                Slider(value: $speedMultiplier, in: 0.5...5.0, step: 0.25)
                    .tint(.blue)
            }

            // Options: Realistic traffic & Loop
            Toggle(isOn: $realisticTraffic) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Realistic Traffic Speed Variation")
                        .font(.system(size: 12, weight: .medium))
                    Text("Adds natural ±5% speed fluctuations & corner easing")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)

            Toggle(isOn: $loopMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continuous Loop Mode")
                        .font(.system(size: 12, weight: .medium))
                    Text("Automatically loops route simulation endlessly")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Playback Controls Card
    private var playbackControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SIMULATION CONTROLS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            // Progress Bar
            if connectionManager.isRoutePlaying {
                VStack(spacing: 4) {
                    ProgressView(value: connectionManager.routeProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)

                    HStack {
                        Text(String(format: "%.0f%% Complete", connectionManager.routeProgress * 100))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        Spacer()
                        Text(formatRemainingTime(connectionManager.routeRemainingSeconds))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Action Buttons Row
            HStack(spacing: 10) {
                if !connectionManager.isRoutePlaying {
                    // Start Route
                    Button {
                        startRouteSimulation()
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Route")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!connectionManager.status.isConnected || routeCoordinates.count < 2)
                } else {
                    // Pause / Resume
                    if connectionManager.isRoutePaused {
                        Button {
                            connectionManager.resumeRoute()
                        } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Resume")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                    } else {
                        Button {
                            connectionManager.pauseRoute()
                        } label: {
                            HStack {
                                Image(systemName: "pause.fill")
                                Text("Pause")
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                        }
                        .buttonStyle(.bordered)
                        .tint(.yellow)
                    }

                    // Stop
                    Button {
                        connectionManager.stopRoute()
                    } label: {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Quick Route Presets
    private var routePresetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK SCENARIO PRESETS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Button {
                    // Cupertino Campus Loop: Apple Park Visitor Center to Infinite Loop
                    currentTarget = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
                    destCoordinate = CLLocationCoordinate2D(latitude: 37.331820, longitude: -122.031180)
                    calculateAppleMapsRoute()
                } label: {
                    presetRow(title: "Apple Park → Infinite Loop", subtitle: "Cupertino, CA (~2.4 km Drive)", icon: "apple.logo")
                }
                .buttonStyle(.plain)

                Button {
                    // Manhattan Cruise: Central Park South to Times Square
                    currentTarget = CLLocationCoordinate2D(latitude: 40.766300, longitude: -73.977400)
                    destCoordinate = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
                    calculateAppleMapsRoute()
                } label: {
                    presetRow(title: "Central Park → Times Square", subtitle: "Manhattan, NY (~1.1 km Cruise)", icon: "building.2.fill")
                }
                .buttonStyle(.plain)

                Button {
                    // Tokyo Cruise: Shibuya Crossing to Roppongi Hills
                    currentTarget = CLLocationCoordinate2D(latitude: 35.659500, longitude: 139.700500)
                    destCoordinate = CLLocationCoordinate2D(latitude: 35.660400, longitude: 139.729200)
                    calculateAppleMapsRoute()
                } label: {
                    presetRow(title: "Shibuya Crossing → Roppongi", subtitle: "Tokyo, Japan (~3.2 km Drive)", icon: "car.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func presetRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Route Calculation Engine
    private func calculateAppleMapsRoute() {
        isCalculatingRoute = true
        routeCalculationError = nil

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentTarget))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoordinate))
        request.transportType = selectedMode == .walk ? .walking : .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            Task { @MainActor in
                self.isCalculatingRoute = false
                if let route = response?.routes.first {
                    // Extract point coordinates from MKPolyline
                    let pointCount = route.polyline.pointCount
                    var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
                    route.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

                    self.routeCoordinates = coords
                    self.totalDistanceMeters = route.distance
                    self.connectionManager.log(tag: "INFO", message: "Computed Apple Maps turn-by-turn road route with \(coords.count) points (\(String(format: "%.2f km", route.distance / 1000.0)))")
                } else {
                    // Fallback to Great-Circle Haversine direct interpolation
                    let numSteps = 50
                    let fallbackCoords = LocationEngine.shared.interpolate(from: currentTarget, to: destCoordinate, steps: numSteps)
                    self.routeCoordinates = [currentTarget] + fallbackCoords
                    self.totalDistanceMeters = LocationEngine.shared.haversineDistance(from: currentTarget, to: destCoordinate)
                    self.routeCalculationError = "Road route unavailable. Using geodesic interpolation fallback."
                    self.connectionManager.log(tag: "WARN", message: "Apple Maps directions failed: \(error?.localizedDescription ?? "No road route"). Fallback to Haversine line.")
                }
            }
        }
    }

    private func startRouteSimulation() {
        connectionManager.startRoute(
            waypoints: routeCoordinates,
            speedKmh: effectiveSpeedKmh,
            loop: loopMode,
            realisticTraffic: realisticTraffic
        )
    }

    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "ETA: %02d:%02d", mins, secs)
    }
}
