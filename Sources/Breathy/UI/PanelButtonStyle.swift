import SwiftUI

/// Panelin büyük, tam genişlikteki eylem düğmeleri.
struct PanelButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, tint: tint)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(configuration.isPressed ? 0.28 : 0.14))
                )
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Simge + başlık + sağda değer.
struct PanelRow: View {
    let icon: String
    let title: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18)
            Text(title).fontWeight(.medium)
            Spacer()
            if let trailing {
                Text(trailing).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
