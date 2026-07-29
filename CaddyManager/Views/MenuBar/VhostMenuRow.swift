//
//  VhostMenuRow.swift
//  CaddyManager
//
//  Created by mahmud on 30/7/26.
//

import SwiftUI


struct VhostMenuRow: View {
    let vhost: Vhost
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: vhost.kind.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vhost.domain)
                        .lineLimit(1)
                    Text(vhost.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: vhost.sslEnabled ? "lock.fill" : "lock.open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}
