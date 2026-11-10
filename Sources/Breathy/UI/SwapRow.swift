import SwiftUI

/// Takas dosyası büyüdüyse yeniden başlatma önerisi.
struct SwapRow: View {
    let swap: SwapInfo

    var body: some View {
        Label {
            Text(message).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .font(.caption)
        .foregroundStyle(.orange)
    }

    private var message: String {
        var text = "Takas dosyası \(ByteFormat.string(swap.fileBytes))"
        if let days = swap.uptimeDays(), days > 0 { text += " · Mac \(days) gündür açık" }
        return text + ". Yeniden başlatınca bu alan geri gelir."
    }
}
