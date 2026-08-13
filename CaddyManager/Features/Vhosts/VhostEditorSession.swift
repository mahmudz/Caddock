import Foundation
import Observation

@Observable
final class VhostEditorSession {
    private(set) var route: VhostEditorRoute?

    var windowTitle: String {
        route?.windowTitle ?? "Vhost"
    }

    func present(_ route: VhostEditorRoute) {
        self.route = route
    }

    func dismiss() {
        route = nil
    }
}
