//
//  ControlsView.swift
//  invis
//
//  Apple Native Grouped Form with Translucent Glass Styling.
//  Uses Apple's official SwiftUI Form, Section, and ButtonStyle APIs.
//

import SwiftUI
import CoreLocation

public struct ControlsView: View {
    @Binding public var targetCoordinate: CLLocationCoordinate2D
    @Binding public var targetAltitude: Double

    @ObservedObject var connectionManager: WiredConnectionManager = .shared
    @ObservedObject var locationManager: UserLocationManager = .shared

    @State private var latString: String = ""
    @State private var lonString: String = ""
    @State private var altString: String = ""
    @State private var showResetConfirm: Bool = false
    @State private var isConsoleExpanded: Bool = false

    public init(
        targetCoordinate: Binding<CLLocationCoordinate2D>,
        targetAltitude: Binding<Double>
    ) {
        self._targetCoordinate = targetCoordinate
        self._targetAltitude = targetAltitude
    }

    public var body: some View {
        Form {
            // 1. Simulation Actions Section
            Section {
                Button {
                    HapticFeedback.impact(.medium)
                    connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: connectionManager.isSpoofingActive ? "location.fill" : "location")
                            .font(.system(size: 15, weight: .semibold))
                        Text(connectionManager.isSpoofingActive ? "Update Simulation" : "Simulate Location")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.blue)
                .disabled(!connectionManager.status.isConnected)

                if connectionManager.isSpoofingActive {
                    Button(role: .destructive) {
                        HapticFeedback.impact(.light)
                        showResetConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restore Physical Hardware GPS")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.red)
                    .confirmationDialog(
                        "Restore Hardware GPS?",
                        isPresented: $showResetConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Restore Authentic Location", role: .destructive) {
                            HapticFeedback.notification(.success)
                            connectionManager.resetLocation()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This clears all active location simulation overrides on the hardware and restores authentic system GPS.")
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            // 2. High-Precision Coordinate Telemetry
            Section {
                // Latitude
                HStack {
                    Text("Latitude")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("Latitude", text: $latString)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if let val = Double(latString), val >= -90.0 && val <= 90.0 {
                                targetCoordinate.latitude = val
                            } else {
                                syncInputStrings()
                            }
                        }

                    HStack(spacing: 2) {
                        Button {
                            HapticFeedback.selection()
                            targetCoordinate.latitude = min(90.0, targetCoordinate.latitude + 0.001)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button {
                            HapticFeedback.selection()
                            targetCoordinate.latitude = max(-90.0, targetCoordinate.latitude - 0.001)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                // Longitude
                HStack {
                    Text("Longitude")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("Longitude", text: $lonString)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if let val = Double(lonString), val >= -180.0 && val <= 180.0 {
                                targetCoordinate.longitude = val
                            } else {
                                syncInputStrings()
                            }
                        }

                    HStack(spacing: 2) {
                        Button {
                            HapticFeedback.selection()
                            targetCoordinate.longitude = min(180.0, targetCoordinate.longitude + 0.001)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button {
                            HapticFeedback.selection()
                            targetCoordinate.longitude = max(-180.0, targetCoordinate.longitude - 0.001)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                // Altitude
                HStack {
                    Text("Altitude")
                        .foregroundColor(.secondary)
                    Spacer()
                    TextField("Meters", text: $altString)
                        .multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if let val = Double(altString) {
                                targetAltitude = val
                            } else {
                                syncInputStrings()
                            }
                        }
                    Text("m")
                        .foregroundColor(.secondary)
                }

                // Reset to My Real Physical GPS Location
                Button {
                    HapticFeedback.selection()
                    if let realLocation = locationManager.userLocation {
                        targetCoordinate = realLocation
                    } else {
                        locationManager.requestLocationOnce()
                    }
                } label: {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.blue)
                        Text("Reset to My Physical Location")
                            .foregroundColor(.blue)
                        Spacer()
                        if locationManager.userLocation != nil {
                            Text("Acquired")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("COORDINATES")
            }

            // 3. Natural Position Drift Section
            Section {
                Toggle("Natural Multi-Path Drift", isOn: $connectionManager.naturalDriftEnabled)
                    .tint(.blue)
                    .onChange(of: connectionManager.naturalDriftEnabled) { _, newValue in
                        HapticFeedback.selection()
                        connectionManager.setNaturalDrift(enabled: newValue, radiusMeters: connectionManager.driftRadiusMeters)
                    }

                if connectionManager.naturalDriftEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Variance Radius")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "±%.1f m", connectionManager.driftRadiusMeters))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue)
                        }

                        Slider(value: $connectionManager.driftRadiusMeters, in: 0.5...5.0, step: 0.2)
                            .tint(.blue)
                            .onChange(of: connectionManager.driftRadiusMeters) { _, newValue in
                                connectionManager.setNaturalDrift(enabled: true, radiusMeters: newValue)
                            }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("POSITION DRIFT")
            } footer: {
                Text("Applies subtle Gaussian random-walk drift to reflect authentic GNSS multi-path variance.")
            }

            // 4. Landmarks Section
            Section {
                ForEach(LocationEngine.defaultPresets) { preset in
                    Button {
                        HapticFeedback.selection()
                        targetCoordinate = preset.coordinate
                        targetAltitude = preset.altitude
                        if connectionManager.status.isConnected && connectionManager.isSpoofingActive {
                            connectionManager.teleport(to: preset.coordinate, altitude: preset.altitude)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 15))
                                .foregroundColor(.blue)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)

                                Text(preset.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("LANDMARK PRESETS")
            }

            // 5. Diagnostics Console Section
            Section {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(connectionManager.logs) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(entry.formattedTime)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Text("[\(entry.tag)]")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(colorForTag(entry.tag))

                                    Text(entry.message)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }
                                .id(entry.id)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: isConsoleExpanded ? 240 : 90)
                    .onChange(of: connectionManager.logs.count) { _, _ in
                        if let last = connectionManager.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                HStack {
                    Button("Clear Logs") {
                        connectionManager.clearLogs()
                    }
                    .font(.system(size: 12))

                    Spacer()

                    Button(isConsoleExpanded ? "Collapse" : "Expand") {
                        withAnimation {
                            isConsoleExpanded.toggle()
                        }
                    }
                    .font(.system(size: 12))
                }
            } header: {
                Text("HARDWARE LOGS")
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            syncInputStrings()
        }
        .onChange(of: targetCoordinate.latitude) { _, _ in
            syncInputStrings()
        }
        .onChange(of: targetCoordinate.longitude) { _, _ in
            syncInputStrings()
        }
    }

    private func syncInputStrings() {
        latString = String(format: "%.6f", targetCoordinate.latitude)
        lonString = String(format: "%.6f", targetCoordinate.longitude)
        altString = String(format: "%.1f", targetAltitude)
    }

    private func colorForTag(_ tag: String) -> Color {
        switch tag {
        case "TX": return .cyan
        case "RX": return .green
        case "ERR": return .red
        case "WARN": return .orange
        default: return .secondary
        }
    }
}
