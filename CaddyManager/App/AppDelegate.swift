import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = AppLogger(category: "AppDelegate")

    let settings: AppSettings
    let setupGate: SetupGate
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
        self.setupGate = SetupGate(settings: settings)
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
            vhosts: { [weak self] in self?.vhostStore.vhosts ?? [] }
        )

        if setupGate.isComplete {
            enterMenuBarMode(startServices: true)
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func finishSetup() {
        guard !setupGate.isComplete else { return }
        setupGate.markComplete(settings: settings)
        enterMenuBarMode(startServices: true)
    }

    private func enterMenuBarMode(startServices: Bool) {
        NSApp.setActivationPolicy(.accessory)
        guard startServices else { return }

        healthCheckService.start()
        Task {
            await vhostStore.regenerateAndReload()

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
        !setupGate.isComplete
    }

    @objc private func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async {
            guard self.setupGate.isComplete else { return }
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
