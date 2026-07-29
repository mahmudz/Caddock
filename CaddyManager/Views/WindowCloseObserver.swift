import AppKit
import SwiftUI

struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.observe(view: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.observe(view: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    final class Coordinator {
        let onClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var observer: NSObjectProtocol?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func observe(view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                guard window !== self.observedWindow else { return }
                self.observedWindow = window
                if let observer = self.observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                self.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.onClose()
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
