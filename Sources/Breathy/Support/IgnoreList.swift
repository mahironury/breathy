import Foundation

/// "Bunu bir daha önerme": kullanıcının gizlediği yollar. Bir klasör gizlenince içindekiler de gizlenir.
/// Konum: ~/Library/Application Support/Breathy/ignored.json
struct IgnoreList: Codable, Sendable, Equatable {
    private(set) var paths: [String] = []

    var isEmpty: Bool { paths.isEmpty }

    func contains(_ path: String) -> Bool {
        paths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    mutating func add(_ path: String) {
        guard !paths.contains(path) else { return }
        paths.append(path)
        paths.sort()
    }

    mutating func remove(_ path: String) {
        paths.removeAll { $0 == path }
    }

    /// Gizlenenleri sonuçtan çıkarır. Bir çift grubunun korunacak kopyası gizlenirse grubun
    /// tamamı gizlenir (korunacak kopyası görünmeyen bir grup gösterilmez).
    func apply(to result: inout ScanResult) {
        guard !paths.isEmpty else { return }
        let hiddenGroups = Set(result.findings.compactMap { finding -> String? in
            guard let group = finding.groupID, !finding.suggested, contains(finding.path) else { return nil }
            return group
        })
        result.removeFindings { finding in
            contains(finding.path) || finding.groupID.map(hiddenGroups.contains) == true
        }
    }

    // MARK: - Kayıt

    static var fileURL: URL { ResultStore.directory.appending(path: "ignored.json") }

    static func load(from url: URL = fileURL) -> IgnoreList {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode(IgnoreList.self, from: data) else { return IgnoreList() }
        return list
    }

    func save(to url: URL = Self.fileURL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
