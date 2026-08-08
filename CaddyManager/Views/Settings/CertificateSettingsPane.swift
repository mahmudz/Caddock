import AppKit
import SwiftUI

struct CertificateSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @State private var trustStatus: CertificateTrustStatus = .notInstalled
    @State private var actionError: String?
    @State private var isWorking = false
    @State private var mobileShare = MobileCertShareServer()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        statusIcon
                        Text(statusLabel)
                            .foregroundStyle(statusColor)
                        Button("Refresh", action: refresh)
                            .controlSize(.small)
                    }
                } label: {
                    Label("Root CA Status", systemImage: "checkmark.shield")
                }
            } footer: {
                Text(statusFooter)
            }

            Section {
                LabeledContent {
                    Button(settings.hasTrustedCaddyCA ? "Re-install" : "Install Root CA", action: installRootCA)
                        .controlSize(.small)
                        .disabled(isWorking || trustStatus == .notInstalled)
                } label: {
                    Label("Install Root CA", systemImage: "plus.circle")
                }

                LabeledContent {
                    Button("Open Keychain Access", action: CertificateStatusChecker.openKeychainAccess)
                        .controlSize(.small)
                } label: {
                    Label("Keychain Access", systemImage: "key")
                }
            } footer: {
                Text("Trusts Caddy's Root CA for your user account. macOS may ask you to authenticate.")
            }

            if trustStatus == .installedNotTrusted {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Click Open Keychain Access above")
                        Text("2. Select System keychain in the sidebar")
                        Text("3. Find Caddy Local Authority (or Caddy Root CA)")
                        Text("4. Double-click the certificate")
                        Text("5. Expand Trust")
                        Text("6. Set When using this certificate to Always Trust")
                        Text("7. Close and authenticate when prompted")
                    }
                    .font(.caption)
                } header: {
                    Label("Finish Trust Setup", systemImage: "list.number")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Firefox uses its own certificate store. Import:")
                        .font(.caption)
                    Text(CertificateStatusChecker.rootCertificateURL.path)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Firefox → Settings → Privacy & Security → Certificates → Authorities → Import")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Firefox", systemImage: "globe")
            }

            Section {
                if mobileShare.isRunning, let url = mobileShare.downloadURL {
                    VStack(alignment: .leading, spacing: 10) {
                        QRCodeView(string: url.absoluteString)
                        Text(url.absoluteString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Scan with phone on same Wi-Fi. Stop server when done.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Stop Server", role: .destructive) {
                            mobileShare.stop()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Start Server & Show QR") {
                        mobileShare.start()
                        if let err = mobileShare.lastError {
                            actionError = err
                        }
                    }
                    .controlSize(.small)
                    .disabled(trustStatus == .notInstalled)
                }
            } header: {
                Label("Share with Mobile Devices", systemImage: "qrcode")
            } footer: {
                Text("Serves the Root CA over a temporary local HTTP server for iOS/Android install.")
            }

            if let actionError {
                Section {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsFormStyle()
        .onAppear(perform: refresh)
        .onDisappear {
            mobileShare.stop()
        }
    }

    private var statusIcon: some View {
        Image(systemName: statusSymbol)
            .foregroundStyle(statusColor)
            .symbolRenderingMode(.hierarchical)
    }

    private var statusSymbol: String {
        switch trustStatus {
        case .installedAndTrusted: return "checkmark.shield.fill"
        case .installedNotTrusted: return "exclamationmark.shield.fill"
        case .notInstalled: return "shield.slash"
        }
    }

    private var statusLabel: String {
        switch trustStatus {
        case .installedAndTrusted: return "Installed and Trusted"
        case .installedNotTrusted: return "Installed, Not Trusted"
        case .notInstalled: return "Not Installed"
        }
    }

    private var statusColor: Color {
        switch trustStatus {
        case .installedAndTrusted: return .green
        case .installedNotTrusted: return .orange
        case .notInstalled: return .secondary
        }
    }

    private var statusFooter: String {
        switch trustStatus {
        case .installedAndTrusted:
            return "HTTPS sites should load without browser warnings."
        case .installedNotTrusted:
            return "Certificate exists but needs Always Trust in Keychain Access."
        case .notInstalled:
            return "Start Caddy with at least one TLS-enabled vhost, then install the Root CA."
        }
    }

    private func refresh() {
        trustStatus = CertificateStatusChecker.status()
        if trustStatus == .installedAndTrusted {
            settings.hasTrustedCaddyCA = true
        }
    }

    private func installRootCA() {
        isWorking = true
        defer { isWorking = false }
        do {
            try CertificateTrustInstaller.installRootCA()
            settings.hasTrustedCaddyCA = true
            actionError = nil
            refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
