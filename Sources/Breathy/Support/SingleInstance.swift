import AppKit

/// Aynı anda tek Breathy. Açılışta başka bir Breathy çalışıyorsa hangisinin kalacağına karar verir.
///   - Güncelleme ya da izin sonrası yeniden başlatma (`--replace-running`): yeni açılan kalır, eskiler kapatılır.
///   - Klasörü silinmiş ya da daha eski sürümdeki kopya: kapatılır, yeni açılan kalır.
///   - Aynı ya da daha yeni sürüm zaten açıksa (ör. iki kez açıldı, açılışta başlatma + elle açma): yeni açılan çıkar.
enum SingleInstance {
    static let replaceFlag = "--replace-running"

    struct RunningCopy: Equatable, Sendable {
        let pid: pid_t
        /// Uygulamanın klasörü; silinmişse nil.
        let bundlePath: String?
        /// Klasördeki Info.plist'e göre sürüm; okunamazsa nil.
        let version: String?
        /// Süreç, diskteki uygulama dosyası yazılmadan önce başlamış: eski kodla çalışıyor
        /// (klasör güncellenmiş ama süreç kapanmamış).
        var startedBeforeCurrentBuild = false
    }

    enum Decision: Equatable {
        case keepRunning
        case terminate([pid_t])
        /// Aynı kopyanın başka bir süreci açık. Ya iki kez açıldı ya da eski sürümün güncelleyicisi bizi
        /// açıp kendisi kapanmak üzere (0.2.1 ve öncesi `--replace-running` göndermez). Biraz bekle:
        /// kapanırsa devam et, kapanmazsa çık. Eskileri her durumda kapat.
        case waitThenDecide(keepers: [pid_t], terminating: [pid_t])
        /// Başka yerde aynı ya da daha yeni sürüm açık: bu süreç çıkar, ama önce eskileri kapatır.
        case quitSelf(terminating: [pid_t])
    }

    /// Açılışta yapılacak iş.
    enum Action: Equatable {
        case run
        case quit(after: Duration)
        case waitFor([pid_t])
    }

    static func decide(myPath: String, myVersion: String, others: [RunningCopy], replacing: Bool) -> Decision {
        guard !others.isEmpty else { return .keepRunning }
        if replacing { return .terminate(others.map(\.pid)) }
        var stale: [pid_t] = []
        var samePath: [pid_t] = []
        var keeperElsewhere = false
        for other in others {
            guard let path = other.bundlePath, let version = other.version else {
                stale.append(other.pid)  // klasörü silinmiş: eski, kapatılmalı
                continue
            }
            if path == myPath {
                if other.startedBeforeCurrentBuild {
                    stale.append(other.pid)  // klasör güncellenmiş, süreç eski kodla kalmış
                } else {
                    samePath.append(other.pid)  // aynı kopya ikinci kez açılmış olabilir
                }
            } else if !Updater.isNewer(myVersion, than: version) {
                keeperElsewhere = true  // başka yerde aynı ya da daha yeni sürüm açık
            } else {
                stale.append(other.pid)  // başka yerdeki daha eski sürüm
            }
        }
        if keeperElsewhere { return .quitSelf(terminating: stale) }
        if !samePath.isEmpty { return .waitThenDecide(keepers: samePath, terminating: stale) }
        return stale.isEmpty ? .keepRunning : .terminate(stale)
    }

