import Foundation

struct DiskSnapshot: Sendable, Equatable {
    let total: Int64
    /// Finder'ın "kullanılabilir" dediği değer (temizlenebilir alan dahil).
    let available: Int64
    /// macOS'un yer gerektiğinde kendisinin sileceği alan (yerel Time Machine yedekleri, iCloud önbelleği…).
    /// `available` bunu zaten içerir.
    var purgeable: Int64 = 0

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum DiskStatus {
    /// Tek bir sistem çağrısı; maliyeti yok denecek kadar az.
    static func read(at url: URL = URL(fileURLWithPath: NSHomeDirectory())) -> DiskSnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        let available = values.volumeAvailableCapacityForImportantUsage ?? plain
        return DiskSnapshot(total: Int64(total), available: available, purgeable: max(available - plain, 0))
    }
}
