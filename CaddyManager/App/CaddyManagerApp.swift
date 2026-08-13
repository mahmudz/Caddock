import SwiftUI

@main
struct CaddyManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(
            "CaddyManager",
            systemImage: menuBarIcon,
            isInserted: menuBarInserted
        ) {
            MenuBarView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
                .environment(appDelegate.vhostStore)
                .environment(appDelegate.helperInstaller)
                .environment(appDelegate.vhostEditorSession)
                .environment(appDelegate.healthCheckService)
        }
        .menuBarExtraStyle(.window)

        Window("Vhosts", id: "vhosts") {
            VhostListView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
                .environment(appDelegate.vhostStore)
                .environment(appDelegate.vhostEditorSession)
                .environment(appDelegate.helperInstaller)
                .environment(appDelegate.healthCheckService)
        }

        Window("Logs", id: "logs") {
            LogsView()
        }

        Window("Docker Compose", id: "docker-compose") {
            DockerComposeInjectView()
                .environment(appDelegate.vhostStore)
        }

        WindowGroup("Site Logs", id: "site-logs", for: UUID.self) { $vhostID in
            if let vhostID, let vhost = appDelegate.vhostStore.vhosts.first(where: { $0.id == vhostID }) {
                SiteLogsView(vhost: vhost)
            } else {
                Text("Vhost not found.")
                    .frame(minWidth: 320, minHeight: 200)
            }
        }
        .defaultLaunchBehavior(.suppressed)

        Window("Vhost", id: "vhost-editor") {
            VhostEditorWindowContent()
                .environment(appDelegate.vhostEditorSession)
                .environment(appDelegate.vhostStore)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultPosition(.center)
        .windowResizability(.contentSize)

        WindowGroup("Setup", id: "setup") {
            SetupWizardView()
                .environment(appDelegate.settings)
                .environment(appDelegate.vhostStore)
                .environment(appDelegate.setupGate)
                .environment(appDelegate.helperInstaller)
                .containerBackground(.thinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(appDelegate.setupGate.isComplete ? .suppressed : .presented)

        Settings {
            SettingsView()
                .environment(appDelegate.settings)
                .environment(appDelegate.processController)
                .environment(appDelegate.helperInstaller)
                .environment(appDelegate.vhostStore)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { appDelegate.setupGate.isComplete },
            set: { newValue in
                if newValue {
                    appDelegate.setupGate.markComplete(settings: appDelegate.settings)
                }
            }
        )
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
