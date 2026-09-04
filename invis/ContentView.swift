//
//  ContentView.swift
//  invis
//
//  Main application container utilizing Apple's real native sheet presentation,
//  background interaction (Apple Maps & Find My style), ultraThinMaterial,
//  and physical GPS initialization via CoreLocation.
//

import SwiftUI
import MapKit
import CoreLocation

public struct ContentView: View {
    @StateObject private var connectionManager = WiredConnectionManager.shared
    @StateObject private var locationManager = UserLocationManager.shared

    // Active target coordinate defaults to user's real location or falls back safely
    @State private var targetCoordinate = CLLocationCoordinate2D(latitude: 37.334900, longitude: -122.009020)
    @State private var targetAltitude: Double = 15.0
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []

    // Navigation & Sheet States
    @State private var selectedTab: ControlTab = .instantSpoof
    @State private var sheetDetent: PresentationDetent = .fraction(0.12)
    @State private var isSheetPresented: Bool = true
    @State private var hasSyncedUserLocation: Bool = false

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
        GeometryReader { geo in
            if geo.size.width > 720 {
                // iPad / Wide Screen Split View
                HStack(spacing: 0) {
                    sidebarPanel
                        .frame(width: 380)
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
                // iPhone: Full-Screen Map with Apple Real Native Sheet & Background Interaction
                ZStack(alignment: .top) {
                    MapView(
                        targetCoordinate: $targetCoordinate,
                        targetAltitude: $targetAltitude,
                        routeCoordinates: routeCoordinates,
                        showBottomInfoBar: false
                    )
                    .ignoresSafeArea()

                    // Top Floating Hardware Status Bar
                    WiredStatusView()
                        .padding(.top, geo.safeAreaInsets.top > 0 ? 0 : 8)
                }
                .sheet(isPresented: $isSheetPresented) {
                    sheetContainer
                        .presentationDetents([.fraction(0.12), .medium, .large], selection: $sheetDetent)
                        .presentationBackgroundInteraction(.enabled(upThrough: .large))
                        .presentationBackground(.ultraThinMaterial)
                        .presentationCornerRadius(28)
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled()
                }
            }
        }
        .onReceive(locationManager.$userLocation) { userCoord in
            guard let coord = userCoord, !hasSyncedUserLocation else { return }
            hasSyncedUserLocation = true
            targetCoordinate = coord
        }
    }

    // MARK: - iPhone Native Sheet Content
    private var sheetContainer: some View {
        VStack(spacing: 0) {
            if sheetDetent == .fraction(0.12) {
                // Minimized Apple Maps-Style Peek Bar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: selectedTab.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTab.rawValue)
                                .font(.system(size: 13, weight: .bold))
                            Text(String(format: "%.4f°, %.4f°", targetCoordinate.latitude, targetCoordinate.longitude))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        HapticFeedback.impact(.medium)
                        connectionManager.teleport(to: targetCoordinate, altitude: targetAltitude)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: connectionManager.isSpoofingActive ? "location.fill" : "location")
                            Text(connectionManager.isSpoofingActive ? "Active" : "Simulate")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(connectionManager.isSpoofingActive ? .green : .blue)
                    .disabled(!connectionManager.status.isConnected)

                    Button {
                        HapticFeedback.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            sheetDetent = .medium
                        }
                    } label: {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        sheetDetent = .medium
                    }
                }
            } else {
                // Expanded / Medium State
                VStack(spacing: 8) {
                    // Segmented Mode Picker
                    Picker("Mode", selection: $selectedTab) {
                        ForEach(ControlTab.allCases) { tab in
                            Label(tab.rawValue, systemImage: tab.iconName)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    // Active Tab Form
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
        }
    }

    // MARK: - iPad Sidebar Panel
    private var sidebarPanel: some View {
        VStack(spacing: 0) {
            WiredStatusView()

            Picker("Mode", selection: $selectedTab) {
                ForEach(ControlTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(14)

            Divider()

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
}

#Preview {
    ContentView()
}
