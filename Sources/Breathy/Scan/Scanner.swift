import Foundation

/// Tarama eşikleri. Testlerde küçültülür.
struct ScanLimits: Sendable {
    /// Bundan küçük önbellek/artık klasörleri listelenmez.
    var minItemBytes: Int64 = 1_000_000
    var largeFileBytes: Int64 = 500_000_000
    /// "Büyük uygulama verileri" bilgisi için eşik.
    var appDataBytes: Int64 = 1_000_000_000
    /// Bu kadar gündür dokunulmamış proje "eski" sayılır.
    var staleProjectDays: Double = 90
    /// Bu kadar gündür açılmamış dosya/uygulama "kullanılmıyor" sayılır.
    var unusedDays: Double = 180
    /// İndirilenler'deki kurulum dosyası bu kadar günden eskiyse aday olur.
    var installerDays: Double = 30
    /// Bu kadar günden eski ekran görüntüleri temizlik için işaretlenir.
    var screenshotDays: Double = 30
    /// Çift dosya aramasına girecek en küçük dosya.
    var duplicateMinBytes: Int64 = 1_000_000
    /// "Ne büyüdü?" karşılaştırması için saklanan en küçük klasör (kayıt dosyası küçük kalsın).
    var folderSizeMinBytes: Int64 = 50_000_000
    /// Uygulama bu kadar gün içinde önbelleğine yazdıysa önbellek "kullanılıyor" sayılır ve otomatik
    /// işaretlenmez: silinirse hemen yeniden oluşur, yer kısa sürede yine dolar.
    var cacheFreshDays: Double = 14
}

/// Taramanın dış dünyaya bağımlılıkları (testlerde sahteleri verilir).
struct ScanEnvironment: Sendable {
    var home: URL
    /// Kullanılmayan uygulamalar için taranan klasörler.
    var applicationDirs: [URL]
    /// Sadece "kurulu mu?" sorusu için bakılan sistem klasörleri.
    var systemApplicationDirs: [URL]
    var now: Date
    /// Açık uygulamalar: küçük harfli bundle ID → görünen ad.
    var runningApps: [String: String]
    var ownBundleID: String
    /// LaunchServices bu bundle ID'yi tanıyor mu (uygulama başka bir yerde kurulu olabilir)?
    var isRegistered: @Sendable (String) -> Bool
    var lastUsed: @Sendable (URL) -> Date?
    var dateAdded: @Sendable (URL) -> Date?
    var iCloudStatus: ICloudStatus
    /// macOS'un ekran görüntülerini kaydettiği klasör.
    var screenshotFolder: URL
    /// Kullanıcının seçtiği kullanım alanları; seçilmeyenlerin kuralları atlanır.
    var areas: Set<UsageArea> = Set(UsageArea.allCases)
}

/// Tek seferlik disk taraması. Senkron çalışır; `Task.detached(priority: .background)` içinde çağrılır,
/// böylece M4'ün verimlilik çekirdeklerinde ve düşük disk önceliğiyle yürür. İptal edilebilir.
struct Scanner: Sendable {
    let env: ScanEnvironment
    var limits = ScanLimits()

    func run(report: @escaping @Sendable (ScanProgress) -> Void) throws -> ScanResult {
        let started = Date()
        let ctx = ScanContext(report: report)
        var findings: [Finding] = []

        try ctx.phase("Önbellekler ve loglar")
        findings += try knownLocations(ctx)

        try ctx.phase("Uygulama verileri")
        findings += try libraryAppData(ctx)

        try ctx.phase("Geliştirici araçları ve oyunlar")
        findings += try knownAppData(ctx)

        try ctx.phase("Uygulamalar")
        findings += try unusedApps(ctx)

        try ctx.phase("Ev klasörü taranıyor")
        let walk = try walkHome(ctx)
        findings += walk.findings
        findings += hiddenFolders(ctx)

        try ctx.phase("Çift dosyalar aranıyor")
        let duplicates = try duplicateFindings(walk.duplicateCandidates, ctx)
        // Çifti bulunan büyük dosya "çift" olarak gösterilir, iki kez sayılmaz.
        let duplicatePaths = Set(duplicates.map(\.path))
        findings.removeAll { $0.category == .largeFiles && duplicatePaths.contains($0.path) }
        findings += duplicates

        try ctx.phase("iCloud")
        let (iCloud, archives) = try iCloudSummary(
            screenshots: findings.filter { $0.category == .screenCaptures }, ctx
        )
        findings += archives

        ctx.finish()
        findings.sort { $0.bytes > $1.bytes }
        return ScanResult(
            date: started,
            duration: Date().timeIntervalSince(started),
            filesVisited: ctx.progress.filesVisited,
            findings: findings,
            iCloud: iCloud,
            folderSizes: ctx.folderSizes.filter { $0.value >= limits.folderSizeMinBytes }
        )
    }

    // MARK: - Ortak yardımcılar

