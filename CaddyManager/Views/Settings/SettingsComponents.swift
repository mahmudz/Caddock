//
//  SettingsComponents.swift
//  CaddyManager
//
//  Created by mahmud on 24/7/26.
//

import SwiftUI

extension View {
    /// Grouped form styling for macOS 26 settings panes.
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyleSoftIfAvailable()
    }
}

private extension View {
    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
