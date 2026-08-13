import Foundation
import ServiceManagement
import SwiftUI

struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @State private var detectedBinary: URL?
    @State private var detectedVersion: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Image(systemName: detectedBinary != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(detectedBinary != nil ? .green : .red)
                            .symbolRenderingMode(.hierarchical)
                        Button("Recheck", action: detect)
                            .controlSize(.small)
                    }
                } label: {
                    Label("Caddy", systemImage: "terminal")
                }

                TextField("Custom binary path (optional)", text: customPathBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(detect)

                Button("Install Caddy…") {
                    AppWindowPresenter.present(
                        open: { openWindow(id: "setup") },
                        target: .window(id: "setup")
                    )
                }
            } footer: {
                if let binary = detectedBinary {
                    Text(detectedVersion ?? binary.path)
                } else {
                    Text("Install via Homebrew, download the official binary, or set a custom path.")
                }
            }

            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    Label("Launch at Login", systemImage: "power")
                }
                .onChange(of: settings.launchAtLogin) { _, _ in
                    syncLoginItem()
                }
            }

            Section {
                Toggle(isOn: $settings.clearLogsOnRestart) {
                    Label("Clear Logs on Restart", systemImage: "doc.text")
                }
            } footer: {
                Text("Clears the Caddy log file when Caddy is stopped and started again. App logs are unaffected. Config reloads while Caddy is running are not affected.")
            }
        }
        .settingsFormStyle()
        .onAppear(perform: detect)
    }

    private func detect() {
        detectedBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride)
        detectedVersion = detectedBinary.flatMap { try? CaddyInstallation.version(of: $0) }
    }

    private var customPathBinding: Binding<String> {
        Binding(
            get: { settings.caddyBinaryPathOverride ?? "" },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                settings.caddyBinaryPathOverride = trimmed.isEmpty ? nil : trimmed
                detect()
            }
        )
    }

    private func syncLoginItem() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settings.launchAtLogin.toggle()
        }
    }
}
