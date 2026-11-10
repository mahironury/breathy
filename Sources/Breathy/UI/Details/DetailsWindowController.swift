import AppKit
import SwiftUI

/// Detaylar penceresi. SwiftUI `Window` sahnesi yerine elle yönetilir: menü çubuğu uygulamasında
/// açılışta kendiliğinden belirmesin, her istendiğinde öne gelsin.
@MainActor
final class DetailsWindowController {
    static let shared = DetailsWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: DetailsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Breathy — Detaylar"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 960, height: 620))
            window.minSize = NSSize(width: 800, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("BreathyDetails")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
