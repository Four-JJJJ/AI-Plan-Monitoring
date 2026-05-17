import Foundation

public enum UsageAnalyticsAggregator {
    private enum TrendBucketGranularity: String {
        case hour
        case day
        case sevenDay
        case month
        case quarter
    }

    private struct TrendBucketPlan {
        var starts: [Date]
        var granularity: TrendBucketGranularity
    }

    public static func snapshot(
        records: [UsageAnalyticsRecord],
        filter: UsageAnalyticsFilter,
        calendar: Calendar,
        now: Date,
        diagnostics: [String]
    ) -> UsageAnalyticsSnapshot {
        let interval = rangeInterval(filter.range, calendar: calendar, now: now)
        let rangeRecords = records.filter { $0.eventAt >= interval.start && $0.eventAt < interval.end }
        let dedupedRangeRecords = deduplicated(rangeRecords)
        let filteredRecords = dedupedRangeRecords.filter { record in
            guard filter.mode == .byModel, let selectedModelID = filter.selectedModelID else {
                return true
            }
            return modelKey(record.modelID) == modelKey(selectedModelID)
        }

        let totals = filteredRecords.reduce(into: UsageMetricTotals()) { partial, record in
            partial.add(record.totals)
        }
        let availableModels = modelOptions(from: dedupedRangeRecords)
        let providerCategories = categoryStats(from: filteredRecords, totalTokens: totals.totalTokens)
        let providerStats = concreteProviderStats(from: filteredRecords, totalTokens: totals.totalTokens)
        let modelStats = concreteModelStats(from: filteredRecords, totalTokens: totals.totalTokens)
        let buckets = trendBuckets(
            from: filteredRecords,
            range: filter.range,
            calendar: calendar,
            now: now
        )

        return UsageAnalyticsSnapshot(
            generatedAt: now,
            filter: filter,
            totals: totals,
            trendBuckets: buckets,
            providerCategoryStats: providerCategories,
            providerStats: providerStats,
            modelStats: modelStats,
            availableModels: availableModels,
            diagnostics: diagnostics
        )
    }

    public static func providerCategory(for record: UsageAnalyticsRecord) -> String {
        if record.source == .ccswitchProxy {
            return "中转代理"
        }
        let appType = record.appType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if appType.contains("claude") {
            return "Claude"
        }
        if appType.contains("codex") || appType.contains("openai") || appType.contains("gpt") {
            return "GPT 官方"
        }
        return "中转代理"
    }

