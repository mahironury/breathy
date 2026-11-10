import Foundation

struct DiskSnapshot: Sendable, Equatable {
    let total: Int64
    /// Finder'ın "kullanılabilir" dediği değer (temizlenebilir alan dahil).
    let available: Int64

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
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskSnapshot(total: Int64(total), available: available)
    }
}
