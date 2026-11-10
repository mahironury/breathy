import AppKit
import Observation

enum TrashState: Sendable, Equatable {
    case unknown
    case needsPermission
    case ready(TrashSummary)
}

/// Yer açılınca panelde gösterilen "+X GB açıldı" kutusu.
struct Celebration: Equatable, Identifiable, Sendable {
    let id = UUID()
    /// Gerçekten açılan alan (kalıcı silinenler). Çöp'e taşınanlar sayılmaz.
    let bytes: Int64
    let detail: String?
}

/// Uygulamanın tek durum kaynağı. Arka planda hiçbir şey taramaz;
/// sadece dakikada bir disk boş alanını ve takas boyutunu okur (iki sistem çağrısı).
@MainActor
@Observable
final class AppModel {
    private(set) var disk: DiskSnapshot?
    private(set) var swap: SwapInfo?
    private(set) var iCloud = ICloudStatus.read()
    private(set) var screenshotFolder = ScreenshotSettings.location()
    private(set) var trash: TrashState = .unknown
    private(set) var isEmptyingTrash = false
    /// Tarama sürerken dolu.
    private(set) var scanProgress: ScanProgress?
    private(set) var lastScan: ScanResult?
    /// Kısa süreli bilgi mesajı, örn. "✓ Mac'te 2,3 GB açıldı".
    private(set) var flash: String?
    /// Detaylar penceresindeki seçim (bulgu yolları). Taramadan sonra önerilenlerle dolar.
    var selection: Set<String> = []
    /// Detaylar penceresi açılınca gösterilecek kategori.
    var detailsCategory: ScanCategory?
    private(set) var cleanProgress: CleanProgress?
    private(set) var lastCleanReport: CleanReport?
    private(set) var celebration: Celebration?
    private(set) var loginItem: LoginItem.State = .unavailable
    /// "Bunu bir daha önerme" listesi.
    private(set) var ignored = IgnoreList.load()
    /// GitHub'da daha yeni bir sürüm varsa dolu.
    private(set) var update: ReleaseInfo?
    private(set) var isUpdating = false
    @ObservationIgnored private var isCheckingUpdate = false
    @ObservationIgnored private var nextUpdateCheck = (UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date)
        .map { $0.addingTimeInterval(86_400) } ?? .distantPast

    var isScanning: Bool { scanProgress != nil }
    var isCleaning: Bool { cleanProgress != nil }

    @ObservationIgnored private let trashService: TrashService
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTrashRefresh = Date.distantPast
    @ObservationIgnored private var keyWindowObserver: NSObjectProtocol?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var celebrationTask: Task<Void, Never>?
    @ObservationIgnored private var lowSpace: LowSpaceNotifier?
    @ObservationIgnored private var scanWork: Task<ScanResult, Error>?
    @ObservationIgnored private var cleanWork: Task<CleanReport, Never>?
    /// Önizleme modunda sonuçlar diske yazılmaz.
    @ObservationIgnored private var persistsResults = true

