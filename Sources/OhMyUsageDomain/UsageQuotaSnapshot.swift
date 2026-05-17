public struct UsageQuotaSnapshot: Equatable, Sendable {
    public let used: Double
    public let limit: Double?
    public let capturedAtUnixSeconds: Double

    public init(
        used: Double,
        limit: Double?,
        capturedAtUnixSeconds: Double
    ) {
        self.used = max(0, used)
        self.limit = limit.map { max(0, $0) }
        self.capturedAtUnixSeconds = capturedAtUnixSeconds
    }

    public var remaining: Double? {
        guard let limit else { return nil }
        return max(0, limit - used)
    }

    public var usageRatio: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(1, max(0, used / limit))
    }
}
