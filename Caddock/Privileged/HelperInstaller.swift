import Foundation
import Observation
import ServiceManagement

enum HelperInstallState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case failed(String)
}

@Observable
final class HelperInstaller: PrivilegedHelperInstalling {
    private(set) var state: HelperInstallState = .notRegistered

    private var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
    }

    var isEnabled: Bool {
        if case .enabled = state { return true }
        return false
    }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        state = Self.map(service.status)
    }

    /// `SMAppService.daemon.register()` does not show a password dialog.
    /// Status becomes `.requiresApproval` until the user enables the item in
    /// System Settings → General → Login Items & Extensions → Background Items.
    func register() {
        do {
            try service.register()
            refreshStatus()
        } catch {
            refreshStatus()
            if state == .requiresApproval || state == .enabled {
                return
            }
            if Self.isApprovalError(error) {
                state = .requiresApproval
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    func unregister() {
        do {
            try service.unregister()
            refreshStatus()
        } catch {
            refreshStatus()
            if state != .notRegistered {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func reinstall() async {
        do {
            try await service.unregister()
        } catch {
            // Continue — register may still succeed.
        }

        refreshStatus()
        try? await Task.sleep(nanoseconds: 500_000_000)

        do {
            try service.register()
            refreshStatus()
        } catch {
            refreshStatus()
            if state == .requiresApproval || state == .enabled {
                return
            }
            if Self.isApprovalError(error) {
                state = .requiresApproval
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func isApprovalError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "SMAppServiceErrorDomain" { return true }
        let message = error.localizedDescription.lowercased()
        return message.contains("not permitted")
            || message.contains("approval")
            || message.contains("denied")
            || message.contains("authorization")
    }

    private static func map(_ status: SMAppService.Status) -> HelperInstallState {
        switch status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notRegistered
        }
    }
}
