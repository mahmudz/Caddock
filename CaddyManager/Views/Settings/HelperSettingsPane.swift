//
//  HelperSettingsPane.swift
//  CaddyManager
//
//  Created by mahmud on 30/7/26.
//

import AppKit
import SwiftUI

struct HelperSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(VhostStore.self) private var vhostStore
    @State private var helperClient = HelperClient()
    @State private var detectedBinary: URL?
    @State private var helperActionError: String?
    @State private var showApprovalAlert = false
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        helperActionButton
                        if showsReinstallButton {
                            Button("Reinstall", action: reinstallHelper)
                                .controlSize(.small)
                                .disabled(isWorking)
                        }
                    }
                } label: {
                    Label("Privileged Helper", systemImage: "lock.shield")
                }

                if helperInstaller.isEnabled {
                    LabeledContent {
                        Button(settings.hasTrustedCaddyCA ? "Re-run" : "Trust", action: trustCaddy)
                            .controlSize(.small)
                            .disabled(detectedBinary == nil || isWorking)
                    } label: {
                        Label("Local CA Trust", systemImage: "checkmark.seal")
                    }
                }
            } footer: {
                Text(helperStatusText)
            }

            Section {
                Text("Installs pf redirect rules (80→\(settings.httpPort), 443→\(settings.httpsPort)) and keeps /etc/hosts in sync with your enabled vhosts.")
            }

            if let helperActionError {
                Section {
                    Label(helperActionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if showsReinstallSuggestion {
                        Text("After rebuilding from Xcode, use Reinstall to replace the stale helper daemon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !helperInstaller.isEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("127.0.0.1  myproject.test")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Then visit https://myproject.test:\(settings.httpsPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Manual Domains", systemImage: "list.bullet.rectangle")
                }
            }
        }
        .settingsFormStyle()
        .onAppear {
            detectedBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride)
            helperInstaller.refreshStatus()
            if helperInstaller.state == .requiresApproval {
                showApprovalAlert = true
            }
        }
        .onChange(of: helperInstaller.state) { oldState, newState in
            if newState == .requiresApproval {
                showApprovalAlert = true
            }
            if newState == .enabled, oldState == .requiresApproval {
                Task { await finishHelperSetup() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helperInstaller.refreshStatus()
        }
        .alert("Enable Privileged Helper", isPresented: $showApprovalAlert) {
            Button("Open System Settings") {
                helperInstaller.openSystemSettingsLoginItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("CaddyManager needs approval to run its privileged helper. Open System Settings, go to Login Items, find CaddyManager under Background Items, and turn it on.")
        }
    }

    private var showsReinstallButton: Bool {
        switch helperInstaller.state {
        case .enabled, .failed, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        }
    }

    private var showsReinstallSuggestion: Bool {
        guard let helperActionError else { return false }
        return helperActionError.localizedCaseInsensitiveContains("invalidated")
            || helperActionError.localizedCaseInsensitiveContains("interrupted")
    }

    @ViewBuilder
    private var helperActionButton: some View {
        switch helperInstaller.state {
        case .enabled:
            Button("Disable", role: .destructive, action: disableHelper)
                .controlSize(.small)
                .disabled(isWorking)
        case .requiresApproval:
            Button("Waiting for Approval…") {}
                .controlSize(.small)
                .disabled(true)
        default:
            Button("Enable", action: enableHelper)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
        }
    }

    private var helperStatusText: String {
        switch helperInstaller.state {
        case .notRegistered: return "Not enabled."
        case .enabled: return "Enabled."
        case .requiresApproval: return "Waiting for approval in System Settings."
        case .notFound: return "Not found. Rebuild the app."
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private func enableHelper() {
        helperActionError = nil
        helperInstaller.register()
        if helperInstaller.state == .requiresApproval {
            showApprovalAlert = true
            return
        }
        guard helperInstaller.isEnabled else { return }
        Task { await finishHelperSetup() }
    }

    private func disableHelper() {
        Task {
            isWorking = true
            defer { isWorking = false }
            helperActionError = nil
            try? await helperClient.uninstallAll()
            helperInstaller.unregister()
        }
    }

    private func reinstallHelper() {
        Task {
            isWorking = true
            defer { isWorking = false }
            helperActionError = nil

            if helperInstaller.isEnabled {
                try? await helperClient.uninstallAll()
            }

            await helperInstaller.reinstall()

            if helperInstaller.state == .requiresApproval {
                showApprovalAlert = true
                return
            }

            guard helperInstaller.isEnabled else { return }
            await finishHelperSetup()
        }
    }

    private func finishHelperSetup() async {
        do {
            _ = try await helperClient.ping()
            try await helperClient.syncHosts(domains: vhostStore.vhosts.filter(\.isEnabled).map(\.domain))
            helperActionError = nil
        } catch {
            helperActionError = error.localizedDescription
        }
    }

    private func trustCaddy() {
        guard let detectedBinary else { return }
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await helperClient.trustCaddyRootCertificate(
                    caddyBinaryPath: detectedBinary.path,
                    callingUserHome: NSHomeDirectory()
                )
                settings.hasTrustedCaddyCA = true
                helperActionError = nil
            } catch {
                helperActionError = error.localizedDescription
            }
        }
    }
}
