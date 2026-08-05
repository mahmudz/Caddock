import Foundation

struct HelperState: Codable {
    var httpPort: Int?
    var httpsPort: Int?
    var domains: [String] = []
    var resolverTLDs: [String] = []
    var dnsPort: Int?

    static func load() -> HelperState {
        guard let data = try? Data(contentsOf: HelperConstants.helperStateFileURL),
              let state = try? JSONDecoder().decode(HelperState.self, from: data) else {
            return HelperState()
        }
        return state
    }

    func save() {
        let directory = HelperConstants.helperStateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: HelperConstants.helperStateFileURL, options: .atomic)
    }
}
