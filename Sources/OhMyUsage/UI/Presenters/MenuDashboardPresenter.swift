import Foundation

struct MenuDashboardHeaderUpdatePresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case positive
        case negative
    }

    var title: String
    var retryTitle: String?
    var tone: Tone
    var isRetryEnabled: Bool
    var showsPrimaryAction: Bool
    var accessibilityLabel: String
}

struct MenuDashboardHeaderPresentation: Equatable {
    var updatedText: String
    var update: MenuDashboardHeaderUpdatePresentation?
}

enum MenuDashboardPresenter {
    static func headerPresentation(
        lastUpdatedAt: Date?,
        language: AppLanguage,
        now: Date,
        updatedAgoLabel: String,
        updateState: MenuUpdateDisplayState
    ) -> MenuDashboardHeaderPresentation {
        MenuDashboardHeaderPresentation(
            updatedText: updatedText(
                lastUpdatedAt: lastUpdatedAt,
                language: language,
                now: now,
                updatedAgoLabel: updatedAgoLabel
            ),
            update: updatePresentation(language: language, updateState: updateState)
        )
    }

    static func updatedText(
        lastUpdatedAt: Date?,
        language: AppLanguage,
        now: Date,
        updatedAgoLabel: String
    ) -> String {
        if let lastUpdatedAt {
            return "\(updatedAgoLabel) \(elapsedText(from: lastUpdatedAt, now: now, language: language))"
        }
        return language == .zhHans ? "更新于 -" : "Updated -"
    }

    static func elapsedText(
        from date: Date,
        now: Date,
        language: AppLanguage
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch language {
        case .zhHans:
            if seconds < 60 { return "\(seconds) 秒前" }
            if seconds < 3600 { return "\(seconds / 60) 分钟前" }
            if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
            return "\(seconds / 86_400) 天前"
        case .en:
            if seconds < 60 { return "\(seconds)s ago" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86_400 { return "\(seconds / 3600)h ago" }
            return "\(seconds / 86_400)d ago"
        }
    }

    private static func updatePresentation(
        language: AppLanguage,
        updateState: MenuUpdateDisplayState
    ) -> MenuDashboardHeaderUpdatePresentation? {
        if case .idle = updateState.kind {
            return nil
        }

        let title = updateState.statusText ?? ""
        return MenuDashboardHeaderUpdatePresentation(
            title: title,
            retryTitle: updateState.retryTitle,
            tone: tone(for: updateState.tone),
            isRetryEnabled: updateState.isRetryEnabled,
            showsPrimaryAction: showsPrimaryAction(for: updateState.kind),
            accessibilityLabel: language == .zhHans
                ? "应用更新状态：\(title)"
                : "App update status: \(title)"
        )
    }

    private static func tone(for tone: UpdateDisplayTone) -> MenuDashboardHeaderUpdatePresentation.Tone {
        switch tone {
        case .neutral:
            return .neutral
        case .positive:
            return .positive
        case .negative:
            return .negative
        }
    }

    private static func showsPrimaryAction(for kind: MenuUpdateDisplayState.Kind) -> Bool {
        if case .updateAvailable = kind {
            return true
        }
        return false
    }
}
