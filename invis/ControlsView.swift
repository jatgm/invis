//
//  ControlsView.swift
//  invis
//
//  Control panel for instant location spoofing, high-precision coordinates,
//  Gaussian micro-jitter drift controls, landmark presets, and safety killswitch.
//

import SwiftUI
import CoreLocation

public struct ControlsView: View {
    @Binding public var targetCoordinate: CLLocationCoordinate2D
    @Binding public var targetAltitude: Double

    @ObservedObject var connectionManager: WiredConnectionManager = .shared
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
        ScrollView {
            VStack(spacing: 16) {
                // 1. Simulation Actions Card (Spoof & Safety Reset)
                simulationActionsCard

                // 2. High-Precision Coordinate Inputs Card
                coordinateInputsCard

                // 3. Natural Micro-Jitter (GPS Drift) Card
                microJitterCard

                // 4. Quick Landmark Presets Grid
                presetsCard

                // 5. Activity Console / Monospace Log
                activityConsoleCard
            }
            .padding(16)
        }
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

    // MARK: - Simulation Actions Card
    private var simulationActionsCard: some View {
        VStack(spacing: 12) {
            // Instant Spoof Button
            Button {
                connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(connectionManager.isSpoofingActive ? "Update Simulated Location" : "Spoof Location")
                        .font(.system(size: 15, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(connectionManager.status.isConnected ? .blue : .gray)
            .disabled(!connectionManager.status.isConnected)

            // Safety Reset (Killswitch) Button
            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Reset to Physical GPS (Killswitch)")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!connectionManager.status.isConnected && !connectionManager.isSpoofingActive)
            .confirmationDialog(
                "Reset to Physical GPS?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset Hardware GPS", role: .destructive) {
                    connectionManager.resetLocation()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will instantly stop all spoofing, close active overrides on the Pico dongle, and restore your device's authentic hardware GPS signal.")
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Coordinate Inputs Card
    private var coordinateInputsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MANUAL COORDINATES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    // Quick San Francisco / Default reset
                    targetCoordinate = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
                } label: {
                    Text("Reset Default")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                // Latitude Input
                HStack {
                    Text("LAT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)

                    TextField("-90.0 to 90.0", text: $latString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit {
                            if let val = Double(latString), val >= -90.0 && val <= 90.0 {
                                targetCoordinate.latitude = val
                            } else {
                                syncInputStrings()
                            }
                        }

                    // Stepper nudge
                    HStack(spacing: 2) {
                        Button {
                            targetCoordinate.latitude = min(90.0, targetCoordinate.latitude + 0.001)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button {
                            targetCoordinate.latitude = max(-90.0, targetCoordinate.latitude - 0.001)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                // Longitude Input
                HStack {
                    Text("LON")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)

                    TextField("-180.0 to 180.0", text: $lonString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit {
                            if let val = Double(lonString), val >= -180.0 && val <= 180.0 {
                                targetCoordinate.longitude = val
                            } else {
                                syncInputStrings()
                            }
                        }

                    // Stepper nudge
                    HStack(spacing: 2) {
                        Button {
                            targetCoordinate.longitude = min(180.0, targetCoordinate.longitude + 0.001)
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button {
                            targetCoordinate.longitude = max(-180.0, targetCoordinate.longitude - 0.001)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                // Altitude Input
                HStack {
                    Text("ALT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)

                    TextField("Meters (e.g. 15.0)", text: $altString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                        .onSubmit {
                            if let val = Double(altString) {
                                targetAltitude = val
                            } else {
                                syncInputStrings()
                            }
                        }

                    Text("m")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Natural Micro-Jitter (GPS Drift) Card
    private var microJitterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $connectionManager.naturalDriftEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Realistic Micro-Jitter")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Gaussian random-walk drift to evade static detection")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.cyan)
            .onChange(of: connectionManager.naturalDriftEnabled) { _, newValue in
                connectionManager.setNaturalDrift(enabled: newValue, radiusMeters: connectionManager.driftRadiusMeters)
            }

            if connectionManager.naturalDriftEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Drift Radius:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "±%.1f meters (σ)", connectionManager.driftRadiusMeters))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                    }

                    Slider(value: $connectionManager.driftRadiusMeters, in: 0.5...5.0, step: 0.1) {
                        Text("Jitter Radius")
                    }
                    .tint(.cyan)
                    .onChange(of: connectionManager.driftRadiusMeters) { _, newValue in
                        connectionManager.setNaturalDrift(enabled: true, radiusMeters: newValue)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Presets Card
    private var presetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LANDMARK PRESETS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(LocationEngine.defaultPresets) { preset in
                    Button {
                        targetCoordinate = preset.coordinate
                        targetAltitude = preset.altitude
                        if connectionManager.status.isConnected && connectionManager.isSpoofingActive {
                            connectionManager.teleport(to: preset.coordinate, altitude: preset.altitude)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(preset.subtitle)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Activity Console Card
    private var activityConsoleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WIRED ACTIVITY LOG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    connectionManager.clearLogs()
                } label: {
                    Text("Clear")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button {
                    isConsoleExpanded.toggle()
                } label: {
                    Image(systemName: isConsoleExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(connectionManager.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.formattedTime)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text("[\(entry.tag)]")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(colorForTag(entry.tag))

                                Text(entry.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .frame(maxHeight: isConsoleExpanded ? 240 : 90)
                .padding(8)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: connectionManager.logs.count) { _, _ in
                    if let last = connectionManager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func colorForTag(_ tag: String) -> Color {
        switch tag {
        case "TX": return .cyan
        case "RX": return .green
        case "ERR": return .red
        case "WARN": return .yellow
        case "MAP": return .purple
        default: return .secondary
        }
    }
}
