import Foundation

enum BackoffPolicy {
    static func delaySeconds(baseInterval: Int, consecutiveFailures: Int) -> Int {
        if consecutiveFailures <= 0 {
            return baseInterval
        }
        if consecutiveFailures == 1 {
            return 120
        }
        return 300
    }
}
