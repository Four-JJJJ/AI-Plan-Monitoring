import Foundation

enum SnapshotStatus: String, Codable {
    case ok
    case warning
    case error
    case disabled
}

enum RelayDisplayMode: String, Codable, Equatable {
    case balance
    case quotaPercent
    case hybrid
}

enum FetchHealth: String, Codable, Equatable {
    case ok
    case authExpired
    case rateLimited
    case endpointMisconfigured
    case unreachable
}

enum ValueFreshness: String, Codable, Equatable {
    case live
    case cachedFallback
    case empty
}

enum UsageQuotaKind: String, Codable, Equatable {
    case session
    case weekly
    case reviews
    case credits
    case extraUsage
    case modelWeekly
    case custom
}

enum UsageQuotaResetSource: String, Codable, Equatable {
    case official
    case webObserved
    case localEstimate
    case userCalibrated
    case unknown
}

enum UsageQuotaResetConfidence: String, Codable, Equatable {
    case confirmed
    case estimated
    case stale
    case unknown
}

struct UsageQuotaWindow: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var remainingPercent: Double
    var usedPercent: Double
    var resetAt: Date?
    var kind: UsageQuotaKind
    var resetSource: UsageQuotaResetSource
    var observedAt: Date?
    var serverClockSkew: TimeInterval?
    var confidence: UsageQuotaResetConfidence
    var windowIdentity: String?

    init(
        id: String,
        title: String,
        remainingPercent: Double,
        usedPercent: Double,
        resetAt: Date? = nil,
        kind: UsageQuotaKind,
        resetSource: UsageQuotaResetSource = .unknown,
        observedAt: Date? = nil,
        serverClockSkew: TimeInterval? = nil,
        confidence: UsageQuotaResetConfidence = .unknown,
        windowIdentity: String? = nil
    ) {
        self.id = id
        self.title = title
        self.remainingPercent = remainingPercent
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.kind = kind
        self.resetSource = resetSource
        self.observedAt = observedAt
        self.serverClockSkew = serverClockSkew
        self.confidence = confidence
        self.windowIdentity = windowIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case remainingPercent
        case usedPercent
        case resetAt
        case kind
        case resetSource
        case observedAt
        case serverClockSkew
        case confidence
        case windowIdentity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        remainingPercent = try container.decode(Double.self, forKey: .remainingPercent)
        usedPercent = try container.decode(Double.self, forKey: .usedPercent)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        kind = try container.decode(UsageQuotaKind.self, forKey: .kind)
        resetSource = try container.decodeIfPresent(UsageQuotaResetSource.self, forKey: .resetSource) ?? .unknown
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        serverClockSkew = try container.decodeIfPresent(TimeInterval.self, forKey: .serverClockSkew)
        confidence = try container.decodeIfPresent(UsageQuotaResetConfidence.self, forKey: .confidence) ?? .unknown
        windowIdentity = try container.decodeIfPresent(String.self, forKey: .windowIdentity)
    }
}

struct UsageSnapshot: Codable, Identifiable, Equatable {
    var id: String { source }
    var source: String
    var status: SnapshotStatus
    var fetchHealth: FetchHealth
    var valueFreshness: ValueFreshness
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
    var updatedAt: Date
    var note: String
    var quotaWindows: [UsageQuotaWindow]
    var sourceLabel: String
    var accountLabel: String?
    var authSourceLabel: String?
    var diagnosticCode: String?
    var extras: [String: String]
    var rawMeta: [String: String]

