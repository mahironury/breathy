import Foundation

/// iCloud analizi: bu Mac'te hangi servisler açık, iCloud Drive'da ne kadar ve nerede yer var,
/// ekran görüntüleri nerede birikiyor, iCloud kapatılırken bırakılmış yerel kopyalar.
extension Scanner {
    func iCloudSummary(screenshots: [Finding], _ ctx: ScanContext) throws -> (ICloudSummary, [Finding]) {
        let fm = FileManager.default
        var summary = ICloudSummary(status: env.iCloudStatus, screenshotFolder: env.screenshotFolder.path)
        summary.screenshotCount = screenshots.count
        summary.screenshotBytes = screenshots.reduce(0) { $0 + $1.bytes }

        // iCloud Drive klasörleri: iCloud'da kapladığı (mantıksal) ve Mac'e inmiş kısmı.
        // Sadece okunur; PathGuard bu klasörde silmeye izin vermez.
        let drive = env.home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if let children = try? fm.contentsOfDirectory(at: drive, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            var folders: [ICloudFolder] = []
            for child in children where child.lastPathComponent != ".DS_Store" {
                try ctx.checkpoint(nil)
                if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                ctx.setFolder(child)
                let sizes = try measureBoth(child, ctx)
                folders.append(ICloudFolder(name: child.lastPathComponent, bytes: sizes.logical, localBytes: sizes.local))
                summary.driveBytes += sizes.logical
                summary.driveLocalBytes += sizes.local
            }
            summary.topFolders = Array(folders.sorted { $0.bytes > $1.bytes }.prefix(8))
        }

        // iCloud Drive kapatılırken "kopyasını sakla" denince oluşan yerel klasörler.
        let cloudStorage = env.home.appending(path: "Library/CloudStorage", directoryHint: .isDirectory)
        let archiveDirs =
            ((try? fm.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("iCloudDrive-") && $0.lastPathComponent.contains("(") }
            + ((try? fm.contentsOfDirectory(at: env.home, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("iCloud Drive (") }

        var archives: [Finding] = []
        for dir in archiveDirs {
            try ctx.checkpoint(nil)
            let bytes = try measure(dir, ctx)
            if bytes >= limits.minItemBytes,
               let f = makeFinding(dir, .iCloudArchive, .info, bytes: bytes,
                                   note: "iCloud Drive kapatılırken bu Mac'te bırakılan kopya", ctx: ctx) {
                archives.append(f)
            }
        }
        return (summary, archives)
    }
}
