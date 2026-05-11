import SwiftUI

struct SettingsOverviewCardItem: Identifiable {
    var id: String
    var icon: String
    var title: String
    var value: String
    var detail: String
    var accent: Color
}

struct SettingsOverviewView<Sections: View>: View {
    var items: [SettingsOverviewCardItem]
    var theme: SettingsTheme
    var sections: Sections

    init(
        items: [SettingsOverviewCardItem],
        theme: SettingsTheme,
        @ViewBuilder sections: () -> Sections
    ) {
        self.items = items
        self.theme = theme
        self.sections = sections()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewGrid(items: items)
                sections
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.never)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: theme.shellCornerRadius)
                .fill(theme.cardBackground)
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: theme.shellCornerRadius)
                .stroke(theme.shellStrokeColor, lineWidth: 1)
        )
        .clipShape(SettingsSmoothedRoundedRectangle(cornerRadius: theme.shellCornerRadius))
    }

    private func overviewGrid(items: [SettingsOverviewCardItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16, alignment: .top)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(items) { item in
                overviewCard(item)
            }
        }
    }

    private func overviewCard(_ item: SettingsOverviewCardItem) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.accent)

                Spacer(minLength: 12)

                Text(item.value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(item.accent)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.titleColor)
                Text(item.detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(theme.hintColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(
            SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                .fill(item.accent.opacity(0.12))
        )
        .overlay(
            SettingsSmoothedRoundedRectangle(cornerRadius: theme.sectionCornerRadius)
                .stroke(item.accent.opacity(0.35), lineWidth: 1)
        )
    }
}