    init(
        source: String,
        status: SnapshotStatus,
        fetchHealth: FetchHealth = .ok,
        valueFreshness: ValueFreshness = .live,
        remaining: Double?,
        used: Double?,
        limit: Double?,
        unit: String,
        updatedAt: Date,
        note: String,
        quotaWindows: [UsageQuotaWindow] = [],
        sourceLabel: String = "",
        accountLabel: String? = nil,
        authSourceLabel: String? = nil,
        diagnosticCode: String? = nil,
        extras: [String: String] = [:],
        rawMeta: [String: String] = [:]
    ) {
        self.source = source
        self.status = status
        self.fetchHealth = fetchHealth
        self.valueFreshness = valueFreshness
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
        self.updatedAt = updatedAt
        self.note = note
        self.quotaWindows = Self.quotaWindowsWithDefaultResetMetadata(
            quotaWindows,
            source: source,
            sourceLabel: sourceLabel,
            valueFreshness: valueFreshness,
            updatedAt: updatedAt
        )
        self.sourceLabel = sourceLabel
        self.accountLabel = accountLabel
        self.authSourceLabel = authSourceLabel
        self.diagnosticCode = diagnosticCode
        self.extras = extras
        self.rawMeta = rawMeta
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case status
        case fetchHealth
        case valueFreshness
        case remaining
        case used
        case limit
        case unit
        case updatedAt
        case note
        case quotaWindows
        case sourceLabel
        case accountLabel
        case authSourceLabel
        case diagnosticCode
        case extras
        case rawMeta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(SnapshotStatus.self, forKey: .status)
        fetchHealth = try container.decodeIfPresent(FetchHealth.self, forKey: .fetchHealth) ?? .ok
        valueFreshness = try container.decodeIfPresent(ValueFreshness.self, forKey: .valueFreshness) ?? .live
        remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
        used = try container.decodeIfPresent(Double.self, forKey: .used)
        limit = try container.decodeIfPresent(Double.self, forKey: .limit)
        unit = try container.decode(String.self, forKey: .unit)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        note = try container.decode(String.self, forKey: .note)
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
        accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        authSourceLabel = try container.decodeIfPresent(String.self, forKey: .authSourceLabel)
        diagnosticCode = try container.decodeIfPresent(String.self, forKey: .diagnosticCode)
        extras = try container.decodeIfPresent([String: String].self, forKey: .extras) ?? [:]
        rawMeta = try container.decodeIfPresent([String: String].self, forKey: .rawMeta) ?? [:]
        quotaWindows = Self.quotaWindowsWithDefaultResetMetadata(
            try container.decodeIfPresent([UsageQuotaWindow].self, forKey: .quotaWindows) ?? [],
            source: source,
            sourceLabel: sourceLabel,
            valueFreshness: valueFreshness,
            updatedAt: updatedAt
        )
    }

    private static func quotaWindowsWithDefaultResetMetadata(
        _ windows: [UsageQuotaWindow],
        source: String,
        sourceLabel: String,
        valueFreshness: ValueFreshness,
        updatedAt: Date
    ) -> [UsageQuotaWindow] {
        windows.map {
            $0.withDefaultResetMetadata(
                snapshotSource: source,
                sourceLabel: sourceLabel,
                valueFreshness: valueFreshness,
                observedAt: updatedAt
            )
        }
    }
}

extension UsageQuotaWindow {
    func withDefaultResetMetadata(
        snapshotSource: String,
        sourceLabel: String,
        valueFreshness: ValueFreshness,
        observedAt fallbackObservedAt: Date
    ) -> UsageQuotaWindow {
        var copy = self
        if copy.observedAt == nil {
            copy.observedAt = fallbackObservedAt
        }
        if copy.windowIdentity == nil {
            copy.windowIdentity = Self.defaultWindowIdentity(for: copy)
        }
        if copy.resetSource == .unknown {
            copy.resetSource = Self.inferredResetSource(
                snapshotSource: snapshotSource,
                sourceLabel: sourceLabel,
                resetAt: copy.resetAt
            )
        }
        if copy.confidence == .unknown {
            copy.confidence = Self.inferredResetConfidence(
                resetAt: copy.resetAt,
                resetSource: copy.resetSource,
                valueFreshness: valueFreshness
            )
        }
        return copy
    }

    static func defaultWindowIdentity(for window: UsageQuotaWindow) -> String? {
        guard let resetAt = window.resetAt else { return nil }
        return "\(window.kind.rawValue):\(Int(resetAt.timeIntervalSince1970))"
    }

    private static func inferredResetSource(
        snapshotSource: String,
        sourceLabel: String,
        resetAt: Date?
    ) -> UsageQuotaResetSource {
        guard resetAt != nil else { return .unknown }
        let source = snapshotSource.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if label == "api" || source.contains("official") {
            return .official
        }
        if label.contains("web") || label.contains("browser") {
            return .webObserved
        }
        if label.contains("cli") || label.contains("local") {
            return .localEstimate
        }
        return .webObserved
    }

    private static func inferredResetConfidence(
        resetAt: Date?,
        resetSource: UsageQuotaResetSource,
        valueFreshness: ValueFreshness
    ) -> UsageQuotaResetConfidence {
        guard resetAt != nil, valueFreshness == .live else {
            return .stale
        }

        switch resetSource {
        case .official, .userCalibrated:
            return .confirmed
        case .webObserved, .localEstimate:
            return .estimated
        case .unknown:
            return .stale
        }
    }
}

struct RelayDiagnosticSnapshotPreview: Equatable {
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
}

struct RelayDiagnosticResult: Equatable {
    var success: Bool
    var fetchHealth: FetchHealth
    var resolvedAdapterID: String
    var resolvedAuthSource: String?
    var message: String
    var snapshotPreview: RelayDiagnosticSnapshotPreview?
}
