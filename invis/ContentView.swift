//
//  ContentView.swift
//  invis
//
//  Main application container with Liquid Glass design system.
//  Strictly conforms to iOS Human Interface Guidelines:
//  Translucent layered materials, specular edge highlights,
//  clean typography, semantic SF Symbols, and zero emojis.
//

import SwiftUI
import MapKit
import CoreLocation

public struct ContentView: View {
    @StateObject private var connectionManager = WiredConnectionManager.shared

    // Active target coordinate (Cupertino default)
    @State private var targetCoordinate = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
    @State private var targetAltitude: Double = 15.0
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    // Navigation Tab Selection
    @State private var selectedTab: ControlTab = .instantSpoof

    public enum ControlTab: String, CaseIterable, Identifiable {
        case instantSpoof = "Location"
        case routePlanner = "Route"

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
            // Floating Top Wired Status Bar
            WiredStatusView()

            // Adaptive Map & Control Layout
            GeometryReader { geo in
                if geo.size.width > 720 {
                    // iPad Landscape / Split View
                    HStack(spacing: 0) {
                        sidebarContent
                            .frame(width: 360)
                            .background(.ultraThinMaterial)

                        Divider()

                        MapView(
                            targetCoordinate: $targetCoordinate,
                            targetAltitude: $targetAltitude,
                            routeCoordinates: routeCoordinates,
                            showBottomInfoBar: true
                        )
                    }
                } else {
                    // iPhone Portrait Stack with Liquid Glass Bottom Sheet
                    ZStack(alignment: .bottom) {
                        MapView(
                            targetCoordinate: $targetCoordinate,
                            targetAltitude: $targetAltitude,
                            routeCoordinates: routeCoordinates,
                            showBottomInfoBar: false
                        )

                        // Collapsible Liquid Glass Sheet
                        iPhoneGlassControlSheet(geo: geo)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Sidebar / Sheet Content
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Segmented Glass Mode Picker
            HStack(spacing: 4) {
                ForEach(ControlTab.allCases) { tab in
                    Button {
                        HapticFeedback.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab ?
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)) :
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.clear)
                        )
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.5)

            // Active Panel View
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

    // MARK: - iPhone Liquid Glass Sheet
    public enum SheetDetent: Equatable {
        case minimized
        case medium
        case expanded
    }

    @State private var sheetDetent: SheetDetent = .minimized

    private func iPhoneGlassControlSheet(geo: GeometryProxy) -> some View {
        let bottomSafeInset = max(geo.safeAreaInsets.bottom, 16)
        let mediumHeight: CGFloat = 320
        let expandedHeight: CGFloat = min(geo.size.height * 0.78, 560)

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
                // Minimized Peek Pill
                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 4.5)
                        .padding(.top, 8)

                    minimizedPeekBar
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        sheetDetent = .medium
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { value in
                            if value.translation.height < -20 {
                                HapticFeedback.selection()
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

            Spacer(minLength: 0)
                .frame(height: bottomSafeInset)
        }
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
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
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.40),
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - iPhone Header Bar (Medium / Expanded)
    private var sheetHeaderBar: some View {
        HStack(spacing: 8) {
            // Mode Indicator
            HStack(spacing: 6) {
                Image(systemName: selectedTab.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)

                Text(selectedTab.rawValue)
                    .font(.system(size: 13, weight: .bold))
            }

            Spacer()

            // Center Grabber Handle
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4.5)

            Spacer()

            // Expand / Minimize Controls
            HStack(spacing: 6) {
                if sheetDetent == .medium {
                    Button {
                        HapticFeedback.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            sheetDetent = .expanded
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        sheetDetent = .minimized
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticFeedback.selection()
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
                    HapticFeedback.selection()
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
                    .background(Color.blue.opacity(0.10))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(String(format: "%.4f°, %.4f°", targetCoordinate.latitude, targetCoordinate.longitude))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick Simulate Button
            Button {
                HapticFeedback.impact(.medium)
                connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: connectionManager.isSpoofingActive ? "location.fill" : "location")
                        .font(.system(size: 10, weight: .semibold))
                    Text(connectionManager.isSpoofingActive ? "Simulating" : "Simulate")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(connectionManager.isSpoofingActive ? Color.green : Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!connectionManager.status.isConnected)

            // Expand Chevron
            Button {
                HapticFeedback.selection()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    sheetDetent = .medium
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}
