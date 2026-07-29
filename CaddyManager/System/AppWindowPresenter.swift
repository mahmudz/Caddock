import AppKit
import SwiftUI

enum AppWindowPresenter {
    enum Target: Equatable {
        case settings
        case window(id: String)
    }

    private static let settingsTabTitles = Set(["General", "Ports", "Advanced", "About"])
    private static let vhostEditorTitles = Set(["Vhost", "New Vhost", "Edit Vhost"])

    static func present(open: @escaping () -> Void, target: Target) {
        NSApp.setActivationPolicy(.regular)
        open()
        focus(target: target, attempt: 0)
    }

    static func presentVhostEditor(
        session: VhostEditorSession,
        openWindow: OpenWindowAction,
        route: VhostEditorRoute
    ) {
        session.present(route)
        NSApp.setActivationPolicy(.regular)

        if let existing = findWindow(for: .window(id: "vhost-editor"), includeHidden: true) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            present(open: { openWindow(id: "vhost-editor") }, target: .window(id: "vhost-editor"))
        }
    }

    private static func focus(target: Target, attempt: Int) {
        let delay = attempt == 0 ? 0.0 : 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)

            if let window = findWindow(for: target) {
                window.makeKeyAndOrderFront(nil)
                return
            }

            if attempt < 4 {
                focus(target: target, attempt: attempt + 1)
            }
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
                && (window.isVisible || includeHidden)
        }
    }

    private static func isMenuBarPanel(_ window: NSWindow) -> Bool {
        let className = String(describing: type(of: window))
        if className.localizedCaseInsensitiveContains("Popover") { return true }
        if className.localizedCaseInsensitiveContains("StatusBar") { return true }
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
        return identifier == id || identifier.hasSuffix(".\(id)") || identifier.hasSuffix(id)
    }

    private static func title(for id: String) -> String {
        switch id {
        case "vhosts": return "Vhosts"
        case "logs": return "Logs"
        case "vhost-editor": return "Vhost"
        default: return id.capitalized
        }
    }
}
