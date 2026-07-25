import ServiceManagement
import SwiftUI

private enum SettingsTab: String, CaseIterable {
    case general, ports, helper

    var title: String {
        switch self {
        case .general: return "General"
        case .ports: return "Ports"
        case .helper: return "Helper"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .ports: return "network"
        case .helper: return "lock.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .ports: return .blue
        case .helper: return .orange
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                GeneralSettingsPane()
            }
            Tab("Ports", systemImage: "network") {
                PortsSettingsPane()
            }
            Tab("Advanced", systemImage: "lock.shield") {
                HelperSettingsPane()
            }
        }
        .scenePadding()
        .fixedSize(horizontal: false, vertical: false)
        .frame(minHeight: 300)
        .tabViewStyle(.tabBarOnly)
    }
}

private struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var detectedBinary: URL?
    @State private var detectedVersion: String?

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 6) {
            SettingsCard {
                SettingsRow(
                    icon: "terminal.fill",
                    iconColor: .black,
                    title: "Caddy",
                    subtitle: detectedBinary != nil ? (detectedVersion ?? detectedBinary?.path) : "Not found"
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: detectedBinary != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(detectedBinary != nil ? .green : .red)
                        Button("Recheck", action: detect)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                if detectedBinary == nil {
                    SettingsRowDivider()
                    HStack {
                        Text("brew install caddy")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }

            SettingsCard {
                SettingsRow(icon: "power", iconColor: .gray, title: "Launch at Login") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: settings.launchAtLogin) { _, _ in
                            syncLoginItem()
                        }
                }
            }
        }
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

private struct PortsSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 8) {
            SettingsCard {
                portRow(icon: "arrow.down.left.circle.fill", color: .blue, title: "HTTP Port", value: $settings.httpPort)
                SettingsRowDivider()
                portRow(icon: "lock.circle.fill", color: .green, title: "HTTPS Port", value: $settings.httpsPort)
                SettingsRowDivider()
                portRow(icon: "terminal.fill", color: .gray, title: "Admin API Port", value: $settings.adminPort)
            }

            SettingsFooter(text: "With the privileged helper enabled (Helper tab), 80 and 443 redirect to the HTTP/HTTPS ports here automatically.")
        }
    }

    private func portRow(icon: String, color: Color, title: String, value: Binding<Int>) -> some View {
        SettingsRow(icon: icon, iconColor: color, title: title) {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Stepper("", value: value, in: 1024...65535)
                    .labelsHidden()
            }
        }
    }
}

private struct HelperSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(VhostStore.self) private var vhostStore
    @State private var helperClient = HelperClient()
    @State private var detectedBinary: URL?
    @State private var helperActionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(
                    icon: "lock.shield.fill",
                    iconColor: helperStatusColor,
                    title: "Privileged Helper",
                    subtitle: helperStatusText
                ) {
                    helperActionButton
                }

                if helperInstaller.isEnabled {
                    SettingsRowDivider()
                    SettingsRow(icon: "checkmark.seal.fill", iconColor: .purple, title: "Local CA Trust") {
                        Button(settings.hasTrustedCaddyCA ? "Re-run" : "Trust", action: trustCaddy)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(detectedBinary == nil)
                    }
                }

                if helperInstaller.state == .requiresApproval {
                    SettingsRowDivider()
                    HStack {
                        Spacer()
                        Button("Open Login Items Settings", action: helperInstaller.openSystemSettingsLoginItems)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }

            SettingsFooter(text: "Installs pf redirect rules (80→\(settings.httpPort), 443→\(settings.httpsPort)) and keeps /etc/hosts in sync with your enabled vhosts.")

            if let helperActionError {
                Label(helperActionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !helperInstaller.isEnabled {
                SettingsCard {
                    SettingsRow(icon: "list.bullet.rectangle.fill", iconColor: .indigo, title: "Manual Domains") {
                        EmptyView()
                    }
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("127.0.0.1  myproject.test")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Then visit https://myproject.test:\(settings.httpsPort)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            detectedBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride)
            helperInstaller.refreshStatus()
        }
    }

    @ViewBuilder
    private var helperActionButton: some View {
        switch helperInstaller.state {
        case .enabled:
            Button("Disable", role: .destructive, action: disableHelper)
                .buttonStyle(.bordered)
                .controlSize(.small)
        default:
            Button("Enable", action: enableHelper)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private var helperStatusText: String {
        switch helperInstaller.state {
        case .notRegistered: return "Not Enabled"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Needs Approval in System Settings"
        case .notFound: return "Not Found (rebuild the app)"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var helperStatusColor: Color {
        switch helperInstaller.state {
        case .notRegistered, .notFound: return .gray
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .failed: return .red
        }
    }

    private func enableHelper() {
        helperInstaller.register()
        guard helperInstaller.isEnabled else { return }
        Task {
            do {
//                try await helperClient.installPFRedirect(httpPort: settings.httpPort, httpsPort: settings.httpsPort)
                try await helperClient.syncHosts(domains: vhostStore.vhosts.filter(\.isEnabled).map(\.domain))
                helperActionError = nil
            } catch {
                helperActionError = error.localizedDescription
            }
        }
    }

    private func disableHelper() {
        Task {
            do {
                try await helperClient.uninstallAll()
                helperInstaller.unregister()
                helperActionError = nil
            } catch {
                print(error)
                helperActionError = error.localizedDescription
            }
        }
    }

    private func trustCaddy() {
        guard let detectedBinary else { return }
        Task {
            do {
                try await helperClient.trustCaddyRootCertificate(
                    caddyBinaryPath: detectedBinary.path,
                    callingUserHome: NSHomeDirectory()
                )
                settings.hasTrustedCaddyCA = true
                helperActionError = nil
            } catch {
                
                print(error)
                helperActionError = error.localizedDescription
            }
        }
    }
}