    init(trashService: TrashService = .user, loadStoredScan: Bool = true) {
        self.trashService = trashService
        if loadStoredScan, var stored = ResultStore.load() {
            ignored.apply(to: &stored)
            lastScan = stored
        }
        resetSelection()
        refreshDisk()
        refreshTrash(force: true)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDisk() }
        }
        timer.tolerance = 30  // sistem uyanmaları birleştirebilsin
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Menü paneli her açıldığında anahtar pencere olur → taze veri.
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelOpened() }
        }
    }

    /// Sadece gerçek uygulamada çağrılır (testlerde, rapor ve önizleme modlarında değil):
    /// açılışta başlatma ve 10 GB uyarısı.
    func startBackgroundServices() {
        LoginItem.configureOnFirstLaunch()
        loginItem = LoginItem.state
        let notifier = LowSpaceNotifier()
        notifier.onOpen = { [weak self] in self?.openDetails() }
        lowSpace = notifier
        if let disk { notifier.check(disk) }
    }

    func panelOpened() {
        refreshDisk()
        refreshTrash()
        iCloud = ICloudStatus.read()
        screenshotFolder = ScreenshotSettings.location()
        if lowSpace != nil { loginItem = LoginItem.state }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
        } catch {
            show("Açılışta başlatma değiştirilemedi. Sistem Ayarları → Genel → Oturum Açma Öğeleri'nden ayarlayabilirsin.")
        }
        loginItem = LoginItem.state
    }

    /// Ekran görüntüleri iCloud'a eşitlenen bir klasöre (Masaüstü/Belgeler) mi kaydediliyor?
    var screenshotsGoToICloud: Bool {
        guard iCloud.desktopDocumentsEnabled else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = screenshotFolder.path
        return ["Desktop", "Documents"].contains { path == "\(home)/\($0)" || path.hasPrefix("\(home)/\($0)/") }
    }

    /// Kullanıcı düğmeye basınca: ekran görüntülerini iCloud dışındaki ~/Pictures/Ekran Görüntüleri'ne kaydet.
    func moveScreenshotsOutOfICloud() {
        let target = ScreenshotSettings.suggestedFolder()
        do {
            try ScreenshotSettings.setLocation(target)
            screenshotFolder = ScreenshotSettings.location()
            show("✓ Yeni ekran görüntüleri Resimler/Ekran Görüntüleri'ne kaydedilecek.")
        } catch {
            show("Konum değiştirilemedi. ⌘⇧5 → Seçenekler'den değiştirebilirsin.")
        }
    }

    func refreshDisk() {
        disk = DiskStatus.read()
        swap = SwapInfo.read()
        if let disk { lowSpace?.check(disk) }
        if lowSpace != nil { checkForUpdatesIfDue() }  // sadece gerçek uygulamada; günde bir istek
    }

    // MARK: - Çöp

    /// Çöp'ü arka planda ölçer. Panel art arda açılırsa 5 sn içinde tekrar ölçmez.
    func refreshTrash(force: Bool = false) {
        guard !isEmptyingTrash else { return }
        guard force || Date().timeIntervalSince(lastTrashRefresh) > 5 else { return }
        lastTrashRefresh = Date()

        let service = trashService
        Task {
            let state = await Task.detached(priority: .utility) { () -> TrashState in
                do { return .ready(try service.summary()) } catch { return .needsPermission }
            }.value
            self.trash = state
        }
    }

    func emptyTrash() {
        guard case .ready(let summary) = trash, !summary.isEmpty, !isEmptyingTrash else { return }
        isEmptyingTrash = true

        let service = trashService
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> TrashEmptyResult? in
                try? service.empty()
            }.value
            isEmptyingTrash = false

            if let result {
                var details: [String] = []
                if result.freedICloudBytes > 0 {
                    details.append("iCloud çöpünden \(ByteFormat.string(result.freedICloudBytes)) silindi")
                }
                if result.failed > 0 {
                    details.append("\(result.failed) öğe silinemedi")
                }
                if result.freedDiskBytes > 0 {
                    celebrate(result.freedDiskBytes, detail: details.isEmpty ? "Çöp boşaltıldı" : details.joined(separator: " · "))
                } else {
                    show((["✓ Çöp boşaltıldı"] + details).joined(separator: " · "))
                }
            } else {
                trash = .needsPermission
            }

            refreshTrash(force: true)
            refreshDisk()
            // APFS boş alanı birkaç saniye gecikmeli günceller.
            try? await Task.sleep(for: .seconds(3))
            refreshDisk()
        }
    }

    // MARK: - Tarama

    /// Taramayı en düşük öncelikte başlatır. Tam Disk Erişimi yoksa başlamaz
    /// (yoksa macOS her klasör için ayrı izin penceresi açardı).
    func startScan() {
        guard scanWork == nil else { return }
        guard case .ready = trash else {
            show("Taramadan önce Tam Disk Erişimi iznini ver.")
            return
        }

        let scanner = Scanner(env: .live())
        scanProgress = ScanProgress()
        let sink: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.scanWork != nil else { return }
                self.scanProgress = progress
            }
        }
        let work = Task.detached(priority: .background) { try scanner.run(report: sink) }
        scanWork = work

        Task {
            let outcome = await work.result
            scanWork = nil
            scanProgress = nil
            switch outcome {
            case .success(var result):
                result.compareGrowth(with: lastScan)
                ignored.apply(to: &result)
                lastScan = result
                lastCleanReport = nil
                resetSelection()
                if persistsResults { ResultStore.save(result) }
                show("✓ Tarama bitti: \(ByteFormat.string(result.cleanableBytes)) temizlenebilir")
            case .failure(let error) where error is CancellationError:
                show("Tarama iptal edildi.")
            case .failure:
                show("Tarama tamamlanamadı.")
            }
        }
    }

    func cancelScan() {
        scanWork?.cancel()
    }

    /// Geliştirme önizlemesi: verilen sonucu gösterir, diske yazmaz.
    func loadForPreview(_ result: ScanResult) {
        persistsResults = false
        lastScan = result
        resetSelection()
    }

    private func show(_ message: String) {
        flash = message
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { flash = nil }
        }
    }

    // MARK: - Güncelleme

    /// Günde bir kez (başarısız olursa saatte bir) GitHub'daki son sürüme bakar.
    func checkForUpdatesIfDue() {
        guard Updater.repo != nil, Date() >= nextUpdateCheck else { return }
        checkForUpdates(manual: false)
    }

    func checkForUpdates(manual: Bool) {
        guard Updater.repo != nil else {
            if manual { show("Güncelleme kaynağı ayarlı değil.") }
            return
        }
        guard !isCheckingUpdate, !isUpdating else { return }
        isCheckingUpdate = true
        nextUpdateCheck = Date().addingTimeInterval(3_600)
        Task {
            defer { isCheckingUpdate = false }
            do {
                let release = try await Updater.latestRelease()
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                nextUpdateCheck = Date().addingTimeInterval(86_400)
                if Updater.isNewer(release.version, than: Updater.currentVersion) {
                    update = release
                } else {
                    update = nil
                    if manual { show("✓ Breathy güncel (\(Updater.currentVersion))") }
                }
            } catch {
                if manual { show("Güncelleme denetlenemedi. İnternet bağlantını kontrol et.") }
            }
        }
    }

    /// Geliştirme önizlemesi: güncelleme satırını göstermek için.
    func showUpdateForPreview(_ release: ReleaseInfo) {
        update = release
    }

    /// İndirir, imzayı doğrular, yerine koyar ve yeniden başlatır.
    func installUpdate() {
        guard let release = update, !isUpdating else { return }
        isUpdating = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try await Updater.install(release) }.value
                SystemLinks.relaunch()
            } catch {
                isUpdating = false
                let reason = (error as? LocalizedError)?.errorDescription ?? "beklenmeyen bir hata"
                show("Güncellenemedi: \(reason). Sürüm sayfası açılıyor.")
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    // MARK: - Bir daha önerme

    func ignore(_ finding: Finding) {
        ignored.add(finding.path)
        ignored.save()
        guard var scan = lastScan else { return }
        ignored.apply(to: &scan)
        lastScan = scan
        selection = selection.filter { path in scan.findings.contains { $0.path == path } }
        if persistsResults { ResultStore.save(scan) }
        show("Gizlendi. Detaylar'daki \"Önerilmeyenler\" listesinden geri alabilirsin.")
    }

    /// Listeden çıkarır; öğe bir sonraki taramada yeniden görünür.
    func unignore(_ path: String) {
        ignored.remove(path)
        ignored.save()
    }

    /// "+X GB açıldı" kutusunu 8 sn gösterir.
    func celebrate(_ bytes: Int64, detail: String?) {
        flash = nil
        celebration = Celebration(bytes: bytes, detail: detail)
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { celebration = nil }
        }
    }
}

