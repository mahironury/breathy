import Foundation

/// Son tarama sonucunu saklar; panel açılınca anında gösterilir.
/// Konum: ~/Library/Application Support/Breathy/last-scan.json
enum ResultStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Breathy", directoryHint: .isDirectory)
    }

    static var fileURL: URL { directory.appending(path: "last-scan.json") }

    static func load() -> ScanResult? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ScanResult.self, from: data)
    }

    static func save(_ result: ScanResult) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(result) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
