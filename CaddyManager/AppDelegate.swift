import AppKit
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.mahmudz.CaddyManager", category: "AppDelegate")

    let settings: AppSettings
    let processController: CaddyProcessController
    let vhostStore: VhostStore

    override init() {
        let settings = AppSettings()
        self.settings = settings
        self.processController = CaddyProcessController(settings: settings)
        self.vhostStore = VhostStore(settings: settings, processController: processController)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        syncLoginItemRegistration()

        Task {
            await vhostStore.regenerateAndReload()
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
