import Foundation
import UserNotifications

/// Boş alan 10 GB'ın altına inince tek bir bildirim. 15 GB'ın üstüne çıkana kadar tekrar etmez
/// (sınırda gidip gelen disk her dakika bildirim yağdırmasın).
struct LowSpaceAlert: Sendable, Equatable {
    static let threshold: Int64 = 10_000_000_000
    static let rearmAbove: Int64 = 15_000_000_000

    private(set) var hasAlerted: Bool

    init(hasAlerted: Bool = false) {
        self.hasAlerted = hasAlerted
    }

    /// Yeni boş alan değerini işler; bildirim gönderilmesi gerekiyorsa true döner.
    mutating func shouldNotify(available: Int64) -> Bool {
        if available >= Self.rearmAbove {
            hasAlerted = false
            return false
        }
        guard available < Self.threshold, !hasAlerted else { return false }
        hasAlerted = true
        return true
    }
}

/// Bildirimi gönderir. Sadece gerçek uygulamada (paket kimliği olan .app) oluşturulur;
/// testlerde ve rapor/önizleme modlarında hiç çalışmaz.
@MainActor
final class LowSpaceNotifier: NSObject, UNUserNotificationCenterDelegate {
    private static let alertedKey = "lowSpaceAlerted"
    private static let requestID = "breathy.low-space"

    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var alert: LowSpaceAlert
    /// Bildirime tıklanınca.
    var onOpen: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alert = LowSpaceAlert(hasAlerted: defaults.bool(forKey: Self.alertedKey))
        super.init()
        center.delegate = self
        // macOS izni yalnızca ilk seferde sorar; sonra bu çağrı sessizce döner.
        // Cevap arka plandaki bir kuyrukta gelir: kapanış @Sendable olmalı, yoksa Swift 6 onu
        // ana aktöre bağlar ve çalışma anındaki kuyruk denetimi uygulamayı çökertir.
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
    }

    func check(_ disk: DiskSnapshot) {
        let before = alert
        if alert.shouldNotify(available: disk.available) { send(available: disk.available) }
        if alert != before { defaults.set(alert.hasAlerted, forKey: Self.alertedKey) }
    }

    private func send(available: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Disk dolmak üzere"
        content.body = "Sadece \(ByteFormat.string(available)) boş alan kaldı. Breathy'de tarama yapıp yer açabilirsin."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil))
    }

    /// Sürüm değiştiyse (güncellemeden sonraki ilk açılış) tek bir bildirim.
    func notifyUpdated(from old: String?, to new: String) {
        let content = UNMutableNotificationContent()
        content.title = "Breathy güncellendi"
        content.body = old.map { "Sürüm \(new) çalışıyor (önceki: \($0)). Eski sürüm kapatıldı." }
            ?? "Sürüm \(new) çalışıyor. Eski sürüm kapatıldı."
        center.add(UNNotificationRequest(identifier: "breathy.updated", content: content, trigger: nil))
    }

    // Breathy menü çubuğu uygulaması olduğu için hep "ön planda" sayılır; bildirimi yine de göster.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await opened()
    }

    private func opened() {
        onOpen?()
    }
}
