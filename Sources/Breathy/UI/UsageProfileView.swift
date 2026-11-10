import AppKit
import SwiftUI

/// İlk açılışta (ve paneldeki "Odak" satırından) gösterilen ekran: "Bu Mac'i ne için kullanıyorsun?"
struct UsageProfileView: View {
    let model: AppModel
    var onDone: () -> Void = {}
    @State private var selection: Set<UsageArea>

    init(model: AppModel, onDone: @escaping () -> Void = {}) {
        self.model = model
        self.onDone = onDone
        _selection = State(initialValue: model.areas)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wind")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bu Mac'i ne için kullanıyorsun?")
                        .font(.title2.weight(.semibold))
                    Text("Seçtiğin alanlara özellikle bakarım, diğerlerini atlarım; tarama da hızlanır. İstediğin zaman panelden değiştirebilirsin.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(UsageArea.allCases) { area in
                    AreaCard(area: area, isOn: selection.contains(area)) {
                        if selection.contains(area) { selection.remove(area) } else { selection.insert(area) }
                    }
                }
            }

            Label {
                Text("Her zaman bakılanlar: uygulama önbellekleri ve loglar, eski kurulum dosyaları, büyük ve çift dosyalar, ekran görüntüleri, büyük gizli klasörler ve iCloud.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.circle").foregroundStyle(.green)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Button(selection.count == UsageArea.allCases.count ? "Hiçbirini seçme" : "Hepsini seç") {
                    selection = selection.count == UsageArea.allCases.count ? [] : Set(UsageArea.allCases)
                }
                .buttonStyle(.link)
                Spacer()
                Button("Şimdilik atla") {
                    model.skipUsageProfile()
                    onDone()
                }
                Button("Kaydet") {
                    model.setAreas(selection)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600)
    }
}

/// Seçilebilir alan kartı: simge, ad, Breathy'nin o alanda nelere baktığı.
private struct AreaCard: View {
    let area: UsageArea
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: area.icon)
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(area.title).font(.headline)
                    Text(area.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isOn ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Paneldeki tek satır: "Odak: Yazılım, Yapay zekâ araçları · Değiştir".
struct FocusRow: View {
    let areas: Set<UsageArea>
    let change: () -> Void

    private var text: String {
        if areas.count == UsageArea.allCases.count { return "bütün alanlar" }
        if areas.isEmpty { return "sadece günlük kullanım" }
        return UsageArea.allCases.filter(areas.contains).map(\.shortTitle).joined(separator: ", ")
    }

    var body: some View {
        Button(action: change) {
            HStack(spacing: 6) {
                Image(systemName: "scope").foregroundStyle(.secondary)
                Text("Odak: \(text)").foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text("Değiştir").foregroundStyle(.tint)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Breathy'nin hangi alanlara özellikle bakacağını seç")
    }
}

/// Kullanım alanı penceresi (Detaylar penceresi gibi elle yönetilir).
@MainActor
final class UsageProfileWindowController {
    static let shared = UsageProfileWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        let view = UsageProfileView(model: model) { [weak self] in self?.window?.close() }
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Breathy — Kullanım alanları"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
