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
    }

    enum Decision: Equatable {
        case keepRunning
        case terminate([pid_t])
        /// Başka bir Breathy kalıyor; bu süreç çıkar, ama önce eskileri kapatır.
        case quitSelf(terminating: [pid_t])
    }

    static func decide(myPath: String, myVersion: String, others: [RunningCopy], replacing: Bool) -> Decision {
        guard !others.isEmpty else { return .keepRunning }
        if replacing { return .terminate(others.map(\.pid)) }
        var stale: [pid_t] = []
        var keeperExists = false
        for other in others {
            guard let path = other.bundlePath, let version = other.version else {
                stale.append(other.pid)  // klasörü silinmiş: eski, kapatılmalı
                continue
            }
            if path == myPath || !Updater.isNewer(myVersion, than: version) {
                keeperExists = true  // aynı kopya ya da aynı/daha yeni sürüm zaten açık
            } else {
                stale.append(other.pid)  // başka yerdeki daha eski sürüm
            }
        }
        if keeperExists { return .quitSelf(terminating: stale) }
        return stale.isEmpty ? .keepRunning : .terminate(stale)
    }

    /// Açılışta çağrılır. Dönen süre doluysa bu süreç o kadar bekleyip kapanmalı (başka bir Breathy
    /// kalıyor; bekleme, kapatılan eskiler zorla kapatılabilsin diye).
    @MainActor
    static func resolve() -> Duration? {
        let me = ProcessInfo.processInfo.processIdentifier
        let id = Bundle.main.bundleIdentifier ?? "com.breathy.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me && !$0.isTerminated }
            .map { app in
                let path = app.bundleURL.map { $0.resolvingSymlinksInPath().path }
                let exists = path.map { FileManager.default.fileExists(atPath: $0) } ?? false
                return RunningCopy(pid: app.processIdentifier,
                                   bundlePath: exists ? path : nil,
                                   version: exists ? path.flatMap(version(atBundlePath:)) : nil)
            }
        let decision = decide(
            myPath: Bundle.main.bundleURL.resolvingSymlinksInPath().path,
            myVersion: Updater.currentVersion,
            others: others,
            replacing: ProcessInfo.processInfo.arguments.contains(replaceFlag)
        )
        switch decision {
        case .keepRunning:
            return nil
        case .terminate(let pids):
            terminate(pids)
            return nil
        case .quitSelf(let pids):
            terminate(pids)
            return pids.isEmpty ? .zero : .seconds(4)
        }
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
