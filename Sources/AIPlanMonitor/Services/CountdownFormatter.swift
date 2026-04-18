import Foundation

enum CountdownFormatter {
    static func text(
        to target: Date?,
        now: Date = Date(),
        placeholder: String
    ) -> String {
        guard let target else { return placeholder }
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let hours = interval / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
