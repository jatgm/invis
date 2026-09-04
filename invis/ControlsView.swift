//
//  ControlsView.swift
//  invis
//
//  Liquid Glass Control Surface for Location Simulation.
//  Strictly adheres to iOS Human Interface Guidelines:
//  Subtle specular borders, translucent ultra-thin materials,
//  clean typography, semantic SF Symbols, and zero emojis.
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                // 1. Primary Simulation Actions
                primaryActionsCard

                // 2. High-Precision Coordinate Telemetry
                coordinatesInspectorCard

                // 3. Natural Position Drift (Variance)
                positionDriftCard

                // 4. Quick Landmark Locations
                landmarksGridCard

                // 5. Hardware Activity Diagnostics
                activityDiagnosticsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

    // MARK: - 1. Primary Simulation Actions
    private var primaryActionsCard: some View {
        VStack(spacing: 10) {
            // Main Simulate Button
            Button {
                HapticFeedback.impact(.medium)
                connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: connectionManager.isSpoofingActive ? "location.fill" : "location")
                        .font(.system(size: 15, weight: .semibold))

                    Text(connectionManager.isSpoofingActive ? "Update Simulation" : "Simulate Location")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(connectionManager.status.isConnected ? Color.blue : Color.secondary.opacity(0.3))
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!connectionManager.status.isConnected)

            // Reset Hardware GPS Button
            if connectionManager.isSpoofingActive {
                Button {
                    HapticFeedback.impact(.light)
                    showResetConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Restore Hardware GPS")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
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
                    Text("This clears active location simulation on the connected hardware and restores authentic system GPS.")
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 2. Coordinates Inspector
    private var coordinatesInspectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("COORDINATES")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    HapticFeedback.selection()
                    targetCoordinate = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
                } label: {
                    Text("Cupertino Default")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                // Latitude Row
                coordinateFieldRow(label: "LAT", text: $latString) { val in
                    if val >= -90.0 && val <= 90.0 { targetCoordinate.latitude = val }
                } stepAction: { delta in
                    targetCoordinate.latitude = min(90.0, max(-90.0, targetCoordinate.latitude + delta))
                }

                // Longitude Row
                coordinateFieldRow(label: "LON", text: $lonString) { val in
                    if val >= -180.0 && val <= 180.0 { targetCoordinate.longitude = val }
                } stepAction: { delta in
                    targetCoordinate.longitude = min(180.0, max(-180.0, targetCoordinate.longitude + delta))
                }

                // Altitude Row
                HStack(spacing: 8) {
                    Text("ALT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .leading)

                    TextField("Meters", text: $altString)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit {
                            if let val = Double(altString) { targetAltitude = val }
                        }

                    Text("meters")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    private func coordinateFieldRow(
        label: String,
        text: Binding<String>,
        onCommit: @escaping (Double) -> Void,
        stepAction: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 32, alignment: .leading)

            TextField(label, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit {
                    if let val = Double(text.wrappedValue) { onCommit(val) }
                    else { syncInputStrings() }
                }

            // Inline Steppers
            HStack(spacing: 1) {
                Button {
                    HapticFeedback.selection()
                    stepAction(0.001)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.04))
                }
                .buttonStyle(.plain)

                Button {
                    HapticFeedback.selection()
                    stepAction(-0.001)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.04))
                }
                .buttonStyle(.plain)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - 3. Natural Position Drift
    private var positionDriftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $connectionManager.naturalDriftEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Natural Position Drift")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Simulates natural multi-path variance with Gaussian random walk")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
            .onChange(of: connectionManager.naturalDriftEnabled) { _, newValue in
                HapticFeedback.selection()
                connectionManager.setNaturalDrift(enabled: newValue, radiusMeters: connectionManager.driftRadiusMeters)
            }

            if connectionManager.naturalDriftEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Variance Radius")
                            .font(.system(size: 11, weight: .regular))
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
                .padding(.top, 4)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 4. Landmarks Grid
    private var landmarksGridCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LANDMARKS")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(LocationEngine.defaultPresets) { preset in
                    Button {
                        HapticFeedback.selection()
                        targetCoordinate = preset.coordinate
                        targetAltitude = preset.altitude
                        if connectionManager.status.isConnected && connectionManager.isSpoofingActive {
                            connectionManager.teleport(to: preset.coordinate, altitude: preset.altitude)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                                .frame(width: 24, height: 24)
                                .background(Color.blue.opacity(0.08))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                Text(preset.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - 5. Activity Diagnostics
    private var activityDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DIAGNOSTICS")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    connectionManager.clearLogs()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isConsoleExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isConsoleExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
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
                .frame(maxHeight: isConsoleExpanded ? 220 : 80)
                .background(Color.black.opacity(0.20))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: connectionManager.logs.count) { _, _ in
                    if let last = connectionManager.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16)
    }

    private func colorForTag(_ tag: String) -> Color {
        switch tag {
        case "TX": return .cyan
        case "RX": return .green
        case "ERR": return .red
        case "WARN": return .orange
        case "MAP": return .blue
        default: return .secondary
        }
    }
}
