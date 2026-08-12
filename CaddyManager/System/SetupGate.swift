import Foundation
import Observation

@Observable
final class SetupGate {
    private(set) var isComplete: Bool

    init(settings: AppSettings) {
        let hasBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) != nil
        self.isComplete = hasBinary
        if hasBinary {
            settings.hasCompletedCaddyOnboarding = true
        }
    }

    func markComplete(settings: AppSettings) {
        settings.hasCompletedCaddyOnboarding = true
        isComplete = true
    }
}
