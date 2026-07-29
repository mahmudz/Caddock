//
//  AboutSettingsPane.swift
//  CaddyManager
//
//  Created by mahmud on 30/7/26.
//

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
            }

            Section {
                Link(destination: URL(string: "https://caddyserver.com")!) {
                    Label("Caddy Web Server", systemImage: "link")
                }
            } footer: {
                Text("Manages a single local Caddy instance for development vhosts.")
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
}
