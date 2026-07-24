import SwiftUI

struct VhostListView: View {
    @Environment(VhostStore.self) private var vhostStore
    @State private var editingVhost: Vhost?
    @State private var isPresentingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(vhostStore.vhosts) { vhost in
                    VhostRow(vhost: vhost)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                vhostStore.delete(vhost)
                            }
                            Button("Edit") { editingVhost = vhost }
                        }
                }
            }
            .navigationTitle("Vhosts")
            .toolbar {
                ToolbarItem {
                    Button {
                        isPresentingNew = true
                    } label: {
                        Label("Add Vhost", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .sheet(item: $editingVhost) { vhost in
            VhostEditorView(vhost: vhost, isNew: false)
        }
        .sheet(isPresented: $isPresentingNew) {
            VhostEditorView(vhost: Vhost(domain: "", kind: .staticSite), isNew: true)
        }
    }
}

private struct VhostRow: View {
    @Environment(VhostStore.self) private var vhostStore
    let vhost: Vhost

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(vhost.domain).font(.body.bold())
                Text(vhost.kind.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("SSL", isOn: Binding(
                get: { vhost.sslEnabled },
                set: { _ in vhostStore.toggleSSL(vhost) }
            ))
            .labelsHidden()
            Toggle("Enabled", isOn: Binding(
                get: { vhost.isEnabled },
                set: { _ in vhostStore.toggleEnabled(vhost) }
            ))
            .labelsHidden()
        }
    }
}
