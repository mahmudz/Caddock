import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CaddyProcessController.self) private var processController
    @Environment(VhostStore.self) private var vhostStore
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""
    @State private var isPresentingNewVhost = false

    private let menuWidth: CGFloat = 280
    private let visibleVhostLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader

            Divider()

            topActions

            searchField

            vhostList

            Divider()

            footerActions
        }
        .frame(width: menuWidth)
        .sheet(isPresented: $isPresentingNewVhost) {
            VhostEditorView(vhost: Vhost(domain: "", kind: .staticSite), isNew: false)
                .environment(vhostStore)
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(statusColor)
                Text(statusText)
                Spacer()
                Toggle("", isOn: Binding(
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
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if let lastError = vhostStore.lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var topActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuActionRow(title: "New Vhost", systemImage: "plus") {
                isPresentingNewVhost = true
            }
            MenuActionRow(title: "Manage Vhosts", systemImage: "list.bullet.rectangle") {
                openAppWindow(id: "vhosts")
            }
        }
        .padding(.vertical, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search vhosts", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var vhostList: some View {
        if filteredVhosts.isEmpty {
            Text(searchText.isEmpty ? "No enabled vhosts." : "No matching vhosts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(displayedVhosts) { vhost in
                    VhostMenuRow(vhost: vhost) {
                        openInBrowser(vhost)
                    }
                }

                if filteredVhosts.count > displayedVhosts.count {
                    MenuActionRow(title: "View All Vhosts", systemImage: "ellipsis") {
                        openAppWindow(id: "vhosts")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuActionRow(title: "Logs", systemImage: "doc.text") {
                openAppWindow(id: "logs")
            }
            MenuActionRow(title: "Settings", systemImage: "gearshape") {
                openSettingsWindow()
            }

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            MenuActionRow(title: "Quit CaddyManager", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
    }

    private var filteredVhosts: [Vhost] {
        let enabled = vhostStore.vhosts
            .filter(\.isEnabled)
            .sorted { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }

        guard !searchText.isEmpty else { return enabled }

        return enabled.filter {
            $0.domain.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var displayedVhosts: [Vhost] {
        let limit = searchText.isEmpty ? visibleVhostLimit : 10
        return Array(filteredVhosts.prefix(limit))
    }

    private func openInBrowser(_ vhost: Vhost) {
        guard let url = vhost.browserURL(
            settings: settings,
            useStandardPorts: helperInstaller.isEnabled
        ) else { return }
        NSWorkspace.shared.open(url)
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


