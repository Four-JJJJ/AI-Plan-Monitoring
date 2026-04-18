import Foundation

enum LocalUsageTrendScope: String, CaseIterable, Identifiable, Sendable {
    case currentAccount
    case allAccounts

    var id: String { rawValue }
}

enum LocalUsageTrendDiagnosticsSource: String, Sendable {
    case strict
    case sessions
    case approximate
}

struct LocalUsageTrendDiagnostics: Equatable, Sendable {
    var matchedRows: Int
    var parsedEvents: Int
    var attributableEvents: Int
    var latestEventAt: Date?
    var source: LocalUsageTrendDiagnosticsSource
}

struct LocalUsageTrendPoint: Equatable, Identifiable, Sendable {
    var id: String
    var startAt: Date
    var totalTokens: Int
    var responses: Int
}

struct LocalUsageModelBreakdown: Equatable, Identifiable, Sendable {
    var id: String { modelID }
    var modelID: String
    var totalTokens: Int
    var responses: Int
}

struct LocalUsagePeriodSummary: Equatable, Sendable {
    var totalTokens: Int
    var responses: Int
    var byModel: [LocalUsageModelBreakdown]

    static let empty = LocalUsagePeriodSummary(totalTokens: 0, responses: 0, byModel: [])
}

struct LocalUsageSummary: Equatable, Sendable {
    var today: LocalUsagePeriodSummary
    var yesterday: LocalUsagePeriodSummary
    var last30Days: LocalUsagePeriodSummary
    var hourly24: [LocalUsageTrendPoint]
    var daily7: [LocalUsageTrendPoint]
    var sourcePath: String
    var generatedAt: Date
    var diagnostics: LocalUsageTrendDiagnostics?
    var isApproximateFallback: Bool

    func markedApproximateFallback(using diagnostics: LocalUsageTrendDiagnostics?) -> LocalUsageSummary {
        LocalUsageSummary(
            today: today,
            yesterday: yesterday,
            last30Days: last30Days,
            hourly24: hourly24,
            daily7: daily7,
            sourcePath: sourcePath,
            generatedAt: generatedAt,
            diagnostics: diagnostics ?? self.diagnostics,
            isApproximateFallback: true
        )
    }
}

struct LocalUsageEvent: Equatable, Sendable {
    var signature: String
    var eventAt: Date
    var modelID: String
    var totalTokens: Int
}

enum LocalUsageSummaryBuilder {
    static func build(
        events: [LocalUsageEvent],
        calendar: Calendar,
        now: Date,
        sourcePath: String
    ) -> LocalUsageSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfYesterday
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let startOf24Hours = calendar.date(byAdding: .hour, value: -23, to: startOfCurrentHour) ?? startOfCurrentHour

        var todayAccumulator = PeriodAccumulator()
        var yesterdayAccumulator = PeriodAccumulator()
        var last30Accumulator = PeriodAccumulator()
        var hourly24Buckets: [Date: PeriodAccumulator] = [:]
        var daily7Buckets: [Date: PeriodAccumulator] = [:]

        for event in events {
            guard event.eventAt >= startOfLast30Days else {
                continue
            }

            last30Accumulator.consume(event: event)
            if event.eventAt >= startOfToday {
                todayAccumulator.consume(event: event)
            } else if event.eventAt >= startOfYesterday {
                yesterdayAccumulator.consume(event: event)
            }

            if event.eventAt >= startOf24Hours,
               let hourStart = calendar.dateInterval(of: .hour, for: event.eventAt)?.start {
                var accumulator = hourly24Buckets[hourStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                hourly24Buckets[hourStart] = accumulator
            }

            if event.eventAt >= startOf7Days {
                let dayStart = calendar.startOfDay(for: event.eventAt)
                var accumulator = daily7Buckets[dayStart, default: PeriodAccumulator()]
                accumulator.consume(event: event)
                daily7Buckets[dayStart] = accumulator
            }
        }

        return LocalUsageSummary(
            today: todayAccumulator.summary,
            yesterday: yesterdayAccumulator.summary,
            last30Days: last30Accumulator.summary,
            hourly24: buildHourlyTrendPoints(
                buckets: hourly24Buckets,
                calendar: calendar,
                startOfCurrentHour: startOfCurrentHour
            ),
            daily7: buildDailyTrendPoints(
                buckets: daily7Buckets,
                calendar: calendar,
                startOfToday: startOfToday
            ),
            sourcePath: sourcePath,
            generatedAt: now,
            diagnostics: nil,
            isApproximateFallback: false
        )
    }

