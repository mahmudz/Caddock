import Foundation
import Observation

@Observable
final class SetupGate {
    private(set) var isComplete: Bool

    init(settings: AppSettings) {
        let hasBinary = CaddyInstallation.locateBinary(override: settings.caddyBinaryPathOverride) != nil
        self.isComplete = settings.hasCompletedSetup && hasBinary
    }

    func markComplete(settings: AppSettings) {
        settings.hasCompletedSetup = true
        isComplete = true
    }
}
