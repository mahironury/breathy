import AppKit
import SwiftUI

/// Menü çubuğunda görünen kısım: rüzgâr simgesi + boş alan, örn. "≋ 11,8 GB".
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.isPrimaryInstance {
            let free = model.disk.map { ByteFormat.string($0.available) }
            Image(nsImage: MenuBarIcon.image(freeText: free))
                .accessibilityLabel(free.map { "Breathy, \($0) boş" } ?? "Breathy")
        } else {
            // Başka bir Breathy'nin kapanması bekleniyor (en çok 3 sn): yer kaplamayan boş simge.
            Image(nsImage: NSImage(size: NSSize(width: 1, height: 1)))
        }
    }
}

/// Etiketi tek bir şablon (template) resim olarak çizer.
/// MenuBarExtra, Text içine gömülü Image'ı menü çubuğuna aktarırken düşürüyor (sadece yazı görünüyordu).
/// Resmi kendimiz çizince simge her zaman görünür; şablon olduğu için açık/koyu menü çubuğuna
/// rengi macOS uyarlar. Değer dakikada bir değişir; aynı değer için tekrar çizilmez.
@MainActor
enum MenuBarIcon {
    private static var cache: (key: String, image: NSImage)?

    static func image(freeText: String?) -> NSImage {
        let key = freeText ?? ""
        if let cache, cache.key == key { return cache.image }
        let image = render(freeText)
        cache = (key, image)
        return image
    }

    static func render(_ freeText: String?) -> NSImage {
        let content = HStack(spacing: 4) {
            Image(systemName: "wind")
                .font(.system(size: 14, weight: .semibold))
            if let freeText {
                Text(freeText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(Color.black)  // şablonda sadece saydamlık kullanılır
        .fixedSize()

        let renderer = ImageRenderer(content: content)
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        renderer.scale = max(scale, 2)
        guard let cgImage = renderer.cgImage else {
            let fallback = NSImage(systemSymbolName: "wind", accessibilityDescription: "Breathy") ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }
        let size = NSSize(width: CGFloat(cgImage.width) / renderer.scale,
                          height: CGFloat(cgImage.height) / renderer.scale)
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }
}
