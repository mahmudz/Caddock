import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DockerComposeInjectView: View {
    @Environment(VhostStore.self) private var vhostStore

    @State private var composeURL: URL?
    @State private var services: [DockerComposeInjector.ServiceInfo] = []
    @State private var selectedServices: Set<String> = []
    @State private var selectedDomains: Set<String> = []
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var availableDomains: [String] {
        vhostStore.enabledHostnamesForHosts()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inject Caddock's Root CA and domain extra_hosts into a docker-compose.yml override.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Select File…", action: pickComposeFile)
                if let composeURL {
                    Text(composeURL.lastPathComponent)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            if !services.isEmpty {
                GroupBox("Services") {
                    List(services, selection: $selectedServices) { service in
                        HStack {
                            Text(service.name)
                            Spacer()
                            if !service.existingExtraHosts.isEmpty {
                                Text("Has hosts")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(service.name)
                    }
                    .frame(minHeight: 120)
                }
            }

            if !availableDomains.isEmpty {
                GroupBox("Domains") {
                    List(availableDomains, id: \.self, selection: $selectedDomains) { domain in
                        Text(domain).tag(domain)
                    }
                    .frame(minHeight: 100)
                }
            } else {
                Text("No enabled non-wildcard domains to inject.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Inject Certificate", action: inject)
                    .buttonStyle(.borderedProminent)
                    .disabled(composeURL == nil || selectedServices.isEmpty)

                Spacer()

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            GroupBox("After inject") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Creates docker-compose.override.yml and .caddock-root-ca.crt")
                    Text("Debian/Ubuntu: update-ca-certificates")
                    Text("Node: NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/caddock-root-ca.crt")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            selectedDomains = Set(availableDomains)
        }
    }

    private func pickComposeFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "yml") ?? .yaml,
            UTType(filenameExtension: "yaml") ?? .yaml,
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        composeURL = url
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            services = DockerComposeInjector.parseServices(from: text)
            selectedServices = Set(services.map(\.name))
            statusMessage = "Found \(services.count) service(s)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inject() {
        guard let composeURL else { return }
        let certURL = CertificateStatusChecker.rootCertificateURL
        guard FileManager.default.fileExists(atPath: certURL.path) else {
            errorMessage = "Root CA not found. Enable TLS on a vhost and start Caddy first."
            return
        }
        do {
            let result = try DockerComposeInjector.inject(
                composeFileURL: composeURL,
                selectedServices: selectedServices,
                domains: Array(selectedDomains).sorted(),
                rootCertURL: certURL
            )
            statusMessage = "Wrote \(result.overrideURL.lastPathComponent) for \(result.servicesTouched.joined(separator: ", "))."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
