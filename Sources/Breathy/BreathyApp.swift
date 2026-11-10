import SwiftUI

/// Breathy — menü çubuğunda yaşayan disk ferahlatıcı.
/// Dock simgesi yok (Info.plist: LSUIElement), sadece sağ üstte rüzgâr simgesi.
/// Detaylar penceresi `DetailsWindowController` ile istenince açılır.
@main
struct BreathyApp: App {
    @State private var model: AppModel
    /// Rapor/önizleme modlarında menü çubuğuna simge konmaz.
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
        #endif
        showsMenuBarIcon = true
        model.startBackgroundServices()  // açılışta başlatma + 10 GB uyarısı
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
