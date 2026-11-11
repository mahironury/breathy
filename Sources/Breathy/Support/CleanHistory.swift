import Foundation

/// Breathy'nin yaptığı her temizliğin kaydı: ne, ne zaman, ne kadar yer açıldı, hangileri Çöp'e gitti.
/// Konum: ~/Library/Application Support/Breathy/history.json (son 200 kayıt).
struct CleanRecord: Codable, Sendable, Identifiable, Equatable {
    enum Kind: String, Codable, Sendable {
        case selection   // Detaylar → Seçilenleri temizle
        case quickClean  // Panel → Güvenli olanları temizle
        case trash       // Çöp'ü boşalt
        case docker      // Docker'da kullanılmayanlar
        case oldCopy     // Eski Breathy kopyası

        var title: String {
            switch self {
            case .selection: "Seçilenler temizlendi"
            case .quickClean: "Güvenli olanlar temizlendi"
            case .trash: "Çöp boşaltıldı"
            case .docker: "Docker'da kullanılmayanlar temizlendi"
            case .oldCopy: "Eski Breathy kopyası Çöp'e taşındı"
            }
        }

        var icon: String {
            switch self {
            case .selection: "checklist"
            case .quickClean: "sparkles"
            case .trash: "trash"
            case .docker: "shippingbox.circle"
            case .oldCopy: "square.on.square.dashed"
            }
        }
    }

    struct Item: Codable, Sendable, Equatable {
        let path: String
        let bytes: Int64
        /// true: Çöp'e taşındı (geri alınabilir); false: doğrudan silindi.
        let trashed: Bool
        let category: ScanCategory?
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    /// Diskte hemen açılan alan (doğrudan silinenler, boşaltılan Çöp, Docker).
    let freedBytes: Int64
    /// Çöp'e taşınan; Çöp boşaltılınca açılır (o zaman ayrı bir "Çöp boşaltıldı" kaydı düşer).
    let trashedBytes: Int64
    /// Öğeler (en çok 300; dosya listesi kayıtta sınırsız büyümesin).
    let items: [Item]
    let itemCount: Int
}

enum CleanHistory {
    static let maxRecords = 200
    static let maxItemsPerRecord = 300

    static var fileURL: URL { ResultStore.directory.appending(path: "history.json") }

    static func load(from url: URL = fileURL) -> [CleanRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CleanRecord].self, from: data)) ?? []
    }

    /// Kaydı başa ekler, en eskileri atar ve diske yazar. Güncel listeyi döner.
    @discardableResult
    static func append(_ record: CleanRecord, to existing: [CleanRecord], at url: URL = fileURL) -> [CleanRecord] {
        let records = Array(([record] + existing).prefix(maxRecords))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(records) { try? data.write(to: url, options: .atomic) }
        return records
    }

    /// Bir temizlik raporundan kayıt üretir (boyut ve kategoriler taramadaki bulgulardan).
    static func record(from report: CleanReport, kind: CleanRecord.Kind, findings: [Finding], date: Date = Date()) -> CleanRecord {
        let byPath = Dictionary(findings.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let items = report.deleted.map { (path: $0, trashed: false) } + report.trashed.map { (path: $0, trashed: true) }
        return CleanRecord(
            date: date, kind: kind,
            freedBytes: report.deletedBytes, trashedBytes: report.trashedBytes,
            items: items.prefix(maxItemsPerRecord).map {
                CleanRecord.Item(path: $0.path, bytes: byPath[$0.path]?.bytes ?? 0,
                                 trashed: $0.trashed, category: byPath[$0.path]?.category)
            },
            itemCount: items.count
        )
    }

    /// Breathy'nin şimdiye kadar açtığı toplam alan. Çöp'e taşınanlar, Çöp boşaltılınca
    /// ayrı kayıtla sayıldığı için burada iki kez sayılmaz.
    static func totalFreed(_ records: [CleanRecord]) -> Int64 {
        records.reduce(0) { $0 + $1.freedBytes }
    }
}
