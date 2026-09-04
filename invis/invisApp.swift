//
//  invisApp.swift
//  invis
//
//  Main entry point for the Invis Wired Location Spoofing application.
//

import SwiftUI

@main
struct invisApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 750)
        #endif
    }
}
