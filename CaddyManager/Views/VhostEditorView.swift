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
        Form {
            Section("Domain") {
                TextField("myproject.test", text: $vhost.domain)
                Picker("Type", selection: $vhost.kind) {
                    ForEach(Vhost.Kind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }

            switch vhost.kind {
            case .staticSite:
                Section("Static Site") {
                    TextField("Document root", text: documentRootBinding)
                }
            case .phpSite:
                Section("PHP Site") {
                    TextField("Document root", text: documentRootBinding)
                    TextField("PHP-FPM socket path", text: phpSocketPathBinding)
                }
            case .reverseProxy:
                Section("Reverse Proxy") {
                    TextField("Target (host:port)", text: proxyTargetBinding)
                }
            }

            Section {
                Toggle("SSL enabled", isOn: $vhost.sslEnabled)
                Toggle("Enabled", isOn: $vhost.isEnabled)
            }

            if !issues.isEmpty {
                Section("Issues") {
                    ForEach(issues) { issue in
                        Text(issue.message)
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear(perform: normalizeFieldsForKind)
        .onChange(of: vhost.kind) { _, _ in normalizeFieldsForKind() }
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
