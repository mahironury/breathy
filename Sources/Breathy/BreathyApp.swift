import AppKit
import SwiftUI

/// Breathy — menü çubuğunda yaşayan disk ferahlatıcı.
/// Dock simgesi yok (Info.plist: LSUIElement), sadece sağ üstte rüzgâr simgesi.
/// Detaylar penceresi `DetailsWindowController` ile istenince açılır.
@main
struct BreathyApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        #if BREATHY_DEV_TOOLS
        // Sadece geliştirme derlemesinde: --report / --snapshot / --verify-update.
        if DevTools.run(model: model) {
            model.showsMenuBarIcon = false
            return
        }
        #endif
        // Aynı anda tek Breathy (bkz. SingleInstance).
        switch SingleInstance.resolve() {
        case .run:
            model.startBackgroundServices()  // açılışta başlatma + 10 GB uyarısı
        case .quit(let delay):
            model.showsMenuBarIcon = false
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                NSApp.terminate(nil)
            }
        case .waitFor(let keepers):
            // Aynı kopyanın eski süreci kapanmak üzere olabilir (eski sürümün güncellemesi): bekle.
            model.showsMenuBarIcon = false
            Task { @MainActor in
                if await SingleInstance.waitUntilGone(keepers) {
                    model.showsMenuBarIcon = true
                    model.startBackgroundServices()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { model.showsMenuBarIcon }, set: { model.showsMenuBarIcon = $0 })) {
            MenuPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
