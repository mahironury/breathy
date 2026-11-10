import AppKit

enum RunningApps {
    /// Açık uygulamalar: küçük harfli bundle ID → görünen ad.
    @MainActor
    static func snapshot() -> [String: String] {
        var running: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            running[id.lowercased()] = app.localizedName ?? id
        }
        return running
    }
}

extension ScanEnvironment {
    /// Gerçek Mac için ortam. Açık uygulamaların listesi tarama başlarken alınır.
    @MainActor
    static func live() -> ScanEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let running = RunningApps.snapshot()
        return ScanEnvironment(
            home: home,
            applicationDirs: [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")],
            systemApplicationDirs: [
                URL(fileURLWithPath: "/System/Applications"),
                URL(fileURLWithPath: "/System/Applications/Utilities"),
            ],
            now: Date(),
            runningApps: running,
            ownBundleID: Bundle.main.bundleIdentifier ?? "com.breathy.app",
            isRegistered: { id in
                guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?
                    .takeRetainedValue() as? [URL] else { return false }
                return !urls.isEmpty
            },
            lastUsed: { Spotlight.lastUsed($0) },
            dateAdded: { Spotlight.dateAdded($0) },
            iCloudStatus: ICloudStatus.read(),
            screenshotFolder: ScreenshotSettings.location(home: home)
        )
    }
}
