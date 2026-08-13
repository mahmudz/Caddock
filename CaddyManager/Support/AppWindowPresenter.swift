import AppKit
import SwiftUI

enum AppWindowPresenter {
    enum Target: Equatable {
        case settings
        case window(id: String)
    }

    private static let settingsTabTitles = Set(["General", "Ports", "Certificates", "Advanced", "About"])
    private static let vhostEditorTitles = Set(["Vhost", "New Vhost", "Edit Vhost"])

    /// Blocks flipping back to `.accessory` while a window is still being created.
    /// MenuBarExtra close otherwise races the new window and steals focus.
    private static var suppressAccessoryUntil: Date?
    private static var hideAccessoryWorkItem: DispatchWorkItem?
    private static var pendingTarget: Target?

    static func present(open: @escaping () -> Void, target: Target) {
        beginPresentation(target: target)
        // Call open() before dismissing the extra — OpenWindowAction dies with that window.
        open()
        dismissMenuBarExtra()
        focus(target: target, attempt: 0)
    }

    static func presentVhostEditor(
        session: VhostEditorSession,
        openWindow: OpenWindowAction,
        route: VhostEditorRoute
    ) {
        session.present(route)
        present(open: { openWindow(id: "vhost-editor") }, target: .window(id: "vhost-editor"))
    }

    static func handleDidBecomeActive() {
        guard let pendingTarget else { return }
        if let window = findWindow(for: pendingTarget, includeHidden: true) {
            bringToFront(window)
            self.pendingTarget = nil
        }
    }

    static func hideDockIconIfNoWindows(excluding closingWindow: NSWindow? = nil) {
        if let closingWindow, isMenuBarPanel(closingWindow) {
            return
        }

        hideAccessoryWorkItem?.cancel()
        let work = DispatchWorkItem {
            if let until = suppressAccessoryUntil, Date() < until {
                return
            }
            let remaining = NSApp.windows.contains { window in
                guard window !== closingWindow else { return false }
                guard window.canBecomeKey, !isMenuBarPanel(window) else { return false }
                return window.isVisible || window.isMiniaturized
            }
            guard !remaining else { return }
            pendingTarget = nil
            NSApp.setActivationPolicy(.accessory)
        }
        hideAccessoryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private static func beginPresentation(target: Target) {
        pendingTarget = target
        suppressAccessoryUntil = Date().addingTimeInterval(1.5)
        hideAccessoryWorkItem?.cancel()
        NSApp.setActivationPolicy(.regular)
        activateApp()
    }

    private static func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    private static func dismissMenuBarExtra() {
        for window in NSApp.windows where isMenuBarPanel(window) {
            window.orderOut(nil)
        }
    }

    private static func bringToFront(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        activateApp()
    }

    private static func focus(target: Target, attempt: Int) {
        let delays: [TimeInterval] = [0.0, 0.05, 0.12, 0.25, 0.45, 0.8]
        guard attempt < delays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) {
            dismissMenuBarExtra()
            if let window = findWindow(for: target, includeHidden: true) {
                bringToFront(window)
                pendingTarget = nil
                return
            }
            focus(target: target, attempt: attempt + 1)
        }
    }

    private static func findWindow(for target: Target, includeHidden: Bool = false) -> NSWindow? {
        candidateWindows(includeHidden: includeHidden).first { window in
            matches(target: target, window: window)
        }
    }

    private static func matches(target: Target, window: NSWindow) -> Bool {
        switch target {
        case .settings:
            return isSettingsWindow(window)
        case .window(let id):
            return matchesWindowID(window, id: id)
                || window.title == title(for: id)
                || (id == "vhost-editor" && isVhostEditorWindow(window))
        }
    }

    private static func candidateWindows(includeHidden: Bool = false) -> [NSWindow] {
        NSApp.windows.filter { window in
            window.canBecomeKey
                && !isMenuBarPanel(window)
                && (window.isVisible || window.isMiniaturized || includeHidden)
        }
    }

    static func isMenuBarPanel(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        if className.localizedCaseInsensitiveContains("Popover") { return true }
        if className.localizedCaseInsensitiveContains("StatusBar") { return true }
        if className.localizedCaseInsensitiveContains("MenuBarExtra") { return true }
        if className.localizedCaseInsensitiveContains("NSStatusItem") { return true }
        if window.level == .popUpMenu { return true }
        if window.level == .statusBar { return true }
        return false
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true {
            return true
        }
        if settingsTabTitles.contains(window.title) {
            return true
        }
        return window.title.localizedCaseInsensitiveContains("settings")
    }

    private static func isVhostEditorWindow(_ window: NSWindow) -> Bool {
        vhostEditorTitles.contains(window.title)
    }

    private static func matchesWindowID(_ window: NSWindow, id: String) -> Bool {
        guard let identifier = window.identifier?.rawValue else { return false }
        if identifier == id { return true }
        if identifier.hasSuffix(".\(id)") { return true }
        if identifier.split(separator: ".").last.map(String.init) == id { return true }
        return false
    }

    private static func title(for id: String) -> String {
        switch id {
        case "vhosts": return "Vhosts"
        case "logs": return "Logs"
        case "vhost-editor": return "Vhost"
        case "docker-compose": return "Docker Compose"
        case "site-logs": return "Site Logs"
        case "setup": return "Setup"
        default: return id.capitalized
        }
    }
}
