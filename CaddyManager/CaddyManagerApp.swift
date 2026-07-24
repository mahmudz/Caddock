//
//  CaddyManagerApp.swift
//  CaddyManager
//
//  Created by mahmud on 24/7/26.
//

import SwiftUI

@main
struct CaddyManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("CaddyManager", systemImage: menuBarIcon) {
            MenuBarView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
                .environment(appDelegate.vhostStore)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Vhosts", id: "vhosts") {
            VhostListView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
                .environment(appDelegate.vhostStore)
        }

        WindowGroup("Logs", id: "logs") {
            LogsView()
        }

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
        }
    }

    private var menuBarIcon: String {
        switch appDelegate.processController.status {
        case .running: return "checkmark.circle.fill"
        case .starting: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .stopped: return "xmark.circle"
        }
    }
}