    /// Açılışta çağrılır ve ne yapılacağını söyler.
    @MainActor
    static func resolve() -> Action {
        let me = ProcessInfo.processInfo.processIdentifier
        let id = Bundle.main.bundleIdentifier ?? "com.breathy.app"
        let myPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        // Diskteki çalıştırılabilir dosyanın yazılma zamanı (paket açılırken korunur: derleme zamanı).
        let currentBuild = Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
            .map { app in
                let path = app.bundleURL.map { $0.resolvingSymlinksInPath().path }
                let exists = path.map { FileManager.default.fileExists(atPath: $0) } ?? false
                let olderCode = path == myPath && {
                    guard let launched = app.launchDate, let currentBuild else { return false }
                    return launched < currentBuild.addingTimeInterval(-1)
                }()
                return RunningCopy(pid: app.processIdentifier,
                                   bundlePath: exists ? path : nil,
                                   version: exists ? path.flatMap(version(atBundlePath:)) : nil,
                                   startedBeforeCurrentBuild: olderCode)
            }
        let decision = decide(
            myPath: myPath,
            myVersion: Updater.currentVersion,
            others: others,
            replacing: ProcessInfo.processInfo.arguments.contains(replaceFlag)
        )
        switch decision {
        case .keepRunning:
            return .run
        case .terminate(let pids):
            terminate(pids)
            return .run
        case .waitThenDecide(let keepers, let pids):
            terminate(pids)
            return .waitFor(keepers)
        case .quitSelf(let pids):
            terminate(pids)
            // Eskiler zorla kapatılabilsin diye biraz bekleyip çık.
            return .quit(after: pids.isEmpty ? .zero : .seconds(4))
        }
    }

    /// Verilen süreçlerin hepsi kapanana kadar (en çok `timeout`) bekler; kapandılarsa true.
    @MainActor
    static func waitUntilGone(_ pids: [pid_t], timeout: Duration = .seconds(3)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let alive = pids.contains { pid in
                guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
                return !app.isTerminated
            }
            if !alive { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    /// Bu süreç başka bir Breathy'nin yerini almak için mi açıldı?
    static var isReplacing: Bool {
        ProcessInfo.processInfo.arguments.contains(replaceFlag)
    }

    /// Önce kibarca "kapan" der; 3 saniyede kapanmazsa zorla kapatır.
    @MainActor
    static func terminate(_ pids: [pid_t]) {
        let apps = pids.compactMap { NSRunningApplication(processIdentifier: $0) }
        apps.forEach { _ = $0.terminate() }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            for app in apps where !app.isTerminated { _ = app.forceTerminate() }
        }
    }

    /// Info.plist'i doğrudan okur (Bundle önbelleği güncellenen klasörde eski değeri verebilir).
    static func version(atBundlePath path: String) -> String? {
        let plist = URL(fileURLWithPath: path).appending(path: "Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
}

/// Başka yerlerde duran eski Breathy kopyaları (ör. İndirilenler'de kalmış 0.2.0).
struct OldCopy: Identifiable, Equatable, Sendable {
    let path: String
    let version: String
    var id: String { path }
}

enum OldCopies {
    /// macOS'un bildiği bütün Breathy kopyaları içinden bu kopya dışındaki eski ya da aynı sürümdekiler.
    static func find() -> [OldCopy] {
        guard let id = Bundle.main.bundleIdentifier,
              let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL]
        else { return [] }
        return filter(urls.map { $0.resolvingSymlinksInPath().path },
                      current: Bundle.main.bundleURL.resolvingSymlinksInPath().path,
                      currentVersion: Updater.currentVersion,
                      version: SingleInstance.version(atBundlePath:),
                      isDevBuild: isDevBuild)
    }

    static func filter(_ paths: [String], current: String, currentVersion: String,
                       version: (String) -> String?, isDevBuild: (String) -> Bool) -> [OldCopy] {
        var seen: Set<String> = [current]
        var out: [OldCopy] = []
        for path in paths where seen.insert(path).inserted {
            // Çöp'tekiler ve geçici klasörler sayılmaz.
            if path.contains("/.Trash/") { continue }
            if ["/private/var/folders/", "/var/folders/", "/private/tmp/", "/tmp/"].contains(where: path.hasPrefix) { continue }
            guard let found = version(path) else { continue }  // artık yok
            if Updater.isNewer(found, than: currentVersion) { continue }  // daha yenisini "eski" deme
            if isDevBuild(path) { continue }
            out.append(OldCopy(path: path, version: found))
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Kaynak klasöründeki derleme çıktısı mı (geliştirici Mac'i)? Üst klasörlerden birinde Package.swift.
    static func isDevBuild(_ path: String) -> Bool {
        var dir = (path as NSString).deletingLastPathComponent
        for _ in 0..<3 {
            if FileManager.default.fileExists(atPath: dir + "/Package.swift") { return true }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return false
    }
}
