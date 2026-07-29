//
//  PortsSettingsPane.swift
//  CaddyManager
//
//  Created by mahmud on 30/7/26.
//

import SwiftUI


struct PortsSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                portField(title: "HTTP Port", systemImage: "arrow.down.left.circle", value: $settings.httpPort)
                portField(title: "HTTPS Port", systemImage: "lock.circle", value: $settings.httpsPort)
                portField(title: "Admin API Port", systemImage: "terminal", value: $settings.adminPort)
            } footer: {
                Text("With the privileged helper enabled (Advanced tab), 80 and 443 redirect to the HTTP/HTTPS ports here automatically.")
            }
        }
        .settingsFormStyle()
    }

    private func portField(title: String, systemImage: String, value: Binding<Int>) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
                Stepper("", value: value, in: 1024...65535)
                    .labelsHidden()
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview {
    PortsSettingsPane()
}
