import Foundation

struct MenuCompactMetricSegmentPresentation: Equatable {
    var title: String
    var valueText: String
}

struct MenuOfficialSlotCardPresentation<ID: Hashable>: Identifiable, Equatable {
    var id: ID
    var title: String
    var planType: String?
    var subtitle: String?
    var status: MenuCardStatusPresentation
    var metricDisplays: [MenuQuotaMetricDisplayPresentation]
    var compactMetricSegments: [MenuCompactMetricSegmentPresentation]
    var actionLabel: String?
    var actionDisabled: Bool
    var detailText: String?
}

struct MenuOfficialProviderGroupPresentation<ID: Hashable>: Equatable {
    var primary: MenuOfficialSlotCardPresentation<ID>
    var secondary: [MenuOfficialSlotCardPresentation<ID>]
}

enum MenuOfficialProviderGroupPresenter {
    static func compactMetricSegments(
        from metricDisplays: [MenuQuotaMetricDisplayPresentation]
    ) -> [MenuCompactMetricSegmentPresentation] {
        metricDisplays
            .prefix(2)
            .compactMap { metric in
                let title = metric.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let valueText = metric.valueText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !valueText.isEmpty else { return nil }
                return MenuCompactMetricSegmentPresentation(title: title, valueText: valueText)
            }
    }

    static func slotCardPresentation<ID: Hashable>(
        id: ID,
        title: String,
        planType: String?,
        subtitle: String?,
        status: MenuCardStatusPresentation,
        metricDisplays: [MenuQuotaMetricDisplayPresentation],
        isActive: Bool,
        canSwitch: Bool,
        isSwitching: Bool,
        switchActionLabel: String
    ) -> MenuOfficialSlotCardPresentation<ID> {
        let action = MenuCardStatePresenter.slotActionPresentation(
            isActive: isActive,
            canSwitch: canSwitch,
            isSwitching: isSwitching,
            actionLabel: switchActionLabel,
            infoText: nil,
            infoIsError: false
        )

        return MenuOfficialSlotCardPresentation(
            id: id,
            title: title,
            planType: planType,
            subtitle: subtitle,
            status: status,
            metricDisplays: metricDisplays,
            compactMetricSegments: compactMetricSegments(from: metricDisplays),
            actionLabel: action.actionLabel,
            actionDisabled: action.actionDisabled,
            detailText: nil
        )
    }

    static func group<ID: Hashable>(
        from presentations: [MenuOfficialSlotCardPresentation<ID>]
    ) -> MenuOfficialProviderGroupPresentation<ID>? {
        guard var primary = presentations.first else { return nil }
        primary.actionLabel = nil
        primary.actionDisabled = false
        primary.detailText = nil

        return MenuOfficialProviderGroupPresentation(
            primary: primary,
            secondary: Array(presentations.dropFirst())
        )
    }
}
