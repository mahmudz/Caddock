import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(CaddyProcessController.self) private var processController
    @Environment(VhostStore.self) private var vhostStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.headline)
                Spacer()
            }

            if let lastError = vhostStore.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            Divider()

            Button(isRunning ? "Stop Caddy" : "Start Caddy") {
                Task {
                    if isRunning {
                        await processController.stop()
                    } else {
                        await vhostStore.regenerateAndReload()
                    }
                }
            }

            Divider()

            Button("Vhosts…") { openWindow(id: "vhosts") }
            Button("Logs…") { openWindow(id: "logs") }
            Button("Settings…") { openWindow(id: "settings") }

            Divider()

            Button("Quit CaddyManager") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private var isRunning: Bool {
        if case .running = processController.status { return true }
        return false
    }

    private var statusText: String {
        switch processController.status {
        case .stopped: return "Caddy stopped"
        case .starting: return "Caddy starting…"
        case .running: return "Caddy running"
        case .failed(let message): return "Caddy failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch processController.status {
        case .stopped: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .failed: return .red
        }
    }
}
