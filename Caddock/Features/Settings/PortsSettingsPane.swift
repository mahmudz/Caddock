import SwiftUI

struct PortsSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VhostStore.self) private var vhostStore

    @State private var portApplyTask: Task<Void, Never>?
    @State private var hasPendingPortApply = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                portField(title: "HTTP Port", systemImage: "arrow.down.left.circle", value: $settings.httpPort)
                portField(title: "HTTPS Port", systemImage: "lock.circle", value: $settings.httpsPort)
                portField(title: "Admin API Port", systemImage: "terminal", value: $settings.adminPort)
            } footer: {
                Text("With the privileged helper enabled (Advanced tab), 80 and 443 redirect to the HTTP/HTTPS ports here automatically.")
            }
        }
        .settingsFormStyle()
        .onChange(of: settings.httpPort) { _, _ in schedulePortApply() }
        .onChange(of: settings.httpsPort) { _, _ in schedulePortApply() }
        .onChange(of: settings.adminPort) { _, _ in schedulePortApply() }
        .onDisappear {
            flushPendingPortApply()
        }
    }

    private func portField(title: String, systemImage: String, value: Binding<Int>) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                Stepper("", value: value, in: 1024...65535)
                    .labelsHidden()
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func schedulePortApply() {
        hasPendingPortApply = true
        portApplyTask?.cancel()
        portApplyTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            hasPendingPortApply = false
            await vhostStore.applyPortChanges()
        }
    }

    private func flushPendingPortApply() {
        portApplyTask?.cancel()
        portApplyTask = nil
        guard hasPendingPortApply else { return }
        hasPendingPortApply = false
        Task { await vhostStore.applyPortChanges() }
    }
}