    static let sizeKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]
    private static let sizeKeySet = Set(sizeKeys)

    /// Diskte kapladığı gerçek alan; klasörse içindekilerin toplamı. Sembolik bağlantılar izlenmez.
    func measure(_ url: URL, _ ctx: ScanContext) throws -> Int64 {
        guard let v = try? url.resourceValues(forKeys: Self.sizeKeySet), v.isSymbolicLink != true else { return 0 }
        guard v.isDirectory == true else { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }

        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Self.sizeKeys, options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let child = e.nextObject() as? URL {
            try ctx.visit(child)
            guard let cv = try? child.resourceValues(forKeys: Self.sizeKeySet),
                  cv.isDirectory != true, cv.isSymbolicLink != true else { continue }
            total += Int64(cv.totalFileAllocatedSize ?? cv.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Boyut ve içindeki en yeni dosyanın tarihi (önbellek gerçekten kullanılıyor mu?).
    func measureWithNewest(_ url: URL, _ ctx: ScanContext) throws -> (bytes: Int64, newest: Date?) {
        let keys: [URLResourceKey] = Self.sizeKeys + [.contentModificationDateKey]
        let keySet = Set(keys)
        guard let v = try? url.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { return (0, nil) }
        guard v.isDirectory == true else {
            return (Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0), v.contentModificationDate)
        }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return (0, nil) }
        var total: Int64 = 0
        var newest: Date?
        while let child = e.nextObject() as? URL {
            try ctx.visit(child)
            guard let cv = try? child.resourceValues(forKeys: keySet),
                  cv.isDirectory != true, cv.isSymbolicLink != true else { continue }
            total += Int64(cv.totalFileAllocatedSize ?? cv.fileAllocatedSize ?? 0)
            if let date = cv.contentModificationDate, date > (newest ?? .distantPast) { newest = date }
        }
        return (total, newest)
    }

    /// Mantıksal boyut (iCloud'da kapladığı) ve Mac'te ayrılan alan birlikte.
    func measureBoth(_ url: URL, _ ctx: ScanContext) throws -> (logical: Int64, local: Int64) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileSizeKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let keySet = Set(keys)
        func sizes(_ v: URLResourceValues) -> (Int64, Int64) {
            (Int64(v.totalFileSize ?? v.fileSize ?? 0), Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0))
        }
        guard let v = try? url.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { return (0, 0) }
        guard v.isDirectory == true else { return sizes(v) }
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return (0, 0) }
        var logical: Int64 = 0
        var local: Int64 = 0
        while let child = e.nextObject() as? URL {
            try ctx.visit(child)
            guard let cv = try? child.resourceValues(forKeys: keySet),
                  cv.isDirectory != true, cv.isSymbolicLink != true else { continue }
            let (l, a) = sizes(cv)
            logical += l
            local += a
        }
        return (logical, local)
    }

    /// Bulgu oluşturur. Silinebilir bir kategori PathGuard'dan geçmezse bulgu üretilmez.
    func makeFinding(
        _ url: URL, _ category: ScanCategory, _ risk: Risk, bytes: Int64,
        suggested: Bool = true, lastUsed: Date? = nil, note: String? = nil, inUseBy: String? = nil,
        groupID: String? = nil, areas: Set<UsageArea>? = nil, ctx: ScanContext
    ) -> Finding? {
        // Kullanıcının seçmediği alanların bulguları üretilmez (kuralların çoğu zaten ölçmeden atlar).
        if let required = areas ?? category.area.map({ [$0] }), required.isDisjoint(with: env.areas) { return nil }
        if risk != .info, !PathGuard.canDelete(url, home: env.home, appDirs: env.applicationDirs) { return nil }
        let finding = Finding(
            path: url.path, category: category, risk: risk, bytes: bytes,
            lastUsed: lastUsed, suggested: suggested && risk != .info, note: note, inUseBy: inUseBy,
            groupID: groupID
        )
        if finding.countsAsCleanable { ctx.found(bytes) }
        return finding
    }

    func daysSince(_ date: Date) -> Double {
        env.now.timeIntervalSince(date) / 86_400
    }

    /// Ham yol (standardize edilmez): FileManager'ın tarama sırasında verdiği yollarla birebir
    /// karşılaştırılabilsin. `standardizedFileURL` "/private/var" gibi önekleri kısaltır.
    func homePath(_ relative: String) -> String {
        env.home.appending(path: relative).path
    }
}

/// Taramanın değişken durumu: sayaçlar, ilerleme bildirimi, iptal kontrolü.
/// Sadece tarama iş parçacığında kullanılır.
final class ScanContext {
    private let report: @Sendable (ScanProgress) -> Void
    private(set) var progress = ScanProgress()
    private var lastReport = Date.distantPast

    init(report: @escaping @Sendable (ScanProgress) -> Void) {
        self.report = report
    }

    func phase(_ name: String) throws {
        try checkCancel()
        progress.phase = name
        send()
    }

    func setFolder(_ url: URL) {
        progress.currentFolder = url.lastPathComponent
    }

    func found(_ bytes: Int64) {
        progress.foundBytes += bytes
    }

    /// Klasör boyutları: ev klasörüne göre yol → bayt ("ne büyüdü?" için).
    private(set) var folderSizes: [String: Int64] = [:]

    func addSize(_ key: String, _ bytes: Int64) {
        folderSizes[key, default: 0] += bytes
    }

    /// Gizli klasörlerde (ev klasörüne göre "." ile başlayan yollar) en son değişen dosyanın tarihi.
    private(set) var latestChange: [String: Date] = [:]

    func noteChange(_ key: String, _ date: Date) {
        if let current = latestChange[key], current >= date { return }
        latestChange[key] = date
    }

    /// Her dosyada çağrılır; 512 dosyada bir iptal ve ilerleme kontrolü yapar.
    func visit(_ url: URL) throws {
        progress.filesVisited += 1
        if progress.filesVisited % 512 == 0 { try checkpoint(url) }
    }

    func checkpoint(_ url: URL?) throws {
        try checkCancel()
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.25 else { return }
        if let url { progress.currentFolder = url.deletingLastPathComponent().lastPathComponent }
        send(now)
    }

    func finish() { send() }

    private func checkCancel() throws {
        if Task.isCancelled { throw CancellationError() }
    }

    private func send(_ now: Date = Date()) {
        lastReport = now
        report(progress)
    }
}