    public static func rangeInterval(
        _ range: UsageAnalyticsRange,
        calendar: Calendar,
        now: Date
    ) -> DateInterval {
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start = calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour
            let end = calendar.date(byAdding: .hour, value: 1, to: currentHour) ?? now
            return DateInterval(start: start, end: end)
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
            return DateInterval(start: start, end: end)
        case .all:
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    private static func deduplicated(_ records: [UsageAnalyticsRecord]) -> [UsageAnalyticsRecord] {
        var selected: [String: UsageAnalyticsRecord] = [:]
        for record in records {
            guard let existing = selected[record.dedupKey] else {
                selected[record.dedupKey] = record
                continue
            }
            if record.source.priority > existing.source.priority {
                selected[record.dedupKey] = record
            }
        }
        return selected.values.sorted { lhs, rhs in
            if lhs.eventAt == rhs.eventAt {
                return lhs.requestID < rhs.requestID
            }
            return lhs.eventAt < rhs.eventAt
        }
    }

    private static func modelOptions(from records: [UsageAnalyticsRecord]) -> [UsageAnalyticsModelOption] {
        var totalsByModel: [String: (title: String, totalTokens: Int)] = [:]
        for record in records {
            let key = modelKey(record.modelID)
            var item = totalsByModel[key] ?? (title: displayValue(record.modelID), totalTokens: 0)
            item.totalTokens += record.totals.totalTokens
            totalsByModel[key] = item
        }
        return totalsByModel.map { key, item in
            UsageAnalyticsModelOption(id: key, title: item.title, totalTokens: item.totalTokens)
        }
        .sorted { lhs, rhs in
            if lhs.totalTokens == rhs.totalTokens {
                return lhs.title < rhs.title
            }
            return lhs.totalTokens > rhs.totalTokens
        }
    }

    private static func categoryStats(
        from records: [UsageAnalyticsRecord],
        totalTokens: Int
    ) -> [UsageProviderCategoryStats] {
        var totalsByCategory: [String: UsageMetricTotals] = [:]
        for record in records {
            totalsByCategory[providerCategory(for: record), default: UsageMetricTotals()].add(record.totals)
        }
        return totalsByCategory.map { key, totals in
            UsageProviderCategoryStats(
                name: key,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: statsSort)
    }

    private static func concreteProviderStats(
        from records: [UsageAnalyticsRecord],
        totalTokens: Int
    ) -> [UsageProviderStats] {
        struct Key: Hashable {
            var providerID: String
            var providerName: String
            var categoryName: String
        }

        var totalsByProvider: [Key: UsageMetricTotals] = [:]
        for record in records {
            let key = Key(
                providerID: record.providerID,
                providerName: record.providerName,
                categoryName: providerCategory(for: record)
            )
            totalsByProvider[key, default: UsageMetricTotals()].add(record.totals)
        }

        return totalsByProvider.map { key, totals in
            UsageProviderStats(
                id: "\(key.categoryName)|\(key.providerID)|\(key.providerName)",
                providerID: key.providerID,
                providerName: key.providerName,
                categoryName: key.categoryName,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: providerSort)
    }

    private static func concreteModelStats(
        from records: [UsageAnalyticsRecord],
        totalTokens: Int
    ) -> [UsageModelStats] {
        struct Group {
            var modelID: String
            var appTypes: Set<String>
            var providerNames: Set<String>
            var totals: UsageMetricTotals
        }

        var groupsByModel: [String: Group] = [:]
        for record in records {
            let key = modelKey(record.modelID)
            var group = groupsByModel[key] ?? Group(
                modelID: displayValue(record.modelID),
                appTypes: [],
                providerNames: [],
                totals: UsageMetricTotals()
            )
            group.appTypes.insert(displayValue(record.appType))
            group.providerNames.insert(displayValue(record.providerName))
            group.totals.add(record.totals)
            groupsByModel[key] = group
        }

        return groupsByModel.map { _, group in
            UsageModelStats(
                modelID: group.modelID,
                appType: summaryValue(group.appTypes, multipleLabel: "mixed"),
                providerName: summaryValue(group.providerNames, multipleLabel: "多个来源"),
                totals: group.totals,
                share: share(tokens: group.totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: modelSort)
    }

    private static func trendBuckets(
        from records: [UsageAnalyticsRecord],
        range: UsageAnalyticsRange,
        calendar: Calendar,
        now: Date
    ) -> [UsageTrendBucket] {
        let plan: TrendBucketPlan
        switch range {
        case .last24Hours:
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            plan = TrendBucketPlan(
                starts: (0..<24).compactMap { calendar.date(byAdding: .hour, value: -(23 - $0), to: currentHour) },
                granularity: .hour
            )
        case .last7Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<7).compactMap { calendar.date(byAdding: .day, value: -(6 - $0), to: today) },
                granularity: .day
            )
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            plan = TrendBucketPlan(
                starts: (0..<30).compactMap { calendar.date(byAdding: .day, value: -(29 - $0), to: today) },
                granularity: .day
            )
        case .all:
            plan = allRangeTrendPlan(from: records, calendar: calendar)
        }

        var recordsByStart: [Date: [UsageAnalyticsRecord]] = [:]
        for record in records {
            let bucketStart = trendBucketStart(
                for: record.eventAt,
                plan: plan,
                calendar: calendar
            )
            if let bucketStart {
                recordsByStart[bucketStart, default: []].append(record)
            }
        }

        return plan.starts.map { start in
            let end = trendBucketEnd(
                for: start,
                granularity: plan.granularity,
                calendar: calendar
            )
            let bucketRecords = recordsByStart[start] ?? []
            let totals = bucketRecords.reduce(into: UsageMetricTotals()) { partial, record in
                partial.add(record.totals)
            }
            return UsageTrendBucket(
                id: "\(plan.granularity.rawValue)-\(Int(start.timeIntervalSince1970))",
                startAt: start,
                endAt: end,
                totals: totals,
                topProviders: breakdown(records: bucketRecords, totalTokens: totals.totalTokens) {
                    $0.providerName
                },
                topModels: breakdown(records: bucketRecords, totalTokens: totals.totalTokens) {
                    modelKey($0.modelID)
                }
            )
        }
    }

    private static func allRangeTrendPlan(
        from records: [UsageAnalyticsRecord],
        calendar: Calendar
    ) -> TrendBucketPlan {
        guard let firstEventAt = records.map(\.eventAt).min(),
              let lastEventAt = records.map(\.eventAt).max() else {
            return TrendBucketPlan(starts: [], granularity: .day)
        }

        let firstDay = calendar.startOfDay(for: firstEventAt)
        let lastDay = calendar.startOfDay(for: lastEventAt)
        let dayCount = max(0, calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0) + 1

        if dayCount <= 180 {
            var starts: [Date] = []
            var cursor = firstDay
            while cursor <= lastDay {
                starts.append(cursor)
                guard let next = calendar.date(byAdding: .day, value: 7, to: cursor),
                      next > cursor else {
                    break
                }
                cursor = next
            }
            return TrendBucketPlan(starts: starts, granularity: .sevenDay)
        }

        let firstMonth = calendar.dateInterval(of: .month, for: firstEventAt)?.start ?? firstDay
        let lastMonth = calendar.dateInterval(of: .month, for: lastEventAt)?.start ?? lastDay
        let monthCount = max(0, calendar.dateComponents([.month], from: firstMonth, to: lastMonth).month ?? 0) + 1
        if monthCount <= 24 {
            return TrendBucketPlan(
                starts: continuousStarts(from: firstMonth, through: lastMonth, component: .month, step: 1, calendar: calendar),
                granularity: .month
            )
        }

        let firstQuarter = quarterStart(for: firstEventAt, calendar: calendar) ?? firstMonth
        let lastQuarter = quarterStart(for: lastEventAt, calendar: calendar) ?? lastMonth
        return TrendBucketPlan(
            starts: continuousStarts(from: firstQuarter, through: lastQuarter, component: .month, step: 3, calendar: calendar),
            granularity: .quarter
        )
    }

    private static func continuousStarts(
        from start: Date,
        through end: Date,
        component: Calendar.Component,
        step: Int,
        calendar: Calendar
    ) -> [Date] {
        var starts: [Date] = []
        var cursor = start
        while cursor <= end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: component, value: step, to: cursor),
                  next > cursor else {
                break
            }
            cursor = next
        }
        return starts
    }

    private static func trendBucketStart(
        for date: Date,
        plan: TrendBucketPlan,
        calendar: Calendar
    ) -> Date? {
        switch plan.granularity {
        case .hour:
            return calendar.dateInterval(of: .hour, for: date)?.start
        case .day:
            return calendar.startOfDay(for: date)
        case .sevenDay:
            guard let firstStart = plan.starts.first else { return nil }
            let recordDay = calendar.startOfDay(for: date)
            let dayOffset = calendar.dateComponents([.day], from: firstStart, to: recordDay).day ?? 0
            guard dayOffset >= 0 else { return nil }
            return calendar.date(byAdding: .day, value: (dayOffset / 7) * 7, to: firstStart)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
        case .quarter:
            return quarterStart(for: date, calendar: calendar)
        }
    }

    private static func trendBucketEnd(
        for start: Date,
        granularity: TrendBucketGranularity,
        calendar: Calendar
    ) -> Date {
        switch granularity {
        case .hour:
            return calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .sevenDay:
            return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .quarter:
            return calendar.date(byAdding: .month, value: 3, to: start) ?? start
        }
    }

    private static func quarterStart(
        for date: Date,
        calendar: Calendar
    ) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year,
              let month = components.month else {
            return nil
        }
        let firstMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: firstMonth,
            day: 1
        ))
    }

    private static func breakdown(
        records: [UsageAnalyticsRecord],
        totalTokens: Int,
        key: (UsageAnalyticsRecord) -> String
    ) -> [UsageAnalyticsBreakdownItem] {
        var totalsByName: [String: UsageMetricTotals] = [:]
        for record in records {
            totalsByName[key(record), default: UsageMetricTotals()].add(record.totals)
        }
        return totalsByName.map { name, totals in
            UsageAnalyticsBreakdownItem(
                name: name,
                totals: totals,
                share: share(tokens: totals.totalTokens, totalTokens: totalTokens)
            )
        }
        .sorted(by: breakdownSort)
        .prefix(5)
        .map { $0 }
    }

    private static func share(tokens: Int, totalTokens: Int) -> Double {
        guard totalTokens > 0 else { return 0 }
        return Double(tokens) / Double(totalTokens)
    }

    private static func modelKey(_ value: String) -> String {
        displayValue(value).lowercased()
    }

    private static func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func summaryValue(_ values: Set<String>, multipleLabel: String) -> String {
        let cleaned = values.map(displayValue).filter { $0 != "unknown" }.sorted()
        if cleaned.count == 1 {
            return cleaned[0]
        }
        if cleaned.isEmpty {
            return "unknown"
        }
        return multipleLabel
    }

    private static func statsSort(lhs: UsageProviderCategoryStats, rhs: UsageProviderCategoryStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func providerSort(lhs: UsageProviderStats, rhs: UsageProviderStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.providerName < rhs.providerName
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func modelSort(lhs: UsageModelStats, rhs: UsageModelStats) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.modelID < rhs.modelID
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }

    private static func breakdownSort(lhs: UsageAnalyticsBreakdownItem, rhs: UsageAnalyticsBreakdownItem) -> Bool {
        if lhs.totals.totalTokens == rhs.totals.totalTokens {
            return lhs.name < rhs.name
        }
        return lhs.totals.totalTokens > rhs.totals.totalTokens
    }
}
