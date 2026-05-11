import SwiftUI

struct SettingsResetDialogView: View {
    var title: String
    var description: String
    var cancelTitle: String
    var confirmTitle: String
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                dialogButton(
                    title: cancelTitle,
                    background: Color.white.opacity(0.12),
                    foreground: Color.white.opacity(0.82),
                    border: Color.white.opacity(0.12),
                    weight: .regular,
                    action: onCancel
                )
                .keyboardShortcut(.cancelAction)

                dialogButton(
                    title: confirmTitle,
                    background: Color(hex: 0xD05757),
                    foreground: Color.white.opacity(0.96),
                    border: Color(hex: 0xD05757),
                    weight: .semibold,
                    action: onConfirm
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(width: 260, alignment: .center)
        .frame(minHeight: 204, alignment: .center)
        .background(
            DialogSmoothRoundedRectangle(cornerRadius: 10, smoothing: 0.45)
                .fill(Color(hex: 0x1C1C1E))
        )
        .overlay(
            DialogSmoothRoundedRectangle(cornerRadius: 10, smoothing: 0.45)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 28, x: 0, y: 14)
        .shadow(color: Color.black.opacity(0.24), radius: 1, x: 0, y: 0)
    }

    private func dialogButton(
        title: String,
        background: Color,
        foreground: Color,
        border: Color,
        weight: Font.Weight,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: weight))
                .foregroundStyle(foreground)
                .lineLimit(1)
                .frame(minWidth: 104)
                .frame(height: 30)
                .background(
                    DialogSmoothRoundedRectangle(cornerRadius: 7, smoothing: 0.45)
                        .fill(background)
                )
                .overlay(
                    DialogSmoothRoundedRectangle(cornerRadius: 7, smoothing: 0.45)
                        .stroke(border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
