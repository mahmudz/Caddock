import SwiftUI

struct VhostListView: View {
    @Environment(VhostStore.self) private var vhostStore
    @Environment(VhostEditorSession.self) private var vhostEditorSession
    @Environment(\.openWindow) private var openWindow
    @State private var pendingDeletion: Vhost?

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
                    }
                } else {
                    List {
                        ForEach(vhostStore.vhosts) { vhost in
                            VhostRow(vhost: vhost, onDelete: { pendingDeletion = vhost })
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { openVhostEditor(vhost) }
                                .contextMenu {
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
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .navigationTitle("Vhosts")
            .toolbar {
                ToolbarItem {
                    Button(action: openNewVhostEditor) {
                        Label("Add Vhost", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .confirmationDialog(
            "Delete \(pendingDeletion?.domain ?? "this vhost")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
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
}

private struct VhostRow: View {
    @Environment(VhostStore.self) private var vhostStore
    let vhost: Vhost
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vhost.kind.systemImage)
                .font(.title3)
                .foregroundStyle(vhost.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(vhost.domain)
                    .font(.body.bold())
                    .foregroundStyle(vhost.isEnabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete")
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
        .onHover { isHovering = $0 }
    }

    private var subtitle: String {
        let detail: String
        switch vhost.kind {
        case .staticSite, .phpSite: detail = vhost.documentRoot ?? ""
        case .reverseProxy: detail = vhost.proxyTarget ?? ""
        }
        return detail.isEmpty ? vhost.kind.displayName : "\(vhost.kind.displayName) · \(detail)"
    }
}
