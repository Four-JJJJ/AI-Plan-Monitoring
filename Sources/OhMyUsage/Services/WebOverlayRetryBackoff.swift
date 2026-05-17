import Foundation

actor WebOverlayRetryBackoff {
    private var blockedUntil: [String: Date] = [:]

    func shouldAttempt(for key: String, forceRefresh: Bool, now: Date = Date()) -> Bool {
        if forceRefresh {
            return true
        }
        guard let deadline = blockedUntil[key] else {
            return true
        }
        return now >= deadline
    }

    func markFailure(for key: String, interval: TimeInterval, now: Date = Date()) {
        blockedUntil[key] = now.addingTimeInterval(max(0, interval))
    }

    func clearFailure(for key: String) {
        blockedUntil.removeValue(forKey: key)
    }
}
