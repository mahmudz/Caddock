//
//  SettingsComponents.swift
//  CaddyManager
//
//  Created by mahmud on 24/7/26.
//

import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SettingsRow<Trailing: View>: View {
    var icon: String?
    var iconColor: Color = .accentColor
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 44)
    }
}

struct SettingsFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

struct SettingsTabButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
