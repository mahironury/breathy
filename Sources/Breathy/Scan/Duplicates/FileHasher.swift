import CryptoKit
import Darwin
import Foundation

/// Dosya parmak izi. Okumalar `F_NOCACHE` ile yapılır: GB'larca dosya okunsa bile
/// macOS'un bellek önbelleği şişmez, diğer uygulamalar yavaşlamaz.
final class FileHasher {
    /// Kısmi parmak izi: dosyanın başından ve sonundan bu kadar bayt.
    static let partialSpan = 64 * 1024
    private var buffer = [UInt8](repeating: 0, count: 1 << 20)

    /// Sadece iCloud'da duran (Mac'e indirilmemiş) bir dosyayı okumak indirmeyi tetikler → okuma.
    static func isSafeToRead(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        else { return false }
        if v.isUbiquitousItem == true { return v.ubiquitousItemDownloadingStatus == .current }
        return true
    }

    /// Boyut + ilk 64 KB + son 64 KB.
    func partial(_ url: URL, size: Int64) -> Data? {
        guard let fd = Self.openForReading(url) else { return nil }
        defer { close(fd) }
        var sha = SHA256()
        withUnsafeBytes(of: size.littleEndian) { sha.update(bufferPointer: $0) }
        guard readUpTo(Self.partialSpan, from: fd, into: &sha) else { return nil }
        if size > Int64(Self.partialSpan) {
            let tail = max(size - Int64(Self.partialSpan), Int64(Self.partialSpan))
            guard lseek(fd, off_t(tail), SEEK_SET) >= 0,
                  readUpTo(Self.partialSpan, from: fd, into: &sha) else { return nil }
        }
        return Data(sha.finalize())
    }

    /// Dosyanın tamamı, 1 MB'lık parçalar halinde. Her parçada iptal kontrolü.
    func full(_ url: URL, ctx: ScanContext) throws -> Data? {
        guard let fd = Self.openForReading(url) else { return nil }
        defer { close(fd) }
        var sha = SHA256()
        while true {
            try ctx.checkpoint(nil)
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 { return nil }
            if n == 0 { break }
            buffer.withUnsafeBytes { sha.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
        }
        return Data(sha.finalize())
    }

    private func readUpTo(_ limit: Int, from fd: Int32, into sha: inout SHA256) -> Bool {
        var remaining = limit
        while remaining > 0 {
            let want = remaining
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
            if n < 0 { return false }
            if n == 0 { break }
            buffer.withUnsafeBytes { sha.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
            remaining -= n
        }
        return true
    }

    private static func openForReading(_ url: URL) -> Int32? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        _ = fcntl(fd, F_NOCACHE, 1)
        return fd
    }

    /// APFS: bu dosyaya özel (başka bir klonla paylaşılmayan) blokların boyutu.
    /// Bir kopya APFS klonuysa silmek neredeyse hiç yer açmaz; bu değer bunu yakalar.
    static func privateSize(_ path: String) -> Int64? {
        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        var raw = [UInt8](repeating: 0, count: 32)
        let status = raw.withUnsafeMutableBytes {
            getattrlist(path, &attrs, $0.baseAddress, $0.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        // Düzen: [u_int32_t uzunluk][off_t özel boyut]
        return raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}
