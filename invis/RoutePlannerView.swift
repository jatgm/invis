//
//  RoutePlannerView.swift
//  invis
//
//  Apple Native Grouped Form Route Planner with Turn-by-Turn Simulation.
//  Uses Apple's official SwiftUI Form, Section, Picker, and ButtonStyle APIs.
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
        Form {
            // 1. Waypoints & Calculation Section
            Section {
                // Origin Row
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .background(Circle().fill(Color.blue.opacity(0.15)))
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ORIGIN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.5f, %.5f", currentTarget.latitude, currentTarget.longitude))
                            .font(.system(.body, design: .monospaced))
                    }
                }

                // Destination Row
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DESTINATION")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.5f, %.5f", destCoordinate.latitude, destCoordinate.longitude))
                            .font(.system(.body, design: .monospaced))
                    }

                    Spacer()

                    Button {
                        HapticFeedback.selection()
                        let temp = destCoordinate
                        destCoordinate = currentTarget
                        currentTarget = temp
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Calculate Action
                Button {
                    HapticFeedback.impact(.medium)
                    calculateAppleMapsRoute()
                } label: {
                    HStack {
                        Spacer()
                        if isCalculatingRoute {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        } else {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        Text(isCalculatingRoute ? "Calculating..." : "Calculate Road Route")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.blue)
                .disabled(isCalculatingRoute)

                if let err = routeCalculationError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }

                if totalDistanceMeters > 0 {
                    HStack {
                        Text("Calculated Road Distance")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2f km", totalDistanceMeters / 1000.0))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                }
            } header: {
                Text("ROUTE ENDPOINTS")
            }

            // 2. Travel Profile Section
            Section {
                // Segmented Profile
                Picker("Travel Mode", selection: $selectedMode) {
                    ForEach(TravelMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Speed Factor")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1fx (%d km/h)", speedMultiplier, Int(effectiveSpeedKmh)))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    Slider(value: $speedMultiplier, in: 0.5...4.0, step: 0.25)
                        .tint(.blue)
                }
                .padding(.vertical, 4)

                Toggle("Simulate Road Traffic Variance", isOn: $realisticTraffic)
                    .tint(.blue)

                Toggle("Continuous Route Loop", isOn: $loopMode)
                    .tint(.blue)
            } header: {
                Text("TRAVEL PROFILE")
            }

            // 3. Playback Section
            Section {
                if connectionManager.isRoutePlaying {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: connectionManager.routeProgress)
                            .tint(.blue)

                        HStack {
                            Text("Simulating Route")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)

                            Spacer()

                            Text(String(format: "%02d:%02d remaining", Int(connectionManager.routeRemainingSeconds) / 60, Int(connectionManager.routeRemainingSeconds) % 60))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if !connectionManager.isRoutePlaying {
                    Button {
                        HapticFeedback.impact(.medium)
                        startSimulation()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                            Text("Start Route Simulation")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(routeCoordinates.count < 2 || !connectionManager.status.isConnected)
                } else {
                    HStack(spacing: 12) {
                        if connectionManager.isRoutePaused {
                            Button {
                                HapticFeedback.impact(.light)
                                connectionManager.resumeRoute()
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "play.fill")
                                    Text("Resume")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(.blue)
                        } else {
                            Button {
                                HapticFeedback.impact(.light)
                                connectionManager.pauseRoute()
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "pause.fill")
                                    Text("Pause")
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }

                        Button(role: .destructive) {
                            HapticFeedback.impact(.light)
                            connectionManager.stopRoute()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "stop.fill")
                                Text("Stop")
                                Spacer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.red)
                    }
                }
            } header: {
                Text("SIMULATION CONTROLS")
            }

            // 4. Preset Circuits Section
            Section {
                Button {
                    HapticFeedback.selection()
                    currentTarget = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
                    destCoordinate = CLLocationCoordinate2D(latitude: 37.331800, longitude: -122.030500)
                    calculateAppleMapsRoute()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Park Perimeter")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Cupertino Infinite Loop Circuit (5.2 km)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button {
                    HapticFeedback.selection()
                    currentTarget = CLLocationCoordinate2D(latitude: 40.765000, longitude: -73.973000)
                    destCoordinate = CLLocationCoordinate2D(latitude: 40.758000, longitude: -73.985500)
                    calculateAppleMapsRoute()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.blue)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manhattan Midtown Express")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            Text("Central Park to Times Square (3.4 km)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("PRESET CIRCUITS")
            }
        }
        .scrollContentBackground(.hidden)
    }

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
