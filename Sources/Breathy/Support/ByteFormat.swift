import Foundation

/// Boyut ve yüzdeleri Türkçe biçimlendirir. Finder gibi 1000 tabanlı (1 GB = 10⁹ bayt).
enum ByteFormat {
    private static let locale = Locale(identifier: "tr_TR")

    /// Örn. "11,8 GB", "245 GB", "940 MB".
    static func string(_ bytes: Int64) -> String {
        let b = Double(max(bytes, 0))
        let (value, unit): (Double, String) = switch b {
        case 1e12...: (b / 1e12, "TB")
        case 1e9...: (b / 1e9, "GB")
        case 1e6...: (b / 1e6, "MB")
        case 1e3...: (b / 1e3, "KB")
        default: (b, "bayt")
        }
        let maxFraction = (value >= 100 || unit == "bayt") ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(0...maxFraction)).locale(locale))
        return "\(number) \(unit)"
    }

    /// Örn. "%95" (Türkçede yüzde işareti başta).
    static func percent(_ fraction: Double) -> String {
        "%\(Int((fraction * 100).rounded()))"
    }
}
