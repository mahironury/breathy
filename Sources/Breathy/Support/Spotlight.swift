import CoreServices
import Foundation

/// Spotlight'tan "son açılma" ve "eklenme" tarihleri.
/// Dosya sistemi erişim tarihinden çok daha güvenilirdir (macOS onu her zaman güncellemez).
enum Spotlight {
    static func lastUsed(_ url: URL) -> Date? { date(kMDItemLastUsedDate, of: url) }
    static func dateAdded(_ url: URL) -> Date? { date(kMDItemDateAdded, of: url) }

    private static func date(_ key: CFString, of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, key) as? Date
    }
}
