import AppKit
import SwiftUI

struct LogsView: View {
    @State private var logText: String = ""
    @State private var timer: Timer?
    @State private var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(logText.isEmpty ? "No log output yet." : logText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: logText) { _, _ in
                guard autoScroll else { return }
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .navigationTitle("Caddy Logs")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
            }
            ToolbarItem {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(logText.isEmpty)
            }
        }
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
