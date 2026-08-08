import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = AppLogger(category: "AppDelegate")

    let settings: AppSettings
    let processController: CaddyProcessController
    let vhostStore: VhostStore
    let helperInstaller: HelperInstaller
    let helperClient: HelperClient
    let vhostEditorSession: VhostEditorSession
    let dnsResponder: LocalDNSResponder
    let healthCheckService: HealthCheckService

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.processController = CaddyProcessController(settings: settings)
        self.helperInstaller = HelperInstaller()
        self.helperClient = HelperClient()
        self.vhostEditorSession = VhostEditorSession()
        self.dnsResponder = LocalDNSResponder()
        self.healthCheckService = HealthCheckService()
        self.vhostStore = VhostStore(
            settings: settings,
            processController: processController,
            helperInstaller: helperInstaller,
            helperClient: helperClient,
            dnsResponder: dnsResponder
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.bootstrap()
        NSApp.setActivationPolicy(.accessory)
        syncLoginItemRegistration()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        healthCheckService.configure(
            settings: settings,
            processController: processController,
            helperInstaller: helperInstaller,
            vhosts: { [weak self] in self?.vhostStore.vhosts ?? [] }
        )
        healthCheckService.start()

        Task {
            await vhostStore.regenerateAndReload()

            // After reboot, pf redirects are gone and the helper may not be ready yet.
            // Retry privileged sync (ping → hosts → resolvers → pf) with backoff.
            if helperInstaller.isEnabled {
                let ok = await vhostStore.ensurePrivilegedNetworkingOnLaunch()
                if !ok {
                    let detail = self.vhostStore.helperSyncError ?? "unknown"
                    Self.logger.error(
                        "Privileged networking still failed after launch retries: \(detail)"
                    )
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        // Defer: willClose fires before window leaves NSApp.windows / visibility flips.
        DispatchQueue.main.async {
            AppWindowPresenter.hideDockIconIfNoWindows(excluding: closing)
        }
    }

    func syncLoginItemRegistration() {
        do {
            if settings.launchAtLogin, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !settings.launchAtLogin, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Failed to sync login item registration: \(error.localizedDescription)")
        }
    }
}
