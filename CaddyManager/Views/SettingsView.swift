import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var detectedBinary: URL?
    @State private var detectedVersion: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Caddy") {
                if let detectedBinary {
                    LabeledContent("Binary", value: detectedBinary.path)
                    if let detectedVersion {
                        LabeledContent("Version", value: detectedVersion)
                    }
                } else {
                    Text("Caddy not found.")
                        .foregroundStyle(.red)
                    Text("Install it with Homebrew, then click Recheck:")
                        .font(.caption)
                    Text("brew install caddy")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Button("Recheck", action: detect)
            }

            Section("Ports") {
                Stepper("HTTP port: \(settings.httpPort)", value: $settings.httpPort, in: 1024...65535)
                Stepper("HTTPS port: \(settings.httpsPort)", value: $settings.httpsPort, in: 1024...65535)
                Stepper("Admin port: \(settings.adminPort)", value: $settings.adminPort, in: 1024...65535)
            }

            Section("Login") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, _ in
                        syncLoginItem()
                    }
            }

            Section("Domains") {
                Text("Until the privileged helper (planned) can automate this, add each vhost's domain to /etc/hosts manually, e.g.:")
                    .font(.caption)
                Text("127.0.0.1  myproject.test")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Text("Then visit it via the configured ports, e.g. https://myproject.test:\(settings.httpsPort)")
                    .font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
        .onAppear(perform: detect)
    }

    private func detect() {
        detectedBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride)
        detectedVersion = detectedBinary.flatMap { try? CaddyInstallation.version(of: $0) }
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
