import Foundation

enum CountdownFormatter {
    static func text(
        to target: Date?,
        now: Date = Date(),
        placeholder: String,
        language: AppLanguage
    ) -> String {
        guard let target else { return placeholder }
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        if days > 0 {
            let hours = (interval % 86_400) / 3_600
            switch language {
            case .zhHans:
                return "\(days)天\(hours)时"
            case .en:
                return "\(days) d \(hours) h"
            }
        }
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        switch language {
        case .zhHans:
            return "\(hours)时\(minutes)分"
        case .en:
            return "\(hours) h \(minutes) m"
        }
    }
}