// MARK: - Seçim ve temizlik

extension AppModel {
    /// Açık bir uygulamaya ait olmayan, bilgi olmayan bulgular seçilebilir.
    nonisolated static func isSelectable(_ finding: Finding) -> Bool {
        finding.risk != .info && finding.inUseBy == nil
    }

    func findings(in category: ScanCategory) -> [Finding] {
        lastScan?.findings.filter { $0.category == category } ?? []
    }

    func isSelected(_ finding: Finding) -> Bool {
        selection.contains(finding.path)
    }

    func toggle(_ finding: Finding) {
        guard Self.isSelectable(finding) else { return }
        if selection.contains(finding.path) { selection.remove(finding.path) } else { selection.insert(finding.path) }
    }

    func setSelection(_ on: Bool, in category: ScanCategory) {
        let paths = findings(in: category).filter(Self.isSelectable).map(\.path)
        if on { selection.formUnion(paths) } else { selection.subtract(paths) }
    }

    /// Taramanın önerdiklerini seç (otomatik işaretleme).
    func resetSelection() {
        selection = Set(lastScan?.findings.filter(\.countsAsCleanable).map(\.path) ?? [])
    }

    var selectedFindings: [Finding] {
        lastScan?.findings.filter { selection.contains($0.path) && Self.isSelectable($0) } ?? []
    }