    private static func buildHourlyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        calendar: Calendar,
        startOfCurrentHour: Date
    ) -> [LocalUsageTrendPoint] {
        (0..<24).compactMap { offset -> LocalUsageTrendPoint? in
            guard let hourStart = calendar.date(byAdding: .hour, value: -(23 - offset), to: startOfCurrentHour) else {
                return nil
            }
            let accumulator = buckets[hourStart] ?? PeriodAccumulator()
            return LocalUsageTrendPoint(
                id: "h-\(Int(hourStart.timeIntervalSince1970))",
                startAt: hourStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses
            )
        }
    }

    private static func buildDailyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        calendar: Calendar,
        startOfToday: Date
    ) -> [LocalUsageTrendPoint] {
        (0..<7).compactMap { offset -> LocalUsageTrendPoint? in
            guard let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday) else {
                return nil
            }
            let accumulator = buckets[dayStart] ?? PeriodAccumulator()
            return LocalUsageTrendPoint(
                id: "d-\(Int(dayStart.timeIntervalSince1970))",
                startAt: dayStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses
            )
        }
    }
}

extension LocalUsageSummary {
    init(codex summary: CodexLocalUsageSummary) {
        self.today = LocalUsagePeriodSummary(codex: summary.today)
        self.yesterday = LocalUsagePeriodSummary(codex: summary.yesterday)
        self.last30Days = LocalUsagePeriodSummary(codex: summary.last30Days)
        self.hourly24 = summary.hourly24.map(LocalUsageTrendPoint.init(codex:))
        self.daily7 = summary.daily7.map(LocalUsageTrendPoint.init(codex:))
        self.sourcePath = summary.databasePath
        self.generatedAt = summary.generatedAt
        self.diagnostics = summary.diagnostics.map(LocalUsageTrendDiagnostics.init(codex:))
        self.isApproximateFallback = false
    }
}

private extension LocalUsageTrendPoint {
    init(codex point: CodexLocalUsageTrendPoint) {
        self.init(
            id: point.id,
            startAt: point.startAt,
            totalTokens: point.totalTokens,
            responses: point.responses
        )
    }
}

private extension LocalUsagePeriodSummary {
    init(codex summary: CodexLocalUsagePeriodSummary) {
        self.init(
            totalTokens: summary.totalTokens,
            responses: summary.responses,
            byModel: summary.byModel.map(LocalUsageModelBreakdown.init(codex:))
        )
    }
}

private extension LocalUsageModelBreakdown {
    init(codex value: CodexLocalUsageModelBreakdown) {
        self.init(
            modelID: value.modelID,
            totalTokens: value.totalTokens,
            responses: value.responses
        )
    }
}

private extension LocalUsageTrendDiagnostics {
    init(codex value: CodexLocalUsageDiagnostics) {
        self.init(
            matchedRows: value.matchedRows,
            parsedEvents: value.parsedEvents,
            attributableEvents: value.attributableEvents,
            latestEventAt: value.latestEventAt,
            source: LocalUsageTrendDiagnosticsSource(codex: value.source)
        )
    }
}

private extension LocalUsageTrendDiagnosticsSource {
    init(codex source: CodexLocalUsageDiagnosticsSource) {
        switch source {
        case .strict:
            self = .strict
        case .sessions:
            self = .sessions
        case .approximate:
            self = .approximate
        }
    }
}

private struct PeriodAccumulator {
    var totalTokens = 0
    var responses = 0
    var byModel: [String: (tokens: Int, responses: Int)] = [:]

    mutating func consume(event: LocalUsageEvent) {
        totalTokens += event.totalTokens
        responses += 1
        var model = byModel[event.modelID, default: (tokens: 0, responses: 0)]
        model.tokens += event.totalTokens
        model.responses += 1
        byModel[event.modelID] = model
    }

    var summary: LocalUsagePeriodSummary {
        let models = byModel.map { key, value in
            LocalUsageModelBreakdown(
                modelID: key,
                totalTokens: value.tokens,
                responses: value.responses
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                if lhs.responses == rhs.responses {
                    return lhs.modelID < rhs.modelID
                }
                return lhs.responses > rhs.responses
            }
            return lhs.totalTokens > rhs.totalTokens
        }

        return LocalUsagePeriodSummary(
            totalTokens: totalTokens,
            responses: responses,
            byModel: models
        )
    }
}
