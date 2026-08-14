import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Ports", systemImage: "network") {
                PortsSettingsPane()
            }
            Tab("Certificates", systemImage: "checkmark.shield") {
                CertificateSettingsPane()
            }
            Tab("Advanced", systemImage: "lock.shield") {
                HelperSettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .tabViewStyle(.tabBarOnly)
    }
}
