import AppKit
import ServiceManagement
import SwiftUI

struct SetupWizardView: View {
    private enum Step: Int, CaseIterable {
        case caddy
        case helper
        case certificate
        case ready

        var title: String {
            switch self {
            case .caddy: return "Caddy"
            case .helper: return "Privileged Helper"
            case .certificate: return "HTTPS Trust"
            case .ready: return "Ready"
            }
        }
    }

    private enum CaddyMethod: Hashable {
        case homebrew
        case download
    }

    @Environment(AppSettings.self) private var settings
    @Environment(VhostStore.self) private var vhostStore
    @Environment(SetupGate.self) private var setupGate
    @Environment(HelperInstaller.self) private var helperInstaller
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var step: Step = .caddy
    @State private var method: CaddyMethod = .homebrew
    @State private var brewAvailable = false
    @State private var isBusy = false
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var installedVersion: String?
    @State private var trustStatus: CertificateTrustStatus = .notInstalled
    @State private var showApprovalAlert = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 36)
                .padding(.bottom, 20)

            Group {
                switch step {
                case .caddy: caddyStep
                case .helper: helperStep
                case .certificate: certificateStep
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(width: 500, height: 420)
        .onAppear(perform: bootstrap)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helperInstaller.refreshStatus()
            if step == .helper, helperInstaller.isEnabled, !isBusy {
                Task { await finishHelperSetup() }
            }
        }
        .onChange(of: helperInstaller.state) { _, newState in
            if newState == .requiresApproval || isNotPermittedFailure(newState) {
                presentApprovalAlert()
            }
            if newState == .enabled {
                Task { await finishHelperSetup() }
            }
        }
        .alert("Enable Privileged Helper", isPresented: $showApprovalAlert) {
            Button("Open Login Items Settings") {
                helperInstaller.openSystemSettingsLoginItems()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("macOS needs you to allow Caddock as a background item.\n\nSystem Settings → General → Login Items & Extensions → Background Items → turn on Caddock.\n\nThen return here and tap Check Again.")
        }
    }

    // MARK: - Chrome

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: item == step ? 22 : 8, height: 8)
                    .accessibilityLabel(item.title)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .caddy {
                Button("Back") {
                    goBack()
                }
                .controlSize(.large)
                .disabled(isBusy)
            }

            Spacer()

            if canSkip {
                Button("Skip") {
                    advance()
                }
                .controlSize(.large)
                .disabled(isBusy)
            }

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canPressPrimary)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var canSkip: Bool {
        switch step {
        case .caddy, .ready: return false
        case .helper, .certificate: return !isBusy
        }
    }

    private var primaryTitle: String {
        if isBusy {
            switch step {
            case .caddy: return "Installing…"
            case .helper: return helperInstaller.isEnabled ? "Enabling…" : (needsHelperApproval ? "Check Again" : "Enabling…")
            case .certificate: return "Installing…"
            case .ready: return "Starting…"
            }
        }
        switch step {
        case .caddy:
            return installedVersion == nil ? "Install" : "Continue"
        case .helper:
            if helperInstaller.isEnabled { return "Continue" }
            if needsHelperApproval { return "Check Again" }
            return "Enable"
        case .certificate:
            return trustStatus == .installedAndTrusted ? "Continue" : "Install Root CA"
        case .ready:
            return "Get Started"
        }
    }

    private var canPressPrimary: Bool {
        switch step {
        case .helper:
            if case .notFound = helperInstaller.state { return false }
            // Never disable Check Again while waiting for Login Items approval.
            if needsHelperApproval { return true }
            return !isBusy
        case .caddy:
            guard !isBusy else { return false }
            if installedVersion != nil { return true }
            if method == .homebrew { return brewAvailable }
            return true
        case .certificate, .ready:
            return !isBusy
        }
    }

    private var needsHelperApproval: Bool {
        switch helperInstaller.state {
        case .requiresApproval:
            return true
        case .failed(let message):
            return isNotPermittedMessage(message)
        default:
            return false
        }
    }

    private func isNotPermittedFailure(_ state: HelperInstallState) -> Bool {
        if case .failed(let message) = state {
            return isNotPermittedMessage(message)
        }
        return false
    }

    private func isNotPermittedMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("not permitted")
    }

    // MARK: - Steps

    private var caddyStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                symbol: "server.rack",
                title: "Install Caddy",
                subtitle: "Caddock needs the Caddy server to run your local sites."
            )

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
                .padding(.top, 16)
                .frame(minHeight: 40)
        }
    }

    private var helperStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                symbol: "lock.shield",
                title: "Privileged Helper",
                subtitle: "Redirects ports 80 and 443 and keeps /etc/hosts in sync. macOS will ask for approval."
            )

            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Status", helperStatusText, color: helperStatusColor)
                labeledRow("HTTP", "80 → \(settings.httpPort)")
                labeledRow("HTTPS", "443 → \(settings.httpsPort)")

                if needsHelperApproval {
                    Text("Enable Caddock under System Settings → General → Login Items & Extensions → Background Items, then tap Check Again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)

            statusArea
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .frame(minHeight: 40)
        }
    }

    private var certificateStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                symbol: "checkmark.shield",
                title: "Trust HTTPS",
                subtitle: "Install Caddy's local Root CA so Safari and Chrome accept your .test sites."
            )

            VStack(alignment: .leading, spacing: 10) {
                labeledRow("Root CA", certificateStatusText, color: certificateStatusColor)
                Text("macOS may ask you to authenticate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)

            statusArea
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .frame(minHeight: 40)
        }
    }

    private var readyStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                symbol: "checkmark.circle",
                title: "You're ready",
                subtitle: "Caddock will live in the menu bar. Add a site whenever you need one."
            )

            VStack(alignment: .leading, spacing: 12) {
                labeledRow("Caddy", installedVersion ?? "Installed", color: .green)
                labeledRow("Helper", helperInstaller.isEnabled ? "Enabled" : "Skipped")
                labeledRow("HTTPS", trustStatus == .installedAndTrusted ? "Trusted" : "Skipped")

                Toggle(isOn: launchAtLoginBinding) {
                    Text("Launch at login")
                }
                .toggleStyle(.switch)
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 28)
        }
    }

    private func stepHeader(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 22)
    }

    private func labeledRow(_ title: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .font(.callout)
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
        } else if step == .caddy, let installedVersion {
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
        _ value: CaddyMethod,
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
            .frame(maxWidth: .infinity, minHeight: 100)
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

    private var helperStatusText: String {
        if needsHelperApproval { return "Waiting for approval" }
        switch helperInstaller.state {
        case .notRegistered: return "Not enabled"
        case .enabled: return "Enabled"
        case .requiresApproval: return "Waiting for approval"
        case .notFound: return "Not found. Rebuild the app."
        case .failed(let message): return message
        }
    }

    private var helperStatusColor: Color {
        if needsHelperApproval { return .orange }
        switch helperInstaller.state {
        case .enabled: return .green
        case .requiresApproval: return .orange
        case .failed, .notFound: return .red
        case .notRegistered: return .secondary
        }
    }

    private var certificateStatusText: String {
        switch trustStatus {
        case .installedAndTrusted: return "Installed and trusted"
        case .installedNotTrusted: return "Installed, not trusted"
        case .notInstalled: return "Not created yet"
        }
    }

    private var certificateStatusColor: Color {
        switch trustStatus {
        case .installedAndTrusted: return .green
        case .installedNotTrusted: return .orange
        case .notInstalled: return .secondary
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                settings.launchAtLogin = newValue
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    settings.launchAtLogin.toggle()
                    errorText = error.localizedDescription
                }
            }
        )
    }

    // MARK: - Actions

    private func bootstrap() {
        brewAvailable = CaddyInstaller.locateBrew() != nil
        if !brewAvailable {
            method = .download
        }
        refreshBinary()
        helperInstaller.refreshStatus()
        trustStatus = CertificateStatusChecker.status()
    }

    private func refreshBinary() {
        if let binary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) {
            installedVersion = (try? CaddyInstallation.version(of: binary)) ?? binary.path
        } else {
            installedVersion = nil
        }
    }

    private func primaryAction() {
        switch step {
        case .caddy:
            if installedVersion != nil {
                Task { await startCaddyThenAdvance() }
            } else {
                switch method {
                case .homebrew: startBrewInstall()
                case .download: startDownload()
                }
            }
        case .helper:
            if helperInstaller.isEnabled {
                advance()
            } else if needsHelperApproval {
                recheckHelperApproval()
            } else {
                enableHelper()
            }
        case .certificate:
            if trustStatus == .installedAndTrusted {
                advance()
            } else {
                installCertificate()
            }
        case .ready:
            finish()
        }
    }

    private func goBack() {
        errorText = nil
        statusText = nil
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func advance() {
        errorText = nil
        statusText = nil
        guard let next = Step(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
        if next == .helper, needsHelperApproval {
            presentApprovalAlert()
        }
        if next == .certificate {
            Task { await prepareCertificateStep() }
        }
    }

    private func finish() {
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.finishSetup()
        } else {
            setupGate.markComplete(settings: settings)
        }
        dismissWindow(id: "setup")
    }

    private func startBrewInstall() {
        isBusy = true
        errorText = nil
        installedVersion = nil
        statusText = "Running brew install caddy…"
        Task {
            do {
                let binary = try await CaddyInstaller.installWithHomebrew()
                settings.caddyBinaryPathOverride = nil
                await finishCaddyInstall(binary: binary)
            } catch {
                failCaddyInstall(error)
            }
        }
    }

    private func startDownload() {
        isBusy = true
        errorText = nil
        installedVersion = nil
        statusText = "Downloading…"
        Task {
            do {
                let binary = try await CaddyInstaller.downloadOfficialBinary { message in
                    Task { @MainActor in
                        statusText = message
                    }
                }
                settings.caddyBinaryPathOverride = binary.path
                await finishCaddyInstall(binary: binary)
            } catch {
                failCaddyInstall(error)
            }
        }
    }

    private func finishCaddyInstall(binary: URL) async {
        installedVersion = (try? CaddyInstallation.version(of: binary)) ?? binary.path
        statusText = "Starting Caddy…"
        await vhostStore.regenerateAndReload()
        isBusy = false
        statusText = nil
        if let lastError = vhostStore.lastError {
            errorText = lastError
            return
        }
        advance()
    }

    private func failCaddyInstall(_ error: Error) {
        errorText = error.localizedDescription
        statusText = nil
        isBusy = false
    }

    private func startCaddyThenAdvance() async {
        isBusy = true
        statusText = "Starting Caddy…"
        errorText = nil
        await vhostStore.regenerateAndReload()
        isBusy = false
        statusText = nil
        if let lastError = vhostStore.lastError {
            errorText = lastError
            return
        }
        advance()
    }

    private func enableHelper() {
        errorText = nil
        isBusy = true
        statusText = "Registering helper…"
        helperInstaller.register()
        isBusy = false
        statusText = nil

        if needsHelperApproval {
            promptForHelperApproval()
            return
        }
        if case .failed(let message) = helperInstaller.state {
            errorText = message
            return
        }
        guard helperInstaller.isEnabled else { return }
        Task { await finishHelperSetup() }
    }

    private func promptForHelperApproval() {
        statusText = "Waiting for approval in System Settings."
        presentApprovalAlert()
    }

    private func presentApprovalAlert() {
        // Modal alert first. Do not auto-jump to System Settings.
        if showApprovalAlert {
            showApprovalAlert = false
            DispatchQueue.main.async {
                showApprovalAlert = true
            }
        } else {
            showApprovalAlert = true
        }
    }

    private func recheckHelperApproval() {
        errorText = nil
        helperInstaller.refreshStatus()
        if helperInstaller.isEnabled {
            statusText = nil
            Task { await finishHelperSetup() }
            return
        }
        if needsHelperApproval {
            statusText = "Still waiting for approval."
            presentApprovalAlert()
            return
        }
        enableHelper()
    }

    private func finishHelperSetup() async {
        guard step == .helper, helperInstaller.isEnabled, !isBusy else { return }
        isBusy = true
        statusText = "Applying port redirects…"
        errorText = nil
        _ = await vhostStore.syncPrivilegedNetworking()
        await vhostStore.regenerateAndReload()
        isBusy = false
        statusText = nil
        if let helperSyncError = vhostStore.helperSyncError {
            errorText = helperSyncError
            return
        }
        advance()
    }

    private func prepareCertificateStep() async {
        trustStatus = CertificateStatusChecker.status()
        guard trustStatus == .notInstalled else { return }
        statusText = "Starting Caddy so it can create the Root CA…"
        await vhostStore.ensureTLSRootCertificate()
        trustStatus = CertificateStatusChecker.status()
        if trustStatus == .notInstalled {
            statusText = "Caddy creates the Root CA after the first HTTPS site. You can skip and install later in Settings."
        } else {
            statusText = nil
        }
    }

    private func installCertificate() {
        isBusy = true
        errorText = nil
        statusText = "Installing Root CA…"
        Task {
            if CertificateStatusChecker.status() == .notInstalled {
                await vhostStore.ensureTLSRootCertificate()
            }
            do {
                try CertificateTrustInstaller.installRootCA()
            } catch {
                errorText = error.localizedDescription
            }
            trustStatus = CertificateStatusChecker.status()
            settings.hasTrustedCaddyCA = trustStatus == .installedAndTrusted
            isBusy = false
            statusText = nil
            if trustStatus == .installedAndTrusted, errorText == nil {
                advance()
            }
        }
    }
}

#Preview {
    let suite = "dev.mahmudz.Caddock.setup-preview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let settings = AppSettings(defaults: defaults)
    let store = VhostStore(
        settings: settings,
        processController: CaddyProcessController(settings: settings),
        helperInstaller: HelperInstaller(),
        helperClient: HelperClient(),
        dnsResponder: LocalDNSResponder()
    )
    return SetupWizardView()
        .environment(settings)
        .environment(store)
        .environment(SetupGate(settings: settings))
        .environment(HelperInstaller())
        .frame(width: 500, height: 420)
}
