import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CaddyProcessController.self) private var processController
    @Environment(VhostStore.self) private var vhostStore
    @Environment(VhostEditorSession.self) private var vhostEditorSession
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(HealthCheckService.self) private var healthCheckService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var searchText = ""

    private let menuWidth: CGFloat = 300
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
        .onChange(of: processController.status) { _, _ in
            healthCheckService.checkAll()
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

            if let helperSyncError = vhostStore.helperSyncError {
                Label(helperSyncError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var topActions: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuActionRow(title: "New Vhost", systemImage: "plus") {
                openNewVhostWindow()
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
                    VhostMenuRow(
                        vhost: vhost,
                        health: healthCheckService.status(for: vhost.id),
                        onOpen: { openInBrowser(vhost) },
                        onLogs: vhost.logSource.isConfigured ? { openSiteLogs(vhost) } : nil
                    )
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
            MenuActionRow(title: "Docker Compose Injector", systemImage: "shippingbox") {
                openAppWindow(id: "docker-compose")
            }
            MenuActionRow(title: "Logs", systemImage: "doc.text") {
                openAppWindow(id: "logs")
            }
            MenuActionRow(title: "Settings", systemImage: "gearshape") {
                openSettingsWindow()
            }

            if CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) == nil {
                MenuActionRow(title: "Install Caddy…", systemImage: "arrow.down.app") {
                    AppWindowPresenter.present(open: { openWindow(id: "setup") }, target: .window(id: "setup"))
                }
            }

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

            MenuActionRow(title: "Quit Caddock", systemImage: "power") {
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
                || $0.aliases.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
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

    private func openSiteLogs(_ vhost: Vhost) {
        AppWindowPresenter.present(
            open: { openWindow(id: "site-logs", value: vhost.id) },
            target: .window(id: "site-logs")
        )
    }

    private func openNewVhostWindow() {
        AppWindowPresenter.presentVhostEditor(
            session: vhostEditorSession,
            openWindow: openWindow,
            route: .newVhost()
        )
    }

    private func openAppWindow(id: String) {
        AppWindowPresenter.present(open: { openWindow(id: id) }, target: .window(id: id))
    }

    private func openSettingsWindow() {
        AppWindowPresenter.present(open: { openSettings() }, target: .settings)
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
