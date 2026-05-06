import Foundation

enum SettingsCountdownPresenter {
    static func codexCountdownText(to target: Date?, now: Date, language: AppLanguage) -> String {
        CountdownFormatter.text(to: target, now: now, placeholder: "--:--:--", language: language)
    }
}
