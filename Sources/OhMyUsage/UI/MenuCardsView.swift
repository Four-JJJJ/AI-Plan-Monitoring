import SwiftUI

struct OfficialProviderGroupCard<ID: Hashable>: View {
    let iconName: String
    let iconFallback: String
    let primary: MenuOfficialSlotCardPresentation<ID>
    let primaryMetrics: [PercentageMetricDisplay]
    let secondary: [MenuOfficialSlotCardPresentation<ID>]
    let backgroundColor: Color
    let statusColor: (MenuCardStatusPresentation) -> Color
    let switchAction: (ID) -> Void
    private let groupBackgroundColor = SettingsVisualTokens.Menu.groupBackground

    var body: some View {
        if secondary.isEmpty {
            primaryCard
        } else {
            VStack(alignment: .leading, spacing: 12) {
                primaryCard

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(secondary.enumerated()), id: \.element.id) { index, row in
                        CompactOfficialSlotRowView(
                            iconName: iconName,
                            iconFallback: iconFallback,
                            row: row,
                            statusColor: statusColor(row.status),
                            action: row.actionLabel != nil ? { switchAction(row.id) } : nil
                        )

                        if index < secondary.count - 1 {
                            ModelCardDivider()
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
            .background(
                SettingsSmoothedRoundedRectangle(
                    cornerRadius: SettingsVisualTokens.Radius.card,
                    smoothing: SettingsVisualTokens.Smoothing.continuous
                )
                    .fill(groupBackgroundColor)
            )
        }
    }

    private var primaryCard: some View {
        PercentageModelCard(
            title: primary.title,
            planType: primary.planType,
            iconName: iconName,
            iconFallback: iconFallback,
            subtitle: primary.subtitle,
            status: CardStatus(
                text: primary.status.text,
                color: statusColor(primary.status)
            ),
            metrics: primaryMetrics,
            errorText: primary.detailText,
            backgroundColor: backgroundColor,
            isDisconnected: false
        )
    }
}

private struct CompactOfficialSlotRowView<ID: Hashable>: View {
    private let compactLineHeight: CGFloat = 12
    private let titleMetricSpacing: CGFloat = 4
    private var rowContentHeight: CGFloat {
        compactLineHeight * 2 + titleMetricSpacing
    }
    let iconName: String
    let iconFallback: String
    let row: MenuOfficialSlotCardPresentation<ID>
    let statusColor: Color
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ModelIconBadge(
                iconName: iconName,
                fallback: iconFallback
            )

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: titleMetricSpacing) {
                    ModelTitleWithPlanType(
                        title: row.title,
                        planType: row.planType,
                        textColor: SettingsVisualTokens.Text.primary
                    )
                    .frame(height: compactLineHeight, alignment: .top)
                    CompactMetricSummaryView(segments: row.compactMetricSegments)
                        .frame(height: compactLineHeight, alignment: .bottom)
                }
                .frame(height: rowContentHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                HStack(spacing: 12) {
                    if let actionLabel = row.actionLabel, let action {
                        HoverActionButton(title: actionLabel, disabled: row.actionDisabled, action: action)
                    }

                    Text(row.status.text)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(statusColor)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: rowContentHeight, alignment: .center)
            }
        }
        .frame(height: rowContentHeight, alignment: .center)
    }
}

private struct CompactMetricSummaryView: View {
    let segments: [MenuCompactMetricSegmentPresentation]

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(segment.title)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(SettingsVisualTokens.Text.tertiary)
                        .lineSpacing(0)
                        .lineLimit(1)

                    Text(segment.valueText)
                        .font(AppFonts.numeric(size: 12, fallbackWeight: .bold))
                        .foregroundStyle(SettingsVisualTokens.Text.primary)
                        .lineSpacing(0)
                        .lineLimit(1)
                }
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}
