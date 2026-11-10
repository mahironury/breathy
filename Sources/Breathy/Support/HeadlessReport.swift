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
@MainActor
enum DevTools {
    static func run(model: AppModel) -> Bool {
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
