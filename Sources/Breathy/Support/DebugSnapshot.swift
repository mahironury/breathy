// Geliştirici araçları: sadece `./build.sh --dev-tools` derlemesinde bulunur.
// Yayın sürümünde yoktur; aksi hâlde Tam Disk Erişimi olan Breathy'yi başka bir program
// bu modlarla başlatıp korunan klasörlerin dökümünü alabilirdi.
#if BREATHY_DEV_TOOLS
import AppKit
import SwiftUI

/// Geliştirme aracı. Normal kullanımda hiç çalışmaz.
///   Breathy --snapshot <klasör> --scan <sonuç.json>
/// Verilen örnek sonucu yükler (diske yazmaz), paneli ve Detaylar penceresini gerçek AppKit
/// çizimiyle PNG'ye kaydeder ve çıkar. Ekran kaydı izni gerekmez: sadece kendi görünümlerini çizer.
@MainActor
enum DebugSnapshot {
    static var outputDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(model: AppModel, into out: URL) {
        let args = ProcessInfo.processInfo.arguments
        if let j = args.firstIndex(of: "--scan"), j + 1 < args.count,
           let data = try? Data(contentsOf: URL(fileURLWithPath: args[j + 1])),
           var scan = try? JSONDecoder().decode(ScanResult.self, from: data) {
            var demoHistory: [CleanRecord] = []
            if args.contains("--demo") {  // yeni panel parçalarını görmek için örnek veri
                model.showAreasForPreview([.development, .aiCoding, .media])
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                let gb: Int64 = 1_000_000_000
                scan.folderSizes = [
                    "Library/Group Containers/group.net.whatsapp.WhatsApp.shared": 45 * gb,
                    "Library/Application Support/Claude": 12 * gb,
                    "Library/Application Support/Google": 2_400_000_000,
                    "Library/Caches": 6 * gb, "Library/Logs": 400_000_000,
                    "Library/Developer/Xcode/DerivedData": 4 * gb,
                ]
                scan.findings.append(Finding(path: home + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                                             category: .docker, risk: .info, bytes: 3_060_000_000, suggested: false,
                                             note: "Docker'ın disk görüntüsü — yukarıdaki karttan kullanılmayan imajları temizleyebilirsin"))
                var shot = Finding(path: home + "/Desktop/Ekran Resmi 2026-03-02 21.14.08.png", category: .screenCaptures,
                                   risk: .review, bytes: 2_400_000, suggested: false)
                shot.markCritical(CriticalData.Kind.cryptoContent.reason)
                var leftover = Finding(path: home + "/Library/Application Support/com.ledger.live", category: .appLeftovers,
                                       risk: .review, bytes: 310_000_000, suggested: false, note: "Kurulu bir uygulamaya ait görünmüyor")
                leftover.markCritical(CriticalData.Kind.cryptoWallet.reason)
                scan.findings += [shot, leftover]
                let day: TimeInterval = 86_400
                for record in [
                    CleanRecord(date: Date().addingTimeInterval(-9 * day), kind: .selection, freedBytes: 14_400_000_000,
                                trashedBytes: 120_000_000,
                                items: [.init(path: home + "/Library/Caches/com.spotify.client", bytes: 1_400_000_000, trashed: false, category: .caches),
                                        .init(path: home + "/Projeler/eski-site/node_modules", bytes: 1_000_000_000, trashed: false, category: .nodeModules),
                                        .init(path: home + "/Downloads/Kurulum.dmg", bytes: 120_000_000, trashed: true, category: .oldInstallers)],
                                itemCount: 3),
                    CleanRecord(date: Date().addingTimeInterval(-9 * day + 600), kind: .trash, freedBytes: 32_500_000_000,
                                trashedBytes: 0, items: [], itemCount: 2),
                    CleanRecord(date: Date().addingTimeInterval(-2 * day), kind: .docker, freedBytes: 1_150_000_000,
                                trashedBytes: 0, items: [], itemCount: 0),
                ] { demoHistory.append(record) }
                if args.contains("--demo-old-copy") {
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    model.showOldCopiesForPreview([OldCopy(path: home + "/Downloads/Breathy/Breathy.app", version: "0.2.0")])
                }
                scan.growthSince = scan.date.addingTimeInterval(-3 * 86_400)
                scan.growth = [
                    GrowthItem(key: "Library/Group Containers/group.net.whatsapp.WhatsApp.shared",
                               title: "WhatsApp", bytes: 46_000_000_000, delta: 2_400_000_000),
                    GrowthItem(key: "Downloads", title: "İndirilenler", bytes: 9_000_000_000, delta: 1_100_000_000),
                    GrowthItem(key: "Movies/Kurgu", title: "Filmler/Kurgu", bytes: 4_000_000_000, delta: 600_000_000),
                ]
                if args.contains("--demo-update") {
                    model.showUpdateForPreview(ReleaseInfo(
                        version: "0.3.0", notes: "", pageURL: URL(string: "https://github.com")!,
                        zipURL: URL(string: "https://github.com")!))
                }
            }
            model.loadForPreview(scan)  // bundan sonra hiçbir şey diske yazılmaz
            // Örnek geçmiş, önizleme moduna geçildikten sonra eklenir (gerçek history.json'a yazılmasın).
            for record in demoHistory { model.addHistory(record) }
        }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            await capture(MenuPanel(model: model), size: nil, to: out.appending(path: "gercek-panel.png"))
            // Küçük ekran: panel sığmaz, orta bölüm kaydırılır, alttaki satır (Çık) görünür kalır.
            MenuPanel.previewScreenHeight = 560
            await capture(MenuPanel(model: model), size: nil, to: out.appending(path: "gercek-panel-kucuk-ekran.png"))
            MenuPanel.previewScreenHeight = nil
            // Menü çubuğu etiketi, açık ve koyu menü çubuğu üstünde.
            for (dark, name) in [(false, "menu-cubugu"), (true, "menu-cubugu-koyu")] {
                await capture(MenuBarLabel(model: model).padding(.horizontal, 10).padding(.vertical, 4),
                              size: nil, to: out.appending(path: "\(name).png"), dark: dark)
            }
            // "+X GB açıldı" kutusu: sayaç bitsin diye biraz daha beklenir.
            model.celebrate(2_340_000_000, detail: "Çöp boşaltıldı")
            await capture(MenuPanel(model: model), size: nil, to: out.appending(path: "gercek-panel-acildi.png"),
                          settle: .milliseconds(1800))
            model.celebrate(2_340_000_000, detail: "Çöp boşaltıldı")
            await capture(MenuPanel(model: model), size: nil, to: out.appending(path: "gercek-panel-acildi-koyu.png"),
                          settle: .milliseconds(1800), dark: true)
            for (category, name) in [(ScanCategory.caches, "onbellek"), (.duplicates, "cift"), (.largeFiles, "buyuk"),
                                     (.screenCaptures, "ekran"), (.appLeftovers, "artik")] {
                model.detailsCategory = category
                await capture(DetailsView(model: model), size: NSSize(width: 900, height: 600),
                              to: out.appending(path: "gercek-detaylar-\(name).png"))
            }
            await capture(UsageProfileView(model: model), size: nil, to: out.appending(path: "gercek-profil.png"))
            await capture(SystemDataView(model: model), size: nil, to: out.appending(path: "gercek-sistem-verileri.png"))
            await capture(HistoryView(model: model), size: NSSize(width: 620, height: 420),
                          to: out.appending(path: "gercek-gecmis.png"))
            model.detailsCategory = .docker
            await capture(DetailsView(model: model), size: NSSize(width: 900, height: 600),
                          to: out.appending(path: "gercek-detaylar-docker.png"), settle: .milliseconds(2500))
            // En dar pencere: temizlik çubuğundaki düğmeler sığıyor mu?
            model.detailsCategory = .duplicates
            await capture(DetailsView(model: model), size: NSSize(width: 800, height: 480),
                          to: out.appending(path: "gercek-detaylar-cift-dar.png"))
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ view: some View, size: NSSize?, to url: URL,
                                settle: Duration = .milliseconds(900), dark: Bool = false) async {
        // Sistem görünümünden bağımsız: açık (ya da istenince koyu) ve dolu arka planla çiz.
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let frameSize = size ?? hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: frameSize.width, height: frameSize.height),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()  // ekran dışında
        try? await Task.sleep(for: settle)  // listeler satırlarını yerleştirsin, animasyonlar bitsin
        if size == nil {
            // Panel yüksekliğini ilk yerleşimden sonra ölçer (kaydırılan bölüm): yeniden boyutlandır.
            window.setContentSize(hosting.fittingSize)
            try? await Task.sleep(for: .milliseconds(300))
        }
        hosting.layoutSubtreeIfNeeded()
        // Ekran 1x olsa da 2x çiz (README görselleri Retina ekranlarda net görünsün).
        let bounds = hosting.bounds
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = bounds.size
            hosting.cacheDisplay(in: bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
#endif
