import ServiceManagement
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
            Tab("Advanced", systemImage: "lock.shield") {
                HelperSettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .frame(width: 440)
        .tabViewStyle(.tabBarOnly)
    }
}





