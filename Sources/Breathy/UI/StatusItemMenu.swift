import AppKit

/// Menü çubuğundaki simgeye sağ tıklayınca (ya da Control ile tıklayınca) açılan kısa menü:
/// paneli aç, Detaylar, geçmiş, güncelleme ve Çık. Panel ekrana sığmasa bile Breathy her zaman
/// buradan kapatılabilir. SwiftUI'nin MenuBarExtra'sı sağ tıkı desteklemediği için tıklama,
/// simgenin penceresine ulaşmadan yakalanır.
@MainActor
final class StatusItemMenu: NSObject {
    private static var shared: StatusItemMenu?

    private let model: AppModel
    private var monitor: Any?

    private init(model: AppModel) {
        self.model = model
    }

    static func install(model: AppModel) {
        guard shared == nil else { return }
        let menu = StatusItemMenu(model: model)
        menu.monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let handled = MainActor.assumeIsolated { menu.handle(event) }
            return handled ? nil : event
        }
        shared = menu
    }

    /// Sağ tık ya da Control-tık simgenin üstündeyse menüyü gösterir ve olayı tüketir.
    private func handle(_ event: NSEvent) -> Bool {
        let isContextClick = event.type == .rightMouseDown
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick, let window = event.window, Self.isStatusItemWindow(window),
              let view = window.contentView else { return false }
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
        return true
    }

    /// Menü çubuğu simgesinin penceresi (AppKit'in iç sınıfı: NSStatusBarWindow).
    static func isStatusItemWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBarWindow")
    }

    /// Menü çubuğundaki kendi düğmemiz (MenuBarExtra'nın durum çubuğu penceresindeki NSStatusBarButton).
    static func statusButton() -> NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, String(describing: type(of: button)).contains("StatusBar") { return button }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        for window in NSApp.windows where isStatusItemWindow(window) {
            if let content = window.contentView, let button = find(content) { return button }
        }
        return nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Breathy'yi aç", #selector(openPanel)))
        if model.lastScan != nil {
            menu.addItem(item("Detaylar ve temizlik…", #selector(openDetails)))
        }
        menu.addItem(item("Temizlik geçmişi", #selector(openHistory)))
        menu.addItem(.separator())
        if let update = model.update {
            let install = item("Güncelle: v\(update.version)", #selector(installUpdate))
            install.isEnabled = !model.isUpdating
            menu.addItem(install)
        } else {
            menu.addItem(item("Güncellemeleri denetle", #selector(checkForUpdates)))
        }
        let version = NSMenuItem(title: "Breathy v\(Updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        menu.addItem(item("Breathy'den çık", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Eylemler

    /// Paneli açmak için simgeye normal bir tıklama gönderilir.
    @objc private func openPanel() {
        Self.statusButton()?.performClick(nil)
    }

    @objc private func openDetails() { model.openDetails(nil) }
    @objc private func openHistory() { model.showHistory() }
    @objc private func installUpdate() { model.installUpdate() }

    @objc private func checkForUpdates() {
        model.checkForUpdates(manual: true)
        openPanel()  // sonuç panelde görünür
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
