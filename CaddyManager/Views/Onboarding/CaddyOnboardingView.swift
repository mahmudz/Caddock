import AppKit
import SwiftUI

struct CaddyOnboardingView: View {
    private enum Method: Hashable {
        case homebrew
        case download
    }

    @Environment(AppSettings.self) private var settings
    @Environment(VhostStore.self) private var vhostStore

    var onClose: (() -> Void)?

    @State private var selectedMethod: Method = .homebrew
    @State private var brewAvailable = false
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var installedVersion: String?

    var body: some View {
        VStack(spacing: 28) {
            Text("Install Caddy")
                .font(.title3.weight(.semibold))

            HStack(spacing: 14) {
                methodCard(
                    method: .homebrew,
                    title: "Homebrew",
                    subtitle: brewAvailable ? "brew install caddy" : "Homebrew not found",
                    systemImage: "terminal",
                    enabled: brewAvailable
                )
                methodCard(
                    method: .download,
                    title: "Download",
                    subtitle: "Official binary",
                    systemImage: "arrow.down.circle",
                    enabled: true
                )
            }

            statusRow
                .frame(minHeight: 36, alignment: .center)

            HStack(spacing: 12) {
                Button("Check") {
                    recheckInstallation()
                }
                .disabled(isBusy)
                .keyboardShortcut("r", modifiers: [.command])

                Spacer()

                Button(nextTitle) {
                    handleNext()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || (installedVersion == nil && selectedMethod == .homebrew && !brewAvailable))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 300)
        .background {
            OnboardingGlassBackground()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            refreshEnvironment()
            if !brewAvailable {
                selectedMethod = .download
            }
        }
        .focusable()
        .onKeyPress(.escape) {
            settings.hasCompletedCaddyOnboarding = true
            onClose?()
            return .handled
        }
    }

    private var nextTitle: String {
        if installedVersion != nil { return "Next" }
        return isBusy ? "Installing…" : "Next"
    }

    @ViewBuilder
    private var statusRow: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusMessage ?? "Working…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else if let errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .textSelection(.enabled)
        } else if let installedVersion {
            Label(installedVersion, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .lineLimit(2)
        } else if let statusMessage {
            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        } else {
            Text("Choose a method, then click Next.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func methodCard(
        method: Method,
        title: String,
        subtitle: String,
        systemImage: String,
        enabled: Bool
    ) -> some View {
        let selected = selectedMethod == method
        return Button {
            guard enabled else { return }
            selectedMethod = method
        } label: {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(enabled ? .primary : .secondary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                    lineWidth: selected ? 1.5 : 1
                )
        }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled || isBusy)
    }

    private func refreshEnvironment() {
        brewAvailable = CaddyInstaller.locateBrew() != nil
        if let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) {
            installedVersion = try? CaddyInstallation.version(of: binary)
        } else {
            installedVersion = nil
        }
    }

    private func handleNext() {
        if installedVersion != nil {
            settings.hasCompletedCaddyOnboarding = true
            onClose?()
            return
        }

        switch selectedMethod {
        case .homebrew:
            installWithBrew()
        case .download:
            installWithDownload()
        }
    }

    private func installWithBrew() {
        runInstall {
            await MainActor.run {
                statusMessage = "Running brew install caddy…"
            }
            let binary = try await CaddyInstaller.installWithHomebrew()
            await MainActor.run {
                settings.caddyBinaryPathOverride = nil
            }
            return binary
        }
    }

    private func installWithDownload() {
        runInstall {
            let binary = try await CaddyInstaller.downloadOfficialBinary { message in
                Task { @MainActor in
                    statusMessage = message
                }
            }
            await MainActor.run {
                settings.caddyBinaryPathOverride = binary.path
            }
            return binary
        }
    }

    private func runInstall(_ work: @escaping @Sendable () async throws -> URL) {
        isBusy = true
        errorMessage = nil
        installedVersion = nil
        Task {
            do {
                let binary = try await work()
                let version = (try? CaddyInstallation.version(of: binary)) ?? binary.path
                installedVersion = version
                statusMessage = nil
                settings.hasCompletedCaddyOnboarding = true
                await vhostStore.regenerateAndReload()
                isBusy = false
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = nil
                isBusy = false
            }
        }
    }

    private func recheckInstallation() {
        errorMessage = nil
        refreshEnvironment()
        if let installedVersion {
            statusMessage = nil
            settings.hasCompletedCaddyOnboarding = true
            Task { await vhostStore.regenerateAndReload() }
        } else {
            statusMessage = "Caddy not found yet."
        }
    }
}

// MARK: - Glass background

private struct OnboardingGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
