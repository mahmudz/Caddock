import SwiftUI

struct VhostEditorView: View {
    @Environment(VhostStore.self) private var vhostStore
    @Environment(\.dismiss) private var dismiss

    @State private var vhost: Vhost
    @State private var issues: [VhostValidationIssue] = []
    private let isNew: Bool

    init(vhost: Vhost, isNew: Bool) {
        _vhost = State(initialValue: vhost)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                validationBanner

                Form {
                    Section {
                        TextField("myproject.test", text: $vhost.domain)
                            .textFieldStyle(.roundedBorder)
                        Picker("Type", selection: $vhost.kind) {
                            ForEach(Vhost.Kind.allCases, id: \.self) { kind in
                                Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                            }
                        }
                    } header: {
                        Label("Domain", systemImage: "globe")
                    }

                    switch vhost.kind {
                    case .staticSite:
                        Section {
                            TextField("Document root", text: documentRootBinding)
                        } header: {
                            Label("Static Site", systemImage: vhost.kind.systemImage)
                        } footer: {
                            Text("Serves files directly from this folder via Caddy's file_server.")
                        }
                    case .phpSite:
                        Section {
                            TextField("Document root", text: documentRootBinding)
                            TextField("PHP-FPM socket path", text: phpSocketPathBinding)
                        } header: {
                            Label("PHP Site", systemImage: vhost.kind.systemImage)
                        } footer: {
                            Text("Serves files from this folder, routing .php requests to PHP-FPM over a unix socket.")
                        }
                    case .reverseProxy:
                        Section {
                            TextField("Target (host:port)", text: proxyTargetBinding)
                        } header: {
                            Label("Reverse Proxy", systemImage: vhost.kind.systemImage)
                        } footer: {
                            Text("Forwards requests to a local process, e.g. 127.0.0.1:3000.")
                        }
                    }

                    Section {
                        Toggle(isOn: $vhost.sslEnabled) {
                            Label("SSL enabled", systemImage: "lock")
                        }
                        Toggle(isOn: $vhost.isEnabled) {
                            Label("Enabled", systemImage: "power")
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(.top, issues.isEmpty ? 0 : 4)
        }
        .frame(minWidth: 440, minHeight: 400)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear(perform: normalizeFieldsForKind)
        .onChange(of: vhost.kind) { _, _ in normalizeFieldsForKind() }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(issues) { issue in
                    Label(
                        issue.message,
                        systemImage: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
        }
    }

    private var documentRootBinding: Binding<String> {
        Binding(get: { vhost.documentRoot ?? "" }, set: { vhost.documentRoot = $0 })
    }

    private var phpSocketPathBinding: Binding<String> {
        Binding(get: { vhost.phpSocketPath ?? "" }, set: { vhost.phpSocketPath = $0 })
    }

    private var proxyTargetBinding: Binding<String> {
        Binding(get: { vhost.proxyTarget ?? "" }, set: { vhost.proxyTarget = $0 })
    }

    private func normalizeFieldsForKind() {
        switch vhost.kind {
        case .staticSite:
            vhost.phpSocketPath = nil
            vhost.proxyTarget = nil
        case .phpSite:
            vhost.proxyTarget = nil
        case .reverseProxy:
            vhost.documentRoot = nil
            vhost.phpSocketPath = nil
        }
    }

    private func save() {
        let result = isNew ? vhostStore.add(vhost) : vhostStore.update(vhost)
        issues = result
        if !result.contains(where: { $0.severity == .error }) {
            dismiss()
        }
    }
}
