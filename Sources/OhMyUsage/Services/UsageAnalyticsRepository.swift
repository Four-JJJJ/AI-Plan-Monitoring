import Foundation

final class UsageAnalyticsRepository: @unchecked Sendable {
    private let ccSwitchReader: CCSwitchUsageLogReader
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        ccSwitchReader: CCSwitchUsageLogReader = CCSwitchUsageLogReader(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.ccSwitchReader = ccSwitchReader
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func snapshot(
        filter: UsageAnalyticsFilter,
        claudeAllConfigDirs: [String] = []
    ) -> UsageAnalyticsSnapshot {
        let now = nowProvider()
        let readRange: UsageAnalyticsRange = filter.range == .all ? .all : .last30Days
        let interval = UsageAnalyticsAggregator.rangeInterval(readRange, calendar: calendar, now: now)
        var diagnostics: [String] = []
        var records: [UsageAnalyticsRecord] = []

        let ccSwitchResult = ccSwitchReader.readUsageLogs(since: interval.start, until: interval.end)
        records.append(contentsOf: ccSwitchResult.records.map(\.analyticsRecord))
        diagnostics.append(contentsOf: ccSwitchResult.diagnostics)

        let localResult = readLocalRecords(
            since: interval.start,
            claudeAllConfigDirs: claudeAllConfigDirs
        )
        records.append(contentsOf: localResult.records)
        diagnostics.append(contentsOf: localResult.diagnostics)

        return UsageAnalyticsAggregator.snapshot(
            records: records,
            filter: filter,
            calendar: calendar,
            now: now,
            diagnostics: diagnostics
        )
    }

    func sourceFingerprint(claudeAllConfigDirs: [String] = []) -> UsageAnalyticsSourceFingerprint {
        UsageAnalyticsSourceFingerprint(
            ccSwitch: usageAnalyticsFileFingerprint(from: ccSwitchReader.sourceFingerprint()),
            codex: usageAnalyticsFileFingerprint(
                from: LocalUsageSourceFingerprintBuilder.codexFingerprint(scope: .allAccounts)
            ),
            claude: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.claudeFingerprint(
                scope: .allAccounts,
                currentConfigDir: nil,
                allConfigDirs: claudeAllConfigDirs
            )),
            kimi: usageAnalyticsFileFingerprint(from: LocalUsageSourceFingerprintBuilder.kimiFingerprint())
        )
    }

    private func readLocalRecords(
        since: Date,
        claudeAllConfigDirs: [String]
    ) -> (records: [UsageAnalyticsRecord], diagnostics: [String]) {
        var records: [UsageAnalyticsRecord] = []
        var diagnostics: [String] = []

        do {
            let codexEvents = try CodexLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: codexEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "codex",
                    providerID: "ohmyusage-codex-local",
                    providerName: "Codex"
                )
            })
        } catch {
            diagnostics.append("Codex 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let claudeEvents = try ClaudeLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, allConfigDirs: claudeAllConfigDirs, since: since)
            records.append(contentsOf: claudeEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "claude",
                    providerID: "ohmyusage-claude-local",
                    providerName: "Claude"
                )
            })
        } catch {
            diagnostics.append("Claude 本地日志读取失败：\(error.localizedDescription)")
        }

        do {
            let kimiEvents = try KimiLocalUsageService(calendar: calendar, nowProvider: nowProvider)
                .fetchEvents(scope: .allAccounts, since: since)
            records.append(contentsOf: kimiEvents.map {
                analyticsRecord(
                    event: $0,
                    appType: "kimi",
                    providerID: "ohmyusage-kimi-local",
                    providerName: "Kimi"
                )
            })
        } catch {
            diagnostics.append("Kimi 本地日志读取失败：\(error.localizedDescription)")
        }

        return (records, diagnostics)
    }

    private func analyticsRecord(
        event: LocalUsageEvent,
        appType: String,
        providerID: String,
        providerName: String
    ) -> UsageAnalyticsRecord {
        UsageAnalyticsRecord(
            source: .ohMyUsageLocal,
            eventAt: event.eventAt,
            appType: appType,
            providerID: providerID,
            providerName: providerName,
            modelID: event.modelID,
            requestID: event.signature,
            totals: usageTotals(from: event)
        )
    }

    private func usageTotals(from event: LocalUsageEvent) -> UsageMetricTotals {
        let componentTotal = event.inputTokens
            + event.outputTokens
            + event.cacheReadTokens
            + event.cacheWriteTokens
        if componentTotal > 0 {
            return UsageMetricTotals(
                requestCount: 1,
                successCount: 1,
                inputTokens: event.inputTokens,
                outputTokens: event.outputTokens,
                cacheReadTokens: event.cacheReadTokens,
                cacheWriteTokens: event.cacheWriteTokens
            )
        }
        return UsageMetricTotals(
            requestCount: 1,
            successCount: 1,
            outputTokens: event.totalTokens
        )
    }

    private func usageAnalyticsFileFingerprint(
        from fingerprint: LocalUsageSourceFingerprint
    ) -> UsageAnalyticsFileFingerprint {
        UsageAnalyticsFileFingerprint(
            roots: fingerprint.roots,
            fileCount: fingerprint.fileCount,
            totalSize: fingerprint.totalSize,
            latestModificationTime: fingerprint.latestModificationTime
        )
    }
}
