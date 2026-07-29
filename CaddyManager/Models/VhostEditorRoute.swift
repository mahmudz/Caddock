import Foundation

struct VhostEditorRoute: Identifiable, Codable {
    let id: UUID
    var vhost: Vhost
    let isNew: Bool

    static func newVhost() -> VhostEditorRoute {
        VhostEditorRoute(
            id: UUID(),
            vhost: Vhost(domain: "", kind: .staticSite),
            isNew: true
        )
    }

    static func edit(_ vhost: Vhost) -> VhostEditorRoute {
        VhostEditorRoute(id: vhost.id, vhost: vhost, isNew: false)
    }

    var windowTitle: String {
        isNew ? "New Vhost" : "Edit Vhost"
    }
}
