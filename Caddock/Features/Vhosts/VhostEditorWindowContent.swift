import SwiftUI

struct VhostEditorWindowContent: View {
    @Environment(VhostEditorSession.self) private var session
    @Environment(VhostStore.self) private var vhostStore

    var body: some View {
        Group {
            if let route = session.route {
                VhostEditorView(vhost: route.vhost, isNew: route.isNew)
                    .environment(vhostStore)
                    .navigationTitle(route.windowTitle)
                    .id(route.id)
            } else {
                Color.clear.frame(minWidth: 480, minHeight: 1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowCloseObserver(onClose: { session.dismiss() }))
    }
}
