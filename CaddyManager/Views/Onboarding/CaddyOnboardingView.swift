import AppKit
import SwiftUI

struct CaddyOnboardingView: View {
    private enum Method: Hashable {
        case homebrew
        case download
    }

    @Environment(AppSettings.self) private var settings
    @Environment(VhostStore.self) private var vhostStore
    @Environment(SetupGate.self) private var setupGate
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var method: Method = .homebrew
    @State private var brewAvailable = false
    @State private var isBusy = false
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var installedVersion: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 36)
                .padding(.bottom, 28)

            HStack(spacing: 12) {
                methodButton(
                    .homebrew,
                    title: "Homebrew",
                    detail: brewAvailable ? "brew install caddy" : "Not installed",
                    symbol: "terminal",
                    enabled: brewAvailable
                )
                methodButton(
                    .download,
                    title: "Download",
                    detail: "From GitHub",
                    symbol: "arrow.down.circle",
                    enabled: true
                )
            }
            .padding(.horizontal, 28)

            statusArea
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .frame(minHeight: 44)

            Spacer(minLength: 12)

            HStack {
                Button("Quit", action: quitApp)
                    .controlSize(.large)
                    .disabled(isBusy)

                Button("Check", action: check)
                    .disabled(isBusy)
                    .controlSize(.large)
                    .keyboardShortcut("r", modifiers: .command)

                Spacer()

                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canPressPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 380)
        .onAppear(perform: bootstrap)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("Set Up Caddy")
                .font(.title2.weight(.semibold))

            Text("CaddyManager needs the Caddy server before the menu bar activates.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        if isBusy { return "Installing…" }
        if installedVersion != nil { return "Continue" }
        return "Install"
    }

    @ViewBuilder
    private var statusArea: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText ?? "Working…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else if let errorText {
            Text(errorText)
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
        } else {
            Text(statusText ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(statusText == nil ? 0 : 1)
        }
    }

    private func methodButton(
        _ value: Method,
        title: String,
        detail: String,
        symbol: String,
        enabled: Bool
    ) -> some View {
        let selected = method == value
        return Button {
            guard enabled else { return }
            method = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: selected ? 1.5 : 1
                )
        }
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled || isBusy)
    }

    private var canPressPrimary: Bool {
        guard !isBusy else { return false }
        if installedVersion != nil { return true }
        if method == .homebrew { return brewAvailable }
        return true
    }

    private func bootstrap() {
        brewAvailable = CaddyInstaller.locateBrew() != nil
        if !brewAvailable {
            method = .download
        }
        refreshBinary()
    }

    private func refreshBinary() {
        if let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) {
            installedVersion = (try? CaddyInstallation.version(of: binary)) ?? binary.path
        } else {
            installedVersion = nil
        }
    }

    private func check() {
        errorText = nil
        refreshBinary()
        if installedVersion != nil {
            statusText = nil
        } else {
            statusText = "Caddy not found yet."
        }
    }

    private func primaryAction() {
        if installedVersion != nil {
            activateMenuBar()
            return
        }
        switch method {
        case .homebrew: startBrewInstall()
        case .download: startDownload()
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func activateMenuBar() {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else {
            setupGate.markComplete(settings: settings)
            dismissWindow(id: CaddyOnboardingPresenter.windowID)
            return
        }
        appDelegate.finishSetup()
        dismissWindow(id: CaddyOnboardingPresenter.windowID)
    }

    private func startBrewInstall() {
        runInstall(status: "Running brew install caddy…") {
            let binary = try await CaddyInstaller.installWithHomebrew()
            await MainActor.run { settings.caddyBinaryPathOverride = nil }
            return binary
        }
    }

    private func startDownload() {
        runInstall(status: "Downloading…") {
            let binary = try await CaddyInstaller.downloadOfficialBinary { message in
                Task { @MainActor in statusText = message }
            }
            await MainActor.run { settings.caddyBinaryPathOverride = binary.path }
            return binary
        }
    }

    private func runInstall(status: String, _ work: @escaping @Sendable () async throws -> URL) {
        isBusy = true
        errorText = nil
        installedVersion = nil
        statusText = status
        Task {
            do {
                let binary = try await work()
                installedVersion = (try? CaddyInstallation.version(of: binary)) ?? binary.path
                statusText = nil
                isBusy = false
                // Successful install → activate menu bar immediately.
                activateMenuBar()
            } catch {
                errorText = error.localizedDescription
                statusText = nil
                isBusy = false
            }
        }
    }
}

#if DEBUG
#Preview {
    let defaults = UserDefaults(suiteName: "dev.mahmudz.CaddyManager.onboarding-preview")!
    defaults.removePersistentDomain(forName: "dev.mahmudz.CaddyManager.onboarding-preview")
    let settings = AppSettings(defaults: defaults)
    let store = VhostStore(
        settings: settings,
        processController: CaddyProcessController(settings: settings),
        helperInstaller: HelperInstaller(),
        helperClient: HelperClient(),
        dnsResponder: LocalDNSResponder()
    )
    return CaddyOnboardingView()
        .environment(settings)
        .environment(store)
        .environment(SetupGate(settings: settings))
        .containerBackground(.thinMaterial, for: .window)
        .frame(width: 480, height: 340)
}
#endif
