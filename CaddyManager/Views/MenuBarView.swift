import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(CaddyProcessController.self) private var processController
    @Environment(VhostStore.self) private var vhostStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(statusColor)
                    Text(statusText)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if let lastError = vhostStore.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }

                Toggle(isOn: Binding(
                    get: { isRunning },
                    set: { shouldRun in
                        Task {
                            if shouldRun {
                                await vhostStore.regenerateAndReload()
                            } else {
                                await processController.stop()
                            }
                        }
                    }
                )) {
                    
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.horizontal, 14)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuRow(title: "Vhosts", systemImage: "list.bullet.rectangle") {
                    openAppWindow(id: "vhosts")
                }
                MenuRow(title: "Logs", systemImage: "doc.text") {
                    openAppWindow(id: "logs")
                }
                MenuRow(title: "Settings", systemImage: "gearshape") {
                    openSettingsWindow()
                }
            }
            .padding(.vertical, 6)

            Divider()

            MenuRow(title: "Quit CaddyManager", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 6)
        }
        .frame(width: 260)
    }

    private func openAppWindow(id: String) {
        presentAppWindow {
            openWindow(id: id)
        }
    }

    private func openSettingsWindow() {
        presentAppWindow {
            openSettings()
        }
    }

    private func presentAppWindow(open: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        open()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.filter({ $0.isVisible && $0.canBecomeKey }).last {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private var isRunning: Bool {
        if case .running = processController.status { return true }
        return false
    }

    private var statusText: String {
        switch processController.status {
        case .stopped: return "Caddy Stopped"
        case .starting: return "Caddy Starting…"
        case .running: return "Caddy Running"
        case .failed: return "Caddy Failed"
        }
    }

    private var statusColor: Color {
        switch processController.status {
        case .stopped: return .secondary
        case .starting: return .yellow
        case .running: return .green
        case .failed: return .red
        }
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}
