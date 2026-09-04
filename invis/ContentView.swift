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

            #if os(macOS)
            // macOS Layout: NavigationSplitView
            NavigationSplitView {
                sidebarContent
                    .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 460)
            } detail: {
                MapView(
                    targetCoordinate: $targetCoordinate,
                    targetAltitude: $targetAltitude,
                    routeCoordinates: routeCoordinates
                )
            }
            #else
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
                            routeCoordinates: routeCoordinates
                        )
                    }
                } else {
                    // iPhone Portrait Stack
                    ZStack(alignment: .bottom) {
                        MapView(
                            targetCoordinate: $targetCoordinate,
                            targetAltitude: $targetAltitude,
                            routeCoordinates: routeCoordinates
                        )

                        // Collapsible Bottom Card for iPhone
                        iPhoneControlSheet
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 950, minHeight: 650)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    connectionManager.startHardwareDiscovery()
                } label: {
                    Label("Detect Pico", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Scan for Raspberry Pi Pico over physical USB")

                Button(role: .destructive) {
                    connectionManager.resetLocation()
                } label: {
                    Label("Reset GPS", systemImage: "arrow.counterclockwise.circle.fill")
                        .foregroundColor(.red)
                }
                .help("Safety Reset: Restores physical GPS")
            }
        }
        #endif
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

    #if os(iOS)
    @State private var isSheetExpanded: Bool = false

    private var iPhoneControlSheet: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.vertical, 8)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSheetExpanded.toggle()
                    }
                }

            sidebarContent
                .frame(maxHeight: isSheetExpanded ? 460 : 180)
        }
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: -4)
        .ignoresSafeArea(edges: .bottom)
    }
    #endif
}

#Preview {
    ContentView()
}
