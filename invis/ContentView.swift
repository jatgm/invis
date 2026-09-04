//
//  ContentView.swift
//  invis
//
//  Main application container with Apple Maps, Wired Pico dongle status,
//  sidebar controls, route simulation, and responsive layout.
//

import SwiftUI
import MapKit
import CoreLocation

public struct ContentView: View {
    @StateObject private var connectionManager = WiredConnectionManager.shared

    // Active target coordinate (default Cupertino Apple Park)
    @State private var targetCoordinate = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
    @State private var targetAltitude: Double = 15.0
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    // UI Tab selection
    @State private var selectedTab: ControlTab = .instantSpoof

    public enum ControlTab: String, CaseIterable, Identifiable {
        case instantSpoof = "Teleport & Presets"
        case routePlanner = "Route Planner"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .instantSpoof: return "location.fill"
            case .routePlanner: return "point.topleft.down.to.point.bottomright.curvepath"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Persistent Top Wired Status Bar
            WiredStatusView()

            // iOS Layout: Overlay bottom sheet or adaptive layout
            GeometryReader { geo in
                if geo.size.width > 700 {
                    // iPad Landscape / Split
                    HStack(spacing: 0) {
                        sidebarContent
                            .frame(width: 380)
                            .background(.regularMaterial)

                        Divider()

                        MapView(
                            targetCoordinate: $targetCoordinate,
                            targetAltitude: $targetAltitude,
                            routeCoordinates: routeCoordinates,
                            showBottomInfoBar: true
                        )
                    }
                } else {
                    // iPhone Portrait Stack
                    ZStack(alignment: .bottom) {
                        MapView(
                            targetCoordinate: $targetCoordinate,
                            targetAltitude: $targetAltitude,
                            routeCoordinates: routeCoordinates,
                            showBottomInfoBar: false
                        )

                        // Collapsible Bottom Card for iPhone
                        iPhoneControlSheet(geo: geo)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Sidebar Content
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Mode", selection: $selectedTab) {
                ForEach(ControlTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Active Tab View
            Group {
                switch selectedTab {
                case .instantSpoof:
                    ControlsView(
                        targetCoordinate: $targetCoordinate,
                        targetAltitude: $targetAltitude
                    )
                case .routePlanner:
                    RoutePlannerView(
                        currentTarget: $targetCoordinate,
                        routeCoordinates: $routeCoordinates
                    )
                }
            }
        }
    }

    public enum SheetDetent: Equatable {
        case minimized
        case medium
        case expanded
    }

    @State private var sheetDetent: SheetDetent = .minimized

    private func iPhoneControlSheet(geo: GeometryProxy) -> some View {
        let bottomSafeInset = max(geo.safeAreaInsets.bottom, 16)
        let mediumHeight: CGFloat = 310
        let expandedHeight: CGFloat = min(geo.size.height * 0.78, 580)

        let contentMaxHeight: CGFloat
        switch sheetDetent {
        case .minimized:
            contentMaxHeight = 0
        case .medium:
            contentMaxHeight = mediumHeight
        case .expanded:
            contentMaxHeight = expandedHeight
        }

        return VStack(spacing: 0) {
            if sheetDetent == .minimized {
                // Compact Peek State: Handle + slim info & spoof action bar
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)

                    minimizedPeekBar
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        sheetDetent = .medium
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            if value.translation.height < -20 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    sheetDetent = .medium
                                }
                            }
                        }
                )
            } else {
                // Header Bar with Drag Handle & Collapse Controls
                sheetHeaderBar

                sidebarContent
                    .frame(maxHeight: contentMaxHeight)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Bottom safe area spacing so buttons sit cleanly above home indicator
            Spacer(minLength: 0)
                .frame(height: bottomSafeInset)
        }
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .shadow(color: Color.black.opacity(0.28), radius: 12, x: 0, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - iPhone Header Bar (Medium / Expanded)
    private var sheetHeaderBar: some View {
        HStack(spacing: 8) {
            // Mode Title & Icon
            HStack(spacing: 6) {
                Image(systemName: selectedTab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                Text(selectedTab.rawValue)
                    .font(.system(size: 13, weight: .bold))
            }

            Spacer()

            // Drag handle capsule in the center
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)

            Spacer()

            // Expand / Minimize Buttons
            HStack(spacing: 8) {
                if sheetDetent == .medium {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetDetent = .expanded
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Expand Full")
                }

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        sheetDetent = .minimized
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Minimize Controls")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                switch sheetDetent {
                case .minimized:
                    sheetDetent = .medium
                case .medium:
                    sheetDetent = .minimized
                case .expanded:
                    sheetDetent = .medium
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        if value.translation.height < -25 {
                            switch sheetDetent {
                            case .minimized:
                                sheetDetent = .medium
                            case .medium:
                                sheetDetent = .expanded
                            case .expanded:
                                break
                            }
                        } else if value.translation.height > 25 {
                            switch sheetDetent {
                            case .expanded:
                                sheetDetent = .medium
                            case .medium:
                                sheetDetent = .minimized
                            case .minimized:
                                break
                            }
                        }
                    }
                }
        )
    }

    // MARK: - iPhone Minimized Peek Bar
    private var minimizedPeekBar: some View {
        HStack(spacing: 12) {
            // Mode & Coordinate summary
            HStack(spacing: 8) {
                Image(systemName: selectedTab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)

                    Text(String(format: "%.4f°, %.4f°", targetCoordinate.latitude, targetCoordinate.longitude))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick Spoof Trigger
            Button {
                connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: connectionManager.isSpoofingActive ? "checkmark.circle.fill" : "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(connectionManager.isSpoofingActive ? "Spoofing" : "Spoof")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(connectionManager.isSpoofingActive ? .green : .blue)
            .controlSize(.small)
            .disabled(!connectionManager.status.isConnected)

            // Expand Chevron
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    sheetDetent = .medium
                }
            } label: {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Expand Controls")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
