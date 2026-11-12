// Geliştirici araçları: sadece `./build.sh --dev-tools` derlemesinde bulunur.
// Yayın sürümünde yoktur; aksi hâlde Tam Disk Erişimi olan Breathy'yi başka bir program
// bu modlarla başlatıp korunan klasörlerin dökümünü alabilirdi.
#if BREATHY_DEV_TOOLS
import AppKit

/// "Sadece raporla" modu (geliştirme ve doğrulama için). Hiçbir şey silmez.
///   open -n -W Breathy.app --args --report <çıktı.json>
/// Menü çubuğunda simge göstermeden tam tarama yapar, sonucu verilen dosyaya (ve panelde görünsün
/// diye ResultStore'a) yazar, sonra çıkar. `open` ile başlatıldığı için Breathy'nin kendi
/// Tam Disk Erişimi izniyle çalışır.
@MainActor
enum HeadlessReport {
    static var outputPath: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--report"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(into url: URL) {
        Task { @MainActor in
            defer { NSApp.terminate(nil) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            guard (try? TrashService.user.summary()) != nil else {
                try? Data(#"{"error":"noPermission"}"#.utf8).write(to: url)
                return
            }
            let scanner = Scanner(env: .live())
            do {
                var result = try await Task.detached(priority: .background) {
                    try scanner.run(report: { _ in })
                }.value
                result.compareGrowth(with: ResultStore.load())
                IgnoreList.load().apply(to: &result)
                ResultStore.save(result)
                try encoder.encode(result).write(to: url)
            } catch {
                try? Data(#"{"error":"\#(error.localizedDescription)"}"#.utf8).write(to: url)
            }
        }
    }
}

/// Güncelleme paketinin imza denetimini kurmadan dener (geliştirme ve doğrulama için):
///   open -n -W Breathy.app --args --verify-update <paket.zip> <çıktı.json>
/// Paketi geçici bir klasöre açar, içindeki Breathy.app'in bu kopyayla aynı sertifikayla
/// imzalı olup olmadığını yazar. Hiçbir şeyi değiştirmez.
@MainActor
enum VerifyUpdateTool {
    static var arguments: (zip: URL, output: URL)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--verify-update"), i + 2 < args.count else { return nil }
        return (URL(fileURLWithPath: args[i + 1]), URL(fileURLWithPath: args[i + 2]))
    }

    static func run(zip: URL, output: URL) {
        Task { @MainActor in
            defer { NSApp.terminate(nil) }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appending(path: "breathy-verify-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? fm.removeItem(at: work) }
            var report: [String: String] = ["current": Updater.currentVersion]
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                let app = try Updater.prepare(zip: zip, in: work, requireNewerThan: nil)
                report["ok"] = "true"
                report["version"] = Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            } catch {
                report["ok"] = "false"
                report["error"] = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: output)
        }
    }
}

/// Geliştirici modlarından biri istendiyse başlatır ve true döner.
/// Arayüz duman testi: uygulama normal açılır (menü çubuğu, tek Breathy kuralı, servisler), sonra
/// Detaylar ve kullanım alanı pencereleri açılır ve 5 sn boyunca boşta ne kadar işlemci yakıldığı ölçülür.
/// Menü çubuğuna tıklayamayan otomasyon için: 0.2.2'deki sahne döngüsü pencere öne gelince başlıyordu.
///   open -n Breathy.app --args --ui-smoke <çıktı.json>
@MainActor
enum UISmokeTest {
    static var outputPath: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--ui-smoke"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_000_000 : -1
    }

    /// Küçük ekranı taklit eden yükseklik: panel buna sığmalı, orta bölüm kaydırılmalı.
    static let smallScreenHeight: CGFloat = 520

    @MainActor final class MenuBox { var menu: NSMenu? }

    /// Simgeye sağ tıklanmış gibi bir olay gönderir, açılan menünün başlıklarını okur ve menüyü kapatır.
    static func rightClickMenuTitles() async -> [String] {
        guard let window = NSApp.windows.first(where: StatusItemMenu.isStatusItemWindow),
              let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: NSPoint(x: window.frame.width / 2, y: window.frame.height / 2),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return [] }
        let box = MenuBox()
        let observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { note in
            nonisolated(unsafe) let menu = note.object as? NSMenu  // bildirim ana kuyrukta gelir
            MainActor.assumeIsolated { box.menu = menu }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        NSApp.postEvent(event, atStart: false)
        for _ in 0..<30 where box.menu == nil { try? await Task.sleep(for: .milliseconds(100)) }
        let titles = box.menu?.items.map(\.title) ?? []
        box.menu?.cancelTracking()
        try? await Task.sleep(for: .milliseconds(300))
        return titles
    }

    static func schedule(model: AppModel, out: URL) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            MenuPanel.previewScreenHeight = smallScreenHeight  // kaydırılan panel yolunu da dener
            let button = StatusItemMenu.statusButton()
            button?.performClick(nil)  // menü çubuğu panelini aç (kullanıcının tıklaması gibi)
            try? await Task.sleep(for: .seconds(1))
            let panel = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }
            let cpu0 = cpuSeconds(), mem0 = residentMB(), t0 = Date()
            try? await Task.sleep(for: .seconds(5))
            let cpu = cpuSeconds() - cpu0
            let titles = await rightClickMenuTitles()
            let report: [String: Double] = [
                "panelOpened": button == nil ? 0 : 1,
                "idleCPUSeconds": cpu,
                "wallSeconds": Date().timeIntervalSince(t0),
                "memoryStartMB": mem0,
                "memoryEndMB": residentMB(),
                "panelHeight": Double(panel?.frame.height ?? -1),
                "screenLimit": Double(smallScreenHeight),
                "contextMenuItems": Double(titles.count),
                "contextMenuQuit": titles.contains("Breathy'den çık") ? 1 : 0,
            ]
            let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: out)
            NSApp.terminate(nil)
        }
    }
}

@MainActor
enum DevTools {
    static func run(model: AppModel) -> Bool {
        // Duman testi uygulamayı normal açar (false döner), sadece ölçümü zamanlar.
        if let out = UISmokeTest.outputPath {
            UISmokeTest.schedule(model: model, out: out)
            return false
        }
        if let out = HeadlessReport.outputPath {
            HeadlessReport.run(into: out)
            return true
        }
        if let check = VerifyUpdateTool.arguments {
            VerifyUpdateTool.run(zip: check.zip, output: check.output)
            return true
        }
        if let out = DebugSnapshot.outputDirectory {
            DebugSnapshot.run(model: model, into: out)
            return true
        }
        return false
    }
}
#endif
