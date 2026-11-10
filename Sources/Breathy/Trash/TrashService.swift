import Foundation

struct TrashSummary: Sendable, Equatable {
    /// Boşaltınca Mac diskinde açılacak alan (yerel + iCloud çöpü).
    var diskBytes: Int64 = 0
    var items: Int = 0
    /// iCloud Drive çöpündeki öğelerin mantıksal boyutu.
    var iCloudBytes: Int64 = 0
    var iCloudItems: Int = 0

    var isEmpty: Bool { items == 0 }
}

struct TrashEmptyResult: Sendable, Equatable {
    var freedDiskBytes: Int64 = 0
    var freedICloudBytes: Int64 = 0
    var removed = 0
    var failed = 0
}

enum TrashError: Error, Equatable {
    /// ~/.Trash okunamıyor → Tam Disk Erişimi verilmemiş.
    case noPermission
}

/// Çöp'ü ölçer ve boşaltır. Yalnızca çöp klasörlerinin *doğrudan çocuklarını* siler.
struct TrashService: Sendable {
    let localTrash: URL
    let iCloudTrash: URL?

    static let user: TrashService = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return TrashService(
            localTrash: home.appending(path: ".Trash", directoryHint: .isDirectory),
            iCloudTrash: home.appending(
                path: "Library/Mobile Documents/com~apple~CloudDocs/.Trash",
                directoryHint: .isDirectory
            )
        )
    }()

    /// Finder'ın kendi oluşturduğu, kullanıcıya ait olmayan dosyalar.
    private static let ignoredNames: Set<String> = [".DS_Store", ".localized"]

    func summary() throws(TrashError) -> TrashSummary {
        var s = TrashSummary()
        for item in try items(in: localTrash, required: true) {
            s.items += 1
            s.diskBytes += FileSize.allocated(item)
        }
        // iCloud çöpüne sadece yerel çöp okunabiliyorsa (yani izin varsa) bakılır.
        if let iCloudTrash, let cloudItems = try? items(in: iCloudTrash, required: false) {
            for item in cloudItems {
                s.items += 1
                s.iCloudItems += 1
                s.diskBytes += FileSize.allocated(item)
                s.iCloudBytes += FileSize.logical(item)
            }
        }
        return s
    }

    func empty() throws(TrashError) -> TrashEmptyResult {
        var result = TrashEmptyResult()

        for item in try items(in: localTrash, required: true) {
            let size = FileSize.allocated(item)
            if Self.remove(item, under: localTrash) {
                result.removed += 1
                result.freedDiskBytes += size
            } else {
                result.failed += 1
            }
        }

        if let iCloudTrash, let cloudItems = try? items(in: iCloudTrash, required: false) {
            for item in cloudItems {
                let disk = FileSize.allocated(item)
                let cloud = FileSize.logical(item)
                if Self.remove(item, under: iCloudTrash) {
                    result.removed += 1
                    result.freedDiskBytes += disk
                    result.freedICloudBytes += cloud
                } else {
                    result.failed += 1
                }
            }
        }
        return result
    }

    // MARK: - Yardımcılar

    private func items(in dir: URL, required: Bool) throws(TrashError) -> [URL] {
        do {
            return try FileManager.default
                .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
                .filter { !Self.ignoredNames.contains($0.lastPathComponent) }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []  // klasör yok = çöp boş
        } catch {
            if required { throw .noPermission }
            return []
        }
    }

    /// Güvenlik: sadece çöp klasörünün doğrudan çocuğuysa siler.
    private static func remove(_ item: URL, under root: URL) -> Bool {
        guard item.deletingLastPathComponent().standardizedFileURL.path
                == root.standardizedFileURL.path else { return false }
        let fm = FileManager.default
        if (try? fm.removeItem(at: item)) != nil { return true }
        // Kilitli (Finder'da "Kilitli" işaretli) öğe: kilidi kaldırıp bir kez daha dene.
        try? fm.setAttributes([.immutable: false], ofItemAtPath: item.path)
        return (try? fm.removeItem(at: item)) != nil
    }
}
