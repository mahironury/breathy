import Darwin
import Foundation

/// macOS'un takas (swap) dosyaları ve Mac'in ne zamandır açık olduğu.
/// Takas dosyaları yeniden başlatınca silinir; uzun süre açık kalan Mac'te onlarca GB tutabilir.
struct SwapInfo: Sendable, Equatable {
    /// Diskteki takas dosyalarının toplam boyutu (/System/Volumes/VM/swapfile*).
    let fileBytes: Int64
    let usedBytes: Int64
    let bootDate: Date?

    /// Bu değerin üstünde panelde "yeniden başlat" önerisi gösterilir.
    static let warningBytes: Int64 = 4_000_000_000

    var shouldWarn: Bool { fileBytes >= Self.warningBytes }

    func uptimeDays(now: Date = Date()) -> Int? {
        bootDate.map { Int(now.timeIntervalSince($0) / 86_400) }
    }

    static func read() -> SwapInfo? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }

        var boot = timeval()
        var bootSize = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let bootDate: Date? = sysctl(&mib, 2, &boot, &bootSize, nil, 0) == 0
            ? Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
            : nil

        return SwapInfo(fileBytes: Int64(usage.xsu_total), usedBytes: Int64(usage.xsu_used), bootDate: bootDate)
    }
}
