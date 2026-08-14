import Foundation

struct VhostExportDocument: Codable {
    var version: Int
    var exportedAt: Date
    var appVersion: String
    var sites: [Vhost]
}

enum VhostImportExport {
    static let fileExtension = "caddock"

    static func exportData(vhosts: [Vhost]) throws -> Data {
        let doc = VhostExportDocument(
            version: 1,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            sites: vhosts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }

    static func importVhosts(from data: Data, existing: [Vhost]) throws -> (imported: [Vhost], skipped: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sites: [Vhost]
        if let doc = try? decoder.decode(VhostExportDocument.self, from: data) {
            sites = doc.sites
        } else {
            sites = try decoder.decode([Vhost].self, from: data)
        }
        let reserved = Set(existing.flatMap(\.allDomains))
        var imported: [Vhost] = []
        var skipped = 0
        for var site in sites {
            let domains = site.allDomains
            if domains.contains(where: { reserved.contains($0) })
                || imported.contains(where: { Set($0.allDomains).intersection(domains).isEmpty == false }) {
                skipped += 1
                continue
            }
            site.id = UUID()
            imported.append(site)
        }
        return (imported, skipped)
    }
}
