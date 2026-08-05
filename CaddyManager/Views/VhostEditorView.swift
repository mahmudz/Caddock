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
                    domainSection
                    kindSpecificSection
                    serverOptionsSection
                    proxyOptionsSection
                    generalSection
                }
                .formStyle(.grouped)
            }
            .padding(.top, issues.isEmpty ? 0 : 4)
        }
        .frame(minWidth: 480, minHeight: 520)
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

    // MARK: - Sections

    private var domainSection: some View {
        Section {
            TextField("myproject.test", text: $vhost.domain)
                .textFieldStyle(.roundedBorder)
            TextField("Aliases (comma-separated)", text: aliasesBinding)
                .textFieldStyle(.roundedBorder)
            Picker("Type", selection: $vhost.kind) {
                ForEach(Vhost.Kind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                }
            }
        } header: {
            Label("Domain", systemImage: "globe")
        } footer: {
            Text("Aliases serve the same site block under additional hostnames, e.g. www.myproject.test.")
        }
    }

    @ViewBuilder
    private var kindSpecificSection: some View {
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
    }

    @ViewBuilder
    private var serverOptionsSection: some View {
        switch vhost.kind {
        case .staticSite, .phpSite:
            Section {
                Toggle(isOn: $vhost.compressionEnabled) {
                    Label("Gzip compression", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                TextField("Index files", text: indexFilesBinding, prompt: Text(vhost.defaultIndexFiles()))
                    .textFieldStyle(.roundedBorder)
            } header: {
                Label("Server", systemImage: "gearshape.2")
            } footer: {
                Text("Index files are tried in order when a directory is requested. Leave blank to use the default for this site type.")
            }
        case .reverseProxy:
            EmptyView()
        }
    }

    @ViewBuilder
    private var proxyOptionsSection: some View {
        if vhost.kind == .reverseProxy {
            Section {
                Toggle(isOn: $vhost.websocketEnabled) {
                    Label("WebSocket & streaming", systemImage: "arrow.left.arrow.right")
                }
                Toggle(isOn: $vhost.preserveHostHeader) {
                    Label("Preserve Host header", systemImage: "character.textbox")
                }
                Toggle(isOn: $vhost.forwardProxyHeaders) {
                    Label("Forward client IP & scheme", systemImage: "arrow.forward")
                }
            } header: {
                Label("Proxy", systemImage: "network")
            } footer: {
                Text("WebSocket & streaming disables proxy timeouts and buffering — needed for Vite HMR, Laravel Echo, SSE, and similar backends.")
            }
        }
    }

    private var generalSection: some View {
        Section {
            Toggle(isOn: $vhost.sslEnabled) {
                Label("SSL enabled", systemImage: "lock")
            }
            Toggle(isOn: $vhost.isEnabled) {
                Label("Enabled", systemImage: "power")
            }
        }
    }

    // MARK: - Validation banner

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

    // MARK: - Bindings

    private var documentRootBinding: Binding<String> {
        Binding(get: { vhost.documentRoot ?? "" }, set: { vhost.documentRoot = $0 })
    }

    private var phpSocketPathBinding: Binding<String> {
        Binding(get: { vhost.phpSocketPath ?? "" }, set: { vhost.phpSocketPath = $0 })
    }

    private var proxyTargetBinding: Binding<String> {
        Binding(get: { vhost.proxyTarget ?? "" }, set: { vhost.proxyTarget = $0 })
    }

    private var indexFilesBinding: Binding<String> {
        Binding(get: { vhost.indexFiles ?? "" }, set: { vhost.indexFiles = $0.isEmpty ? nil : $0 })
    }

    private var aliasesBinding: Binding<String> {
        Binding(
            get: { vhost.aliases.joined(separator: ", ") },
            set: { raw in
                vhost.aliases = raw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Actions

    private func normalizeFieldsForKind() {
        switch vhost.kind {
        case .staticSite:
            vhost.phpSocketPath = nil
            vhost.proxyTarget = nil
            vhost.websocketEnabled = true
            vhost.preserveHostHeader = false
            vhost.forwardProxyHeaders = true
        case .phpSite:
            vhost.proxyTarget = nil
            vhost.websocketEnabled = true
            vhost.preserveHostHeader = false
            vhost.forwardProxyHeaders = true
        case .reverseProxy:
            vhost.documentRoot = nil
            vhost.phpSocketPath = nil
            vhost.indexFiles = nil
            vhost.compressionEnabled = true
        }
    }

    private func save() {
        vhost.domain = vhost.domain.trimmingCharacters(in: .whitespaces).lowercased()
        let result = isNew ? vhostStore.add(vhost) : vhostStore.update(vhost)
        issues = result
        if !result.contains(where: { $0.severity == .error }) {
            dismiss()
        }
    }
}
