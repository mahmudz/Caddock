import AppKit
import SwiftUI

struct SiteLogsView: View {
    let vhost: Vhost

    @StateObject private var streamer = SiteLogStreamer()
    @State private var searchText = ""
    @State private var autoScroll = true

    private var displayedText: String {
        guard !searchText.isEmpty else { return streamer.text }
        return streamer.text
            .components(separatedBy: "\n")
            .filter { $0.localizedCaseInsensitiveContains(searchText) }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = streamer.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(8)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.4))

            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayedText.isEmpty ? "Waiting for log output…" : displayedText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: streamer.text) { _, _ in
                    guard autoScroll else { return }
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Logs — \(vhost.domain)")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
            }
            ToolbarItem {
                Button {
                    streamer.text = ""
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
            ToolbarItem {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(displayedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(displayedText.isEmpty)
            }
        }
        .onAppear {
            streamer.start(source: vhost.logSource)
        }
        .onDisappear {
            streamer.stop()
        }
    }
}
