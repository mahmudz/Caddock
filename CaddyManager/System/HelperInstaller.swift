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
final class HelperInstaller {
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

    func register() {
        do {
            try service.register()
            refreshStatus()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func unregister() {
        do {
            try service.unregister()
            refreshStatus()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Unregisters and re-registers the helper daemon. Use after rebuilding the app
    /// when XPC connections fail due to a stale installed helper.
    func reinstall() async {
        do {
            try await service.unregister()
        } catch {
            state = .failed(error.localizedDescription)
        }

        refreshStatus()
        try? await Task.sleep(nanoseconds: 500_000_000)

        do {
            try service.register()
            refreshStatus()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
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
