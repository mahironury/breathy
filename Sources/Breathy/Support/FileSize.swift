import Foundation

/// Dosya ve klasör boyutu ölçümü.
enum FileSize {
    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .totalFileSizeKey, .fileSizeKey,
    ]

    /// Diskte gerçekten kapladığı alan — silince Mac'te açılacak yer.
    static func allocated(_ url: URL) -> Int64 {
        sum(url) { Int64($0.totalFileAllocatedSize ?? $0.fileAllocatedSize ?? 0) }
    }

    /// Mantıksal boyut — sadece bulutta duran iCloud dosyalarında da doğru değeri verir.
    static func logical(_ url: URL) -> Int64 {
        sum(url) { Int64($0.totalFileSize ?? $0.fileSize ?? 0) }
    }

    private static func sum(_ url: URL, _ measure: (URLResourceValues) -> Int64) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        // Sembolik bağlantıların hedefine gidilmez; bağlantının kendisi ölçülür.
        guard values.isDirectory == true, values.isSymbolicLink != true else { return measure(values) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }  // okunamayan alt öğeyi atla, devam et
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let v = try? child.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
            total += measure(v)
        }
        return total
    }
}
