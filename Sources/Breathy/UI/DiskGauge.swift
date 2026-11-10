import SwiftUI

/// Büyük yüzde + renkli doluluk çubuğu.
struct DiskGauge: View {
    let disk: DiskSnapshot

    private var tint: Color {
        switch disk.usedFraction {
        case ..<0.80: .green
        case ..<0.90: .orange
        default: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Yer açılınca yüzde ve çubuk yumuşakça yeni değere kayar.
            HStack(alignment: .firstTextBaseline) {
                Text(ByteFormat.percent(disk.usedFraction))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("dolu").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ByteFormat.string(disk.available)) boş")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("\(ByteFormat.string(disk.used)) / \(ByteFormat.string(disk.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(geo.size.width * disk.usedFraction, 8))
                }
            }
            .frame(height: 10)
            .accessibilityElement()
            .accessibilityLabel("Disk \(ByteFormat.percent(disk.usedFraction)) dolu")
        }
        .animation(.spring(duration: 0.8, bounce: 0.2), value: disk.available)
    }
}
