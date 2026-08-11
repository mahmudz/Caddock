import AppKit
import SwiftUI

@MainActor
enum CaddyOnboardingPresenter {
    private static var window: NSWindow?

    static func presentIfNeeded(settings: AppSettings, vhostStore: VhostStore) {
        let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride)
        if binary != nil {
            if !settings.hasCompletedCaddyOnboarding {
                settings.hasCompletedCaddyOnboarding = true
            }
            return
        }
        guard !settings.hasCompletedCaddyOnboarding else { return }
        present(settings: settings, vhostStore: vhostStore)
    }

    static func present(settings: AppSettings, vhostStore: VhostStore) {
        if let window, window.isVisible {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = CaddyOnboardingView(onClose: close)
            .environment(settings)
            .environment(vhostStore)

        let hosting = NSHostingController(rootView: root)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.title = "Install Caddy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 300))
        window.center()
        window.delegate = CloseDelegate.shared

        // Soft rounded shadow matching the clipped glass content.
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.close()
        window = nil
        AppWindowPresenter.hideDockIconIfNoWindows()
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        static let shared = CloseDelegate()

        func windowWillClose(_ notification: Notification) {
            CaddyOnboardingPresenter.window = nil
            DispatchQueue.main.async {
                AppWindowPresenter.hideDockIconIfNoWindows()
            }
        }
    }
}
