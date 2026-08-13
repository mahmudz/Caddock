import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VhostListView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VhostStore.self) private var vhostStore
    @Environment(VhostEditorSession.self) private var vhostEditorSession
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(HealthCheckService.self) private var healthCheckService
    @Environment(\.openWindow) private var openWindow

    @State private var pendingDeletion: Vhost?
    @State private var searchText = ""
    @State private var filter: VhostFilter = .all
    @State private var importExportMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if vhostStore.vhosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Vhosts", systemImage: "server.rack")
                    } description: {
                        Text("Add a vhost to start serving a site through Caddy.")
                    } actions: {
                        Button("Add Vhost", action: openNewVhostEditor)
                        Button("Import…", action: importVhosts)
                    }
                } else if filteredVhosts.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text(emptyResultsDescription)
                    } actions: {
                        if !searchText.isEmpty || filter != .all {
                            Button("Clear Filters") { clearFilters() }
                        }
                    }
                } else {
                    List {
                        if filter == .all && searchText.isEmpty {
                            if !enabledVhosts.isEmpty {
                                vhostRows(enabledVhosts)
                            }
                            if !disabledVhosts.isEmpty {
                                vhostRows(disabledVhosts)
                            }
                        } else {
                            vhostRows(filteredVhosts)
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .navigationTitle("Vhosts")
            .searchable(text: $searchText, prompt: "Search domains, paths, or type")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Filter", selection: $filter) {
                        ForEach(VhostFilter.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("Import", action: importVhosts)
                        Button("Export", action: exportVhosts)
                            .disabled(vhostStore.vhosts.isEmpty)
                    } label: {
                        Label("Import / Export", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openNewVhostEditor) {
                        Label("Add Vhost", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let importExportMessage {
                    Text(importExportMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .confirmationDialog(
            "Delete \(pendingDeletion?.domain ?? "this vhost")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let vhost = pendingDeletion {
                    vhostStore.delete(vhost)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes it from the Caddyfile and stops serving it. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func vhostRows(_ vhosts: [Vhost]) -> some View {
        ForEach(vhosts) { vhost in
            VhostRow(
                vhost: vhost,
                issues: VhostValidator.validate(vhost, existing: vhostStore.vhosts),
                health: healthCheckService.status(for: vhost.id),
                onOpen: { openInBrowser(vhost) },
                onEdit: { openVhostEditor(vhost) },
                onDelete: { pendingDeletion = vhost }
            )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { openVhostEditor(vhost) }
            .contextMenu {
                Button("Open in Browser") { openInBrowser(vhost) }
                    .disabled(!vhost.isEnabled)
                Divider()
                Button("Edit") { openVhostEditor(vhost) }
                Button("Delete", role: .destructive) { pendingDeletion = vhost }
            }
            .swipeActions {
                Button("Delete", role: .destructive) { pendingDeletion = vhost }
                Button("Edit") { openVhostEditor(vhost) }
                    .tint(.accentColor)
            }
        }
    }

    private var filteredVhosts: [Vhost] {
        vhostStore.vhosts
            .filter(matchesFilter)
            .filter(matchesSearch)
            .sorted { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
    }

    private var enabledVhosts: [Vhost] {
        filteredVhosts.filter(\.isEnabled)
    }

    private var disabledVhosts: [Vhost] {
        filteredVhosts.filter { !$0.isEnabled }
    }

    private func matchesFilter(_ vhost: Vhost) -> Bool {
        switch filter {
        case .all: return true
        case .enabled: return vhost.isEnabled
        case .disabled: return !vhost.isEnabled
        }
    }

    private func matchesSearch(_ vhost: Vhost) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystack = [
            vhost.domain,
            vhost.aliases.joined(separator: " "),
            vhost.kind.displayName,
            vhost.documentRoot ?? "",
            vhost.phpSocketPath ?? "",
            vhost.proxyTarget ?? "",
        ]
        .joined(separator: " ")
        .localizedLowercase

        return haystack.localizedCaseInsensitiveContains(query)
    }

    private var emptyResultsDescription: String {
        if !searchText.isEmpty {
            return "No vhosts match \"\(searchText)\"."
        }
        switch filter {
        case .enabled: return "No enabled vhosts."
        case .disabled: return "No disabled vhosts."
        case .all: return "No vhosts found."
        }
    }

    private func clearFilters() {
        searchText = ""
        filter = .all
    }

    private func openInBrowser(_ vhost: Vhost) {
        guard let url = vhost.browserURL(
            settings: settings,
            useStandardPorts: helperInstaller.isEnabled
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openNewVhostEditor() {
        AppWindowPresenter.presentVhostEditor(
            session: vhostEditorSession,
            openWindow: openWindow,
            route: .newVhost()
        )
    }

    private func openVhostEditor(_ vhost: Vhost) {
        AppWindowPresenter.presentVhostEditor(
            session: vhostEditorSession,
            openWindow: openWindow,
            route: .edit(vhost)
        )
    }

    private func hostingWindow() -> NSWindow? {
        NSApp.windows.first { window in
            !AppWindowPresenter.isMenuBarPanel(window)
                && (window.title == "Vhosts" || window.identifier?.rawValue.localizedCaseInsensitiveContains("vhosts") == true)
        } ?? NSApp.keyWindow
    }

    private var importExportType: UTType {
        UTType(filenameExtension: VhostImportExport.fileExtension) ?? .json
    }

    private func exportVhosts() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [importExportType]
        panel.nameFieldStringValue = "vhosts.\(VhostImportExport.fileExtension)"
        panel.canCreateDirectories = true

        let finish: (URL?) -> Void = { url in
            guard let url else { return }
            do {
                let data = try vhostStore.exportData()
                try data.write(to: url, options: .atomic)
                importExportMessage = "Exported \(vhostStore.vhosts.count) site(s)."
            } catch {
                importExportMessage = error.localizedDescription
            }
        }

        if let window = hostingWindow() {
            panel.beginSheetModal(for: window) { response in
                finish(response == .OK ? panel.url : nil)
            }
        } else if panel.runModal() == .OK {
            finish(panel.url)
        }
    }

    private func importVhosts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [importExportType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let finish: (URL?) -> Void = { url in
            guard let url else { return }
            do {
                let data = try Data(contentsOf: url)
                let skipped = try vhostStore.importData(data)
                importExportMessage = skipped > 0
                    ? "Import done. Skipped \(skipped) duplicate(s)."
                    : "Import done."
            } catch {
                importExportMessage = error.localizedDescription
            }
        }

        if let window = hostingWindow() {
            panel.beginSheetModal(for: window) { response in
                finish(response == .OK ? panel.url : nil)
            }
        } else if panel.runModal() == .OK {
            finish(panel.url)
        }
    }
}

private enum VhostFilter: CaseIterable {
    case all
    case enabled
    case disabled

    var title: String {
        switch self {
        case .all: return "All"
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        }
    }
}

private struct VhostRow: View {
    @Environment(VhostStore.self) private var vhostStore

    let vhost: Vhost
    let issues: [VhostValidationIssue]
    let health: BackendHealthStatus
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }

    private var hasWarnings: Bool {
        !hasErrors && issues.contains { $0.severity == .warning }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)

            Image(systemName: vhost.kind.systemImage)
                .font(.title3)
                .foregroundStyle(vhost.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vhost.domain)
                        .font(.body.bold())
                        .foregroundStyle(vhost.isEnabled ? .primary : .secondary)
                        .lineLimit(1)

                    if hasErrors || hasWarnings {
                        Image(systemName: hasErrors ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(hasErrors ? .red : .orange)
                            .help(issues.map(\.message).joined(separator: "\n"))
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovering {
                HStack(spacing: 8) {
                    Button(action: onOpen) {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")
                    .disabled(!vhost.isEnabled)

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }

            Button {
                vhostStore.toggleSSL(vhost)
            } label: {
                Image(systemName: vhost.sslEnabled ? "lock.fill" : "lock.open")
                    .foregroundStyle(vhost.sslEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(vhost.sslEnabled ? "SSL enabled" : "SSL disabled")

            Toggle("Enabled", isOn: Binding(
                get: { vhost.isEnabled },
                set: { _ in vhostStore.toggleEnabled(vhost) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .opacity(vhost.isEnabled ? 1 : 0.72)
        .onHover { isHovering = $0 }
    }

    private var subtitle: String {
        let aliasSuffix = vhost.aliases.isEmpty
            ? ""
            : " · +\(vhost.aliases.count) alias\(vhost.aliases.count == 1 ? "" : "es")"
        let detail: String
        switch vhost.kind {
        case .staticSite, .phpSite: detail = vhost.documentRoot ?? ""
        case .reverseProxy: detail = vhost.proxyTarget ?? ""
        }
        let base = detail.isEmpty ? vhost.kind.displayName : "\(vhost.kind.displayName) · \(detail)"
        return base + aliasSuffix
    }

    private var healthColor: Color {
        switch health {
        case .healthy: return .green
        case .unhealthy: return .red
        case .checking: return .yellow
        case .unknown: return .secondary.opacity(0.4)
        }
    }
}
