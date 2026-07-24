import SwiftUI

struct LogsView: View {
    @State private var logText: String = ""
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            Text(logText.isEmpty ? "No log output yet." : logText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minWidth: 560, minHeight: 400)
        .navigationTitle("Caddy Logs")
        .onAppear {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refresh()
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refresh() {
        guard let url = try? CaddyProcessController.logFileURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        logText = text
    }
}
