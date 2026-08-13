import Foundation

struct VhostValidationIssue: Identifiable, Equatable {
    enum Severity: Equatable {
        case error
        case warning
    }

    var id: String { message }
    var severity: Severity
    var message: String
}
