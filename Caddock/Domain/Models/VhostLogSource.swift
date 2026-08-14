import Foundation

enum VhostLogSourceKind: String, Codable, CaseIterable, Identifiable {
    case none
    case file
    case docker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .file: return "File"
        case .docker: return "Docker"
        }
    }
}

struct VhostLogSource: Codable, Equatable {
    var kind: VhostLogSourceKind = .none
    var filePath: String?
    var followFile: Bool = true
    var linesFromEnd: Int? = 100
    var dockerContainer: String?
    var dockerFollow: Bool = true
    var dockerTimestamps: Bool = false
    var dockerTail: Int = 100

    static let none = VhostLogSource()

    var isConfigured: Bool {
        switch kind {
        case .none: return false
        case .file: return !(filePath?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        case .docker: return !(dockerContainer?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }
}
