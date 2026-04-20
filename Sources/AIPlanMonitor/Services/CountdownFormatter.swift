import Foundation

enum CountdownFormatter {
    static func text(
        to target: Date?,
        now: Date = Date(),
        placeholder: String
    ) -> String {
        guard let target else { return placeholder }
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        if days > 0 {
            let hours = (interval % 86_400) / 3_600
            return "\(days)天\(hours)时"
        }
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        return "\(hours)时\(minutes)分"
    }
}
