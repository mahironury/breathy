import SwiftUI

/// Yer açılınca panelde beliren kutu: rüzgâr simgesi savrulur, "+X GB" sıfırdan sayarak yükselir.
struct FreedBanner: View {
    let celebration: Celebration
    @State private var gust = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce.up, options: .repeat(2), value: gust)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    AnimatedBytes(bytes: celebration.bytes, prefix: "+")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("açıldı").font(.headline)
                }
                if let detail = celebration.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.green.opacity(0.25)))
        .accessibilityElement(children: .combine)
        .onAppear { gust += 1 }
    }
}

/// Ekrana gelince 0'dan hedef değere sayan bayt metni ("2,3 GB"). Hareket azaltma açıksa doğrudan gösterir.
struct AnimatedBytes: View {
    let bytes: Int64
    var prefix = ""
    var suffix = ""
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CountingBytes(value: shown, prefix: prefix, suffix: suffix)
            .monospacedDigit()
            .accessibilityLabel(prefix + ByteFormat.string(bytes) + suffix)
            .onAppear { animate() }
            .onChange(of: bytes) { animate() }
    }

    private func animate() {
        if reduceMotion {
            shown = Double(bytes)
        } else {
            withAnimation(.easeOut(duration: 1.2)) { shown = Double(bytes) }
        }
    }
}

/// SwiftUI ara değerleri `animatableData` üzerinden verir; her karede metin yeniden biçimlenir.
private struct CountingBytes: View, Animatable {
    var value: Double
    let prefix: String
    let suffix: String

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(prefix + ByteFormat.string(Int64(value.rounded())) + suffix)
    }
}
