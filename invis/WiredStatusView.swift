//
//  WiredStatusView.swift
//  invis
//
//  Liquid Glass Wired Hardware Status Header.
//  Strictly conforms to iOS Human Interface Guidelines:
//  Subtle specular border, translucent ultra-thin material,
//  clean typography, semantic SF Symbols, and zero emojis.
//

import SwiftUI

public struct WiredStatusView: View {
    @ObservedObject var connectionManager: WiredConnectionManager = .shared
    @State private var isPulsing: Bool = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Status Pip
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.20))
                    .frame(width: 24, height: 24)
                    .scaleEffect(isPulsing && connectionManager.status.isConnected ? 1.35 : 1.0)
                    .opacity(isPulsing && connectionManager.status.isConnected ? 0.0 : 0.8)
                    .animation(
                        connectionManager.status.isConnected ?
                            Animation.easeOut(duration: 1.8).repeatForever(autoreverses: false) : .default,
                        value: isPulsing
                    )

                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 24, height: 24)
            .onAppear {
                isPulsing = true
            }

            // Status Copy
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if case .connected(_, let version, _) = connectionManager.status {
                        Text(version)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }

                Text(statusSubtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Right Action / Telemetry
            if case .connected(let latency, _, _) = connectionManager.status {
                HStack(spacing: 5) {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1f ms", latency))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .liquidGlassCapsule()
            } else {
                Button {
                    HapticFeedback.impact(.light)
                    connectionManager.startHardwareDiscovery()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Connect")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .liquidGlassCapsule()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
        )
    }

    private var statusColor: Color {
        switch connectionManager.status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return Color.secondary.opacity(0.6)
        }
    }

    private var statusTitle: String {
        switch connectionManager.status {
        case .connected(_, _, let transport):
            if transport.contains("Mac") {
                return "MacBook USB Bridge"
            } else if transport.contains("Simulator") {
                return "Simulator Interface"
            } else {
                return "Pico Hardware Interface"
            }
        case .connecting:
            return "Negotiating Link"
        case .disconnected:
            return "Hardware Standby"
        }
    }

    private var statusSubtitle: String {
        switch connectionManager.status {
        case .connected(_, _, let transport):
            if let model = connectionManager.connectedDeviceModel {
                return "\(model) via \(transport)"
            }
            return transport
        case .connecting(let detail):
            return detail
        case .disconnected(let reason):
            return reason
        }
    }
}
