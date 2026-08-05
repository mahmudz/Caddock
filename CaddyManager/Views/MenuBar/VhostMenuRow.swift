import SwiftUI

struct VhostMenuRow: View {
    let vhost: Vhost
    let health: BackendHealthStatus
    let onOpen: () -> Void
    var onLogs: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 8, height: 8)
                    Image(systemName: vhost.kind.systemImage)
                        .frame(width: 18)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(vhost.domain)
                                .lineLimit(1)
                            if vhost.isWildcard {
                                Text("wildcard")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                        Text(vhost.kind.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: vhost.sslEnabled ? "lock.fill" : "lock.open")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "safari")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onLogs {
                Button(action: onLogs) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Site logs")
            }
        }
        .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }

    private var healthColor: Color {
        switch health {
        case .healthy: return .green
        case .unhealthy: return .red
        case .checking: return .yellow
        case .unknown: return .secondary.opacity(0.4)
        }
    }
}
