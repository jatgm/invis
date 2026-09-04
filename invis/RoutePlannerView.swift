//
//  RoutePlannerView.swift
//  invis
//
//  Liquid Glass Route Planner & Interpolation Simulation.
//  Strictly conforms to iOS Human Interface Guidelines:
//  Subtle specular borders, translucent ultra-thin materials,
//  clean typography, semantic SF Symbols, and zero emojis.
//

import SwiftUI
import MapKit
import CoreLocation

public struct RoutePlannerView: View {
    @Binding public var currentTarget: CLLocationCoordinate2D
    @Binding public var routeCoordinates: [CLLocationCoordinate2D]

    @ObservedObject var connectionManager: WiredConnectionManager = .shared

    // Route endpoints
    @State private var destCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
    @State private var isCalculatingRoute: Bool = false
    @State private var routeCalculationError: String? = nil

    // Route parameters
    @State private var selectedMode: TravelMode = .drive
    @State private var speedMultiplier: Double = 1.0
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // 1. Waypoints & Route Calculation Card
                waypointsCard

                // 2. Travel Profile & Speed Multiplier Card
                travelProfileCard

                // 3. Playback Controls & Timeline Card
                playbackControlsCard

                // 4. Quick Route Presets Card
                quickRoutesCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 1. Waypoints Card
    private var waypointsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DESTINATION")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                // Origin
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .background(Circle().fill(Color.blue.opacity(0.15)))
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("ORIGIN")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text(String(format: "%.5f, %.5f", currentTarget.latitude, currentTarget.longitude))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)

                // Vector Track Divider
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1.5, height: 18)
                        .padding(.leading, 6)
                    Spacer()
                }

                // Destination
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("DESTINATION")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text(String(format: "%.5f, %.5f", destCoordinate.latitude, destCoordinate.longitude))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Button {
                        HapticFeedback.selection()
                        let temp = destCoordinate
                        destCoordinate = currentTarget
                        currentTarget = temp
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 10)
            .background(Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Compute Button
            Button {
                HapticFeedback.impact(.medium)
                calculateAppleMapsRoute()
            } label: {
                HStack(spacing: 6) {
                    if isCalculatingRoute {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(isCalculatingRoute ? "Calculating Road Geometry..." : "Calculate Turn-by-Turn Route")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(isCalculatingRoute)

            if let err = routeCalculationError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }

            if totalDistanceMeters > 0 {
                HStack {
                    Text("Road Distance")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.2f km", totalDistanceMeters / 1000.0))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 2. Travel Profile Card
    private var travelProfileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAVEL PROFILE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            // Segmented Travel Mode
            HStack(spacing: 6) {
                ForEach(TravelMode.allCases) { mode in
                    Button {
                        HapticFeedback.selection()
                        selectedMode = mode
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 13, weight: .medium))

                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))

                            Text("\(Int(mode.baseSpeedKmh)) km/h")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedMode == mode ? Color.blue.opacity(0.15) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selectedMode == mode ? Color.blue : Color.clear, lineWidth: 1)
                        )
                        .foregroundColor(selectedMode == mode ? .blue : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Speed Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed Factor")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx (%d km/h)", speedMultiplier, Int(effectiveSpeedKmh)))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)
                }

                Slider(value: $speedMultiplier, in: 0.5...4.0, step: 0.25)
                    .tint(.blue)
            }

            // Traffic Variance & Loop Options
            Toggle(isOn: $realisticTraffic) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Simulate Road Traffic")
                        .font(.system(size: 12, weight: .medium))
                    Text("Natural deceleration on corners and subtle speed variance")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)

            Toggle(isOn: $loopMode) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Continuous Route Loop")
                        .font(.system(size: 12, weight: .medium))
                    Text("Replay route continuously once destination is reached")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 3. Playback Controls Card
    private var playbackControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SIMULATION PLAYBACK")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            // Timeline Progress
            if connectionManager.isRoutePlaying {
                VStack(spacing: 6) {
                    ProgressView(value: connectionManager.routeProgress)
                        .tint(.blue)

                    HStack {
                        Text("Simulating Route")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)

                        Spacer()

                        Text(String(format: "%02d:%02d remaining", Int(connectionManager.routeRemainingSeconds) / 60, Int(connectionManager.routeRemainingSeconds) % 60))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
            }

            // Transport Buttons
            HStack(spacing: 8) {
                if !connectionManager.isRoutePlaying {
                    Button {
                        HapticFeedback.impact(.medium)
                        startSimulation()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                            Text("Start Route")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(routeCoordinates.count >= 2 && connectionManager.status.isConnected ? Color.blue : Color.secondary.opacity(0.3))
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(routeCoordinates.count < 2 || !connectionManager.status.isConnected)
                } else {
                    if connectionManager.isRoutePaused {
                        Button {
                            HapticFeedback.impact(.light)
                            connectionManager.resumeRoute()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("Resume")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            HapticFeedback.impact(.light)
                            connectionManager.pauseRoute()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "pause.fill")
                                Text("Pause")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.06))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        HapticFeedback.impact(.light)
                        connectionManager.stopRoute()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 4. Quick Route Presets
    private var quickRoutesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESET CIRCUITS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                presetCircuitRow(
                    title: "Cupertino Infinite Loop Circuit",
                    detail: "Apple Park Perimeter (5.2 km)",
                    icon: "apple.logo",
                    start: CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020),
                    dest: CLLocationCoordinate2D(latitude: 37.331800, longitude: -122.030500)
                )

                presetCircuitRow(
                    title: "Manhattan Midtown Express",
                    detail: "Central Park to Times Square (3.4 km)",
                    icon: "building.2.fill",
                    start: CLLocationCoordinate2D(latitude: 40.765000, longitude: -73.973000),
                    dest: CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
                )
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    private func presetCircuitRow(title: String, detail: String, icon: String, start: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> some View {
        Button {
            HapticFeedback.selection()
            currentTarget = start
            destCoordinate = dest
            calculateAppleMapsRoute()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .frame(width: 26, height: 26)
                    .background(Color.blue.opacity(0.08))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Route Calculation Logic
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
                if let error = error {
                    self.routeCalculationError = error.localizedDescription
                    return
                }

                guard let primaryRoute = response?.routes.first else {
                    self.routeCalculationError = "No valid road route found between points."
                    return
                }

                self.totalDistanceMeters = primaryRoute.distance
                var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: primaryRoute.polyline.pointCount)
                primaryRoute.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: primaryRoute.polyline.pointCount))
                self.routeCoordinates = coordinates
                HapticFeedback.notification(.success)
            }
        }
    }

    private func startSimulation() {
        guard routeCoordinates.count >= 2 else { return }
        connectionManager.startRoute(
            waypoints: routeCoordinates,
            speedKmh: effectiveSpeedKmh,
            loop: loopMode,
            realisticTraffic: realisticTraffic
        )
    }
}