    func selectedBytes(in category: ScanCategory? = nil) -> Int64 {
        selectedFindings
            .filter { category == nil || $0.category == category }
            .reduce(0) { $0 + $1.bytes }
    }

    func openDetails(_ category: ScanCategory? = nil) {
        if let category { detailsCategory = category }
        DetailsWindowController.shared.show(model: self)
    }

    func dismissCleanReport() {
        lastCleanReport = nil
    }

    /// Panelden tek tıkla temizlenebilenler: sadece kendiliğinden yeniden oluşanlar (🟢),
    /// önerilmiş ve açık bir uygulamaya ait olmayanlar. Kişisel dosyalar bu listeye hiç girmez.
    var safeCleanable: [Finding] {
        lastScan?.findings.filter { $0.risk == .safe && $0.countsAsCleanable } ?? []
    }

    func cleanSafe() {
        clean(safeCleanable)
    }

    /// Seçilenleri türüne göre temizler (🟢 sil, 🟡 Çöp'e taşı). Arka planda, iptal edilebilir.
    func cleanSelected() {
        clean(selectedFindings)
    }

    private func clean(_ selected: [Finding]) {
        guard cleanWork == nil, !isScanning, let scan = lastScan, !selected.isEmpty else { return }

        let cleaner = Cleaner(
            home: FileManager.default.homeDirectoryForCurrentUser,
            appDirs: [URL(fileURLWithPath: "/Applications"),
                      FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")],
            runningApps: RunningApps.snapshot()
        )
        cleanProgress = CleanProgress(total: selected.count)
        lastCleanReport = nil

        let sink: @Sendable (CleanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.cleanWork != nil else { return }
                self.cleanProgress = progress
            }
        }
        let all = scan.findings
        let work = Task.detached(priority: .utility) {
            cleaner.clean(selected, allFindings: all, progress: sink)
        }
        cleanWork = work

        Task {
            var report = await work.value
            if !report.needsAuthorization.isEmpty {
                report = await trashWithAuthorization(report)
            }
            cleanWork = nil
            cleanProgress = nil
            lastCleanReport = report
            removeCleaned(report.cleanedPaths)

            let trashedNote = report.trashedBytes > 0
                ? "\(ByteFormat.string(report.trashedBytes)) Çöp'e taşındı, Çöp boşaltılınca o da açılır"
                : nil
            if report.deletedBytes > 0 {
                celebrate(report.deletedBytes, detail: trashedNote ?? "Temizlik bitti")
            } else if let trashedNote {
                show("✓ " + trashedNote)
            }

            refreshTrash(force: true)
            refreshDisk()
            try? await Task.sleep(for: .seconds(3))  // APFS boş alanı gecikmeli günceller
            refreshDisk()
        }
    }

    func cancelCleaning() {
        cleanWork?.cancel()
    }

    /// Yönetici izni gerekenleri (ör. /Applications'taki uygulamalar) Finder üzerinden Çöp'e taşır;
    /// macOS şifre sorar, kullanıcı onaylarsa taşınır.
    private func trashWithAuthorization(_ report: CleanReport) async -> CleanReport {
        var report = report
        let urls = report.needsAuthorization.map { URL(fileURLWithPath: $0) }
        let moved: Set<String> = await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { @Sendable result, _ in  // herhangi bir kuyrukta çağrılabilir
                continuation.resume(returning: Set(result.keys.map(\.path)))
            }
        }
        let sizes = Dictionary(uniqueKeysWithValues: (lastScan?.findings ?? []).map { ($0.path, $0.bytes) })
        for path in report.needsAuthorization {
            if moved.contains(path) {
                report.trashed.append(path)
                report.trashedBytes += sizes[path] ?? 0
            } else {
                report.failed.append(CleanIssue(path: path, reason: "Yönetici izni verilmedi"))
            }
        }
        report.needsAuthorization = []
        return report
    }

    /// Temizlenenleri sonuçtan çıkarır; tek kopyası kalan çift grupları da listeden düşer.
    private func removeCleaned(_ paths: Set<String>) {
        guard var scan = lastScan, !paths.isEmpty else { return }
        scan.removeFindings { paths.contains($0.path) }
        lastScan = scan
        selection.subtract(paths)
        if persistsResults { ResultStore.save(scan) }
    }
}
