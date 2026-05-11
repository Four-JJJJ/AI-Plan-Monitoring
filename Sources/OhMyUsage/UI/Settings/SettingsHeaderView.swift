import SwiftUI

struct SettingsHeaderView: View {
    var presentation: SettingsHeaderPresentation
    var theme: SettingsTheme
    var onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.titleColor)

                Text(presentation.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.hintColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onRefresh) {
                Label(presentation.refreshButtonTitle, systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(theme.accentColor)
            .help(presentation.refreshHelpText)
        }
    }
}
