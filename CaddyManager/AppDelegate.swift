import AppKit
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager", category: "AppDelegate")

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
        NSApp.setActivationPolicy(.accessory)
        syncLoginItemRegistration()

        healthCheckService.configure(
            settings: settings,
            processController: processController,
            helperInstaller: helperInstaller,
            vhosts: { [weak self] in self?.vhostStore.vhosts ?? [] }
        )
        healthCheckService.start()

        Task {
            await vhostStore.regenerateAndReload()

            if helperInstaller.isEnabled {
                do {
                    try await helperClient.installPFRedirect(httpPort: settings.httpPort, httpsPort: settings.httpsPort)
                } catch {
                    Self.logger.error("Failed to re-assert pf redirect on launch: \(error.localizedDescription, privacy: .public)")
                }
            }
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
            Self.logger.error("Failed to sync login item registration: \(error.localizedDescription, privacy: .public)")
        }
    }
}
