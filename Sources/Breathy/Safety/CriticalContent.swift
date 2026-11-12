import Foundation
import PDFKit
import Vision

/// Dosyanın içeriğinde hassas bilgi var mı? Metin dosyaları, PDF'ler ve görüntüler
/// (ekran görüntüsündeki yazılar Mac'in kendi metin tanımasıyla, internete çıkmadan okunur).
enum CriticalContent {
    /// Taramada içerik okumaya ayrılan süre. Sınırı aşan dosyalar silmeden hemen önce okunur.
    final class Budget: @unchecked Sendable {
        let deadline: Date
        init(seconds: Double) { deadline = Date().addingTimeInterval(seconds) }
        var isOver: Bool { Date() >= deadline }
    }

    static let textExtensions: Set<String> = ["csv", "tsv", "txt", "json", "md", "rtf", "html", "htm", "xml"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "gif"]
    static let maxTextBytes = 1_000_000
    static let maxImageBytes: Int64 = 40_000_000
    static let maxPDFPages = 5

    static func kind(of url: URL, budget: Budget?) -> CriticalData.Kind? {
        if budget?.isOver == true { return nil }
        guard let text = extractText(url), !text.isEmpty else { return nil }
        return textKind(text)
    }

    static func extractText(_ url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if textExtensions.contains(ext) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: maxTextBytes) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            return (0..<min(document.pageCount, maxPDFPages))
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
        }
        if imageExtensions.contains(ext) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            guard size <= maxImageBytes else { return nil }
            return recognizeText(url)
        }
        return nil
    }

    /// Görüntüdeki yazılar (Vision, cihaz üzerinde).
    static func recognizeText(_ url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(url: url, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// Metinde kurtarma ifadesi, gizli anahtar ya da korunması gereken başka bir bilgi var mı?
    static func textKind(_ text: String) -> CriticalData.Kind? {
        let words = CriticalData.tokens(text)
        if CriticalData.containsPhrase(words, CriticalData.recoveryPhrases)
            || words.contains(where: { $0 == "mnemonic" || $0 == "privkey" || $0 == "privatekey" }) {
            return .recoveryCodes
        }
        if matches(text, #"\b[xyzt]prv[1-9A-HJ-NP-Za-km-z]{100,}"#, ignoreCase: false) { return .secretKey }
        // Kesin adresler: Bitcoin (bc1…), Ethereum (0x + 40 hane), işlem kimliği (0x + 64 hane), xpub/zpub.
        let strong: [(pattern: String, ignoreCase: Bool)] = [
            (#"\bbc1[02-9ac-hj-np-z]{25,87}\b"#, true),
            (#"\b0x[0-9a-f]{40}\b"#, true),
            (#"\b0x[0-9a-f]{64}\b"#, true),
            (#"\b[xyz]pub[1-9A-HJ-NP-Za-km-z]{100,}"#, false),
        ]
        if strong.contains(where: { matches(text, $0.pattern, ignoreCase: $0.ignoreCase) }) { return .cryptoContent }

        let keywordCount = Set(words.compactMap { token in
            CriticalData.cryptoWords.first { word in word.count <= 4 ? token == word : token.hasPrefix(word) }
        }).count
        // Eski Bitcoin ve TRON adresleri başka kimliklere benzeyebilir: yanında bir kripto sözcüğü de olmalı.
        let weak = [#"\b[13][1-9A-HJ-NP-Za-km-z]{25,34}\b"#, #"\bT[1-9A-HJ-NP-Za-km-z]{33}\b"#]
        if keywordCount >= 1, weak.contains(where: { matches(text, $0, ignoreCase: false) }) { return .cryptoContent }
        return keywordCount >= 2 ? .cryptoContent : nil
    }

    // MARK: - Zip arşivleri

    static let maxZipDirectoryBytes: UInt64 = 16_000_000

    /// Zip arşivindeki dosyaların yolları ("Yedek/kasa.kdbx"). Arşiv açılmaz: sadece sonundaki
    /// içindekiler listesi okunur, büyük arşivlerde de bir anlık iştir. Okunamazsa nil.
    static func zipEntryNames(_ url: URL, maxEntries: Int = 100_000) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size >= 22 else { return nil }

        // Sondaki kayıt (EOCD) en fazla 64 KB'lık bir yorumla birlikte son 65.557 baytın içindedir.
        let tailLength = min(size, 65_557)
        guard (try? handle.seek(toOffset: size - tailLength)) != nil,
              let tailData = try? handle.read(upToCount: Int(tailLength)) else { return nil }
        let tail = [UInt8](tailData)
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1)
            .first(where: { tail[$0] == 0x50 && tail[$0 + 1] == 0x4B && tail[$0 + 2] == 0x05 && tail[$0 + 3] == 0x06 })
        else { return nil }

        var directorySize = UInt64(le32(tail, eocd + 12))
        var directoryOffset = UInt64(le32(tail, eocd + 16))
        if directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            // ZIP64: konum kaydı EOCD'nin hemen önündedir, asıl kayıt dosyanın başka bir yerindedir.
            let locator = eocd - 20
            guard locator >= 0, le32(tail, locator) == 0x0706_4B50 else { return nil }
            let record = le64(tail, locator + 8)
            guard record + 56 <= size, (try? handle.seek(toOffset: record)) != nil,
                  let recordData = try? handle.read(upToCount: 56), recordData.count == 56 else { return nil }
            let bytes = [UInt8](recordData)
            guard le32(bytes, 0) == 0x0606_4B50 else { return nil }
            directorySize = le64(bytes, 40)
            directoryOffset = le64(bytes, 48)
        }
        guard directorySize <= maxZipDirectoryBytes, directoryOffset + directorySize <= size,
              (try? handle.seek(toOffset: directoryOffset)) != nil,
              let directoryData = try? handle.read(upToCount: Int(directorySize)) else { return nil }

        let directory = [UInt8](directoryData)
        var names: [String] = []
        var i = 0
        while i + 46 <= directory.count, le32(directory, i) == 0x0201_4B50, names.count < maxEntries {
            let nameLength = Int(le16(directory, i + 28))
            let extraLength = Int(le16(directory, i + 30))
            let commentLength = Int(le16(directory, i + 32))
            guard i + 46 + nameLength <= directory.count else { break }
            let raw = directory[(i + 46)..<(i + 46 + nameLength)]
            if let name = String(bytes: raw, encoding: .utf8) ?? String(bytes: raw, encoding: .isoLatin1) {
                names.append(name)
            }
            i += 46 + nameLength + extraLength + commentLength
        }
        return names
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(le16(b, i)) | UInt32(le16(b, i + 2)) << 16
    }
    private static func le64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(le32(b, i)) | UInt64(le32(b, i + 4)) << 32
    }

    private static func matches(_ text: String, _ pattern: String, ignoreCase: Bool) -> Bool {
        let options: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
