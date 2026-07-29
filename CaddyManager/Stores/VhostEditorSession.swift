import Foundation
import Observation

@Observable
final class VhostEditorSession {
    private(set) var route: VhostEditorRoute?

    var windowTitle: String {
        route?.windowTitle ?? "Vhost"
    }

    func presentNew() {
        route = .newVhost()
    }

    func presentEdit(_ vhost: Vhost) {
        route = .edit(vhost)
    }

    func present(_ route: VhostEditorRoute) {
        self.route = route
    }

    func dismiss() {
        route = nil
    }
}
