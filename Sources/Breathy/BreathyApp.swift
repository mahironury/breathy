import AppKit
import SwiftUI

/// Breathy — menü çubuğunda yaşayan disk ferahlatıcı.
/// Dock simgesi yok (Info.plist: LSUIElement), sadece sağ üstte rüzgâr simgesi.
/// Detaylar penceresi `DetailsWindowController` ile istenince açılır.
@main
struct BreathyApp: App {
    @State private var model: AppModel
    /// Açılışta bir kez belirlenir ve değişmez. MenuBarExtra'nın `isInserted`'ı değişken bir duruma
    /// (Binding(get:set:)) bağlanırsa panel açılınca SwiftUI sahneyi durmadan yeniden kurar ve uygulama
    /// kilitlenir (0.2.2'de yaşandı). Bu yüzden her zaman `.constant`.
    private let showsMenuBarIcon: Bool

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        #if BREATHY_DEV_TOOLS
        // Sadece geliştirme derlemesinde: --report / --snapshot / --verify-update.
        if DevTools.run(model: model) {
            showsMenuBarIcon = false
            return
        }
        if UISmokeTest.outputPath != nil {  // duman testi: kurulu Breathy açık olsa da çalışsın
            showsMenuBarIcon = true
            model.startBackgroundServices()
            return
        }
        #endif
        // Aynı anda tek Breathy (bkz. SingleInstance).
        switch SingleInstance.resolve() {
        case .run:
            showsMenuBarIcon = true
            model.startBackgroundServices()  // açılışta başlatma + 10 GB uyarısı
        case .quit(let delay):
            showsMenuBarIcon = false
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                NSApp.terminate(nil)
            }
        case .waitFor(let keepers):
            // Aynı kopyanın eski süreci kapanmak üzere olabilir (eski sürümün güncellemesi): bekle.
            // Simge sahnede kalır ama beklerken boş görünür.
            showsMenuBarIcon = true
            model.isPrimaryInstance = false
            Task { @MainActor in
                if await SingleInstance.waitUntilGone(keepers) {
                    model.isPrimaryInstance = true
                    model.startBackgroundServices()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(showsMenuBarIcon)) {
            MenuPanel(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
