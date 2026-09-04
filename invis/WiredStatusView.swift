//
//  WiredStatusView.swift
//  invis
//
//  Wired Hardware Detection & Cable Status Indicator.
//  Displays real-time USB link state, ping latency, and firmware handshake version.
//

import SwiftUI

public struct WiredStatusView: View {
    @ObservedObject var connectionManager: WiredConnectionManager = .shared
    @State private var pulseAnimation = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Radar Icon Indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .scaleEffect(pulseAnimation && connectionManager.status.isConnected ? 1.3 : 1.0)
                    .opacity(pulseAnimation && connectionManager.status.isConnected ? 0.0 : 1.0)
                    .animation(
                        connectionManager.status.isConnected ?
                            Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                        value: pulseAnimation
                    )

                Circle()
                    .fill(statusColor.opacity(0.25))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIconName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(statusColor)
            }
            .onAppear {
                pulseAnimation = true
            }

            // Connection Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(statusHeadline)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    if case .connected(_, let version, _) = connectionManager.status {
                        Text(version)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }

                Text(statusSubheadline)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Ping Latency & Transport Badge
            if case .connected(let latency, _, _) = connectionManager.status {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f ms", latency))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    Text("WIRED USB")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button {
                    connectionManager.startHardwareDiscovery()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Detect")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.primary.opacity(0.08)),
            alignment: .bottom
        )
    }

    private var statusColor: Color {
        switch connectionManager.status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        }
    }

    private var statusIconName: String {
        switch connectionManager.status {
        case .connected(_, _, let transport):
            if transport.contains("Mac") {
                return "laptopcomputer"
            } else if transport.contains("Simulator") {
                return "desktopcomputer"
            } else {
                return "cpu"
            }
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        case .disconnected:
            return "cable.connector.slash"
        }
    }

    private var statusHeadline: String {
        switch connectionManager.status {
        case .connected(_, _, let transport):
            if transport.contains("Mac") {
                return "MacBook USB Bridge"
            } else if transport.contains("Simulator") {
                return "Simulator Mock Dongle"
            } else {
                return "Pico Hardware Dongle"
            }
        case .connecting:
            return "Establishing Wired Link..."
        case .disconnected:
            return "Hardware Disconnected"
        }
    }

    private var statusSubheadline: String {
        switch connectionManager.status {
        case .connected(_, _, let transport):
            if let model = connectionManager.connectedDeviceModel {
                return "\(model) • \(transport)"
            }
            return "Active Wired Link: \(transport)"
        case .connecting(let detail):
            return detail
        case .disconnected(let reason):
            return reason
        }
    }
}
