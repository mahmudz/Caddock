import Foundation

enum CaddyOnboardingPresenter {
    static let windowID = "onboarding"

    static func needsPresentation(settings: AppSettings) -> Bool {
        CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) == nil
    }

    static func presentIfNeeded(settings: AppSettings, open: @escaping () -> Void) {
        guard needsPresentation(settings: settings) else { return }
        present(open: open)
    }

    static func present(open: @escaping () -> Void) {
        AppWindowPresenter.present(open: open, target: .window(id: windowID))
    }
}
