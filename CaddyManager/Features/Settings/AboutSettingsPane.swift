import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    Text("CaddyManager")
                        .font(.title2.bold())

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Bundle ID", value: bundleIdentifier)
                if let copyright {
                    LabeledContent("Copyright", value: copyright)
                }
                LabeledContent("Repository") {
                    Link("mahmudz/CaddyManager", destination: Self.repositoryURL)
                }
                LabeledContent("Author") {
                    Link("mahmudz", destination: Self.authorURL)
                }
            }

            Section {
                LabeledContent("Caddy") {
                    Link("caddyserver.com", destination: Self.caddyURL)
                }
            } header: {
                Text("Credits")
            } footer: {
                Text("Caddy serves every vhost. Not affiliated with official caddy project.")
            }
        }
        .settingsFormStyle()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    private var copyright: String? {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
    }

    private static let repositoryURL = URL(string: "https://github.com/mahmudz/CaddyManager")!
    private static let authorURL = URL(string: "https://github.com/mahmudz")!
    private static let caddyURL = URL(string: "https://caddyserver.com")!
    private static let valetURL = URL(string: "https://github.com/laravel/valet")!
}
