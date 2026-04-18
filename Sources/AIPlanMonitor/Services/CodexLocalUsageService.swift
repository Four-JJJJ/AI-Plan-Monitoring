import Foundation
import SQLite3

enum CodexTrendScope: String, CaseIterable, Identifiable, Sendable {
    case currentAccount
    case allAccounts

    var id: String { rawValue }
}

struct CodexTrendIdentityContext: Equatable, Sendable {
    var accountID: String?
    var email: String?
    var identityKey: String?

    init(accountID: String?, email: String?, identityKey: String? = nil) {
        self.accountID = Self.normalizedAccountID(accountID)
        self.email = Self.trimmed(email)?.lowercased()
        self.identityKey = Self.trimmed(identityKey)?.lowercased()
    }

    var cacheIdentity: String {
        identityKey ?? accountID ?? email ?? "unknown"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedAccountID(_ value: String?) -> String? {
        guard var accountID = trimmed(value)?.lowercased() else { return nil }
        if accountID.hasPrefix("tenant:account:") {
            accountID = String(accountID.dropFirst("tenant:account:".count))
        }
        if accountID.hasPrefix("account:") {
            accountID = String(accountID.dropFirst("account:".count))
        }
        return trimmed(accountID)
    }
}

struct CodexLocalUsageTrendPoint: Equatable, Identifiable, Sendable {
    var id: String
    var startAt: Date
    var totalTokens: Int
    var responses: Int
}

struct CodexLocalUsageModelBreakdown: Equatable, Identifiable, Sendable {
    var id: String { modelID }
    var modelID: String
    var totalTokens: Int
    var responses: Int
}

struct CodexLocalUsagePeriodSummary: Equatable, Sendable {
    var totalTokens: Int
    var responses: Int
    var byModel: [CodexLocalUsageModelBreakdown]

    static let empty = CodexLocalUsagePeriodSummary(totalTokens: 0, responses: 0, byModel: [])
}

enum CodexLocalUsageDiagnosticsSource: String, Sendable {
    case strict
    case sessions
    case approximate
}

struct CodexLocalUsageDiagnostics: Equatable, Sendable {
    var matchedRows: Int
    var parsedEvents: Int
    var attributableEvents: Int
    var latestEventAt: Date?
    var source: CodexLocalUsageDiagnosticsSource
}

struct CodexLocalUsageSummary: Equatable, Sendable {
    var today: CodexLocalUsagePeriodSummary
    var yesterday: CodexLocalUsagePeriodSummary
    var last30Days: CodexLocalUsagePeriodSummary
    var hourly24: [CodexLocalUsageTrendPoint]
    var daily7: [CodexLocalUsageTrendPoint]
    var databasePath: String
    var generatedAt: Date
    var diagnostics: CodexLocalUsageDiagnostics?
}

enum CodexLocalUsageServiceError: LocalizedError, Equatable {
    case databaseNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "Codex logs database not found: \(path)"
        }
    }
}

final class CodexLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let maxRowCount: Int

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        maxRowCount: Int = 60_000,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.maxRowCount = max(100, maxRowCount)
    }

    func fetchSummary(
        databasePath: String? = nil,
        sessionsRootPath: String? = nil,
        archivedSessionsRootPath: String? = nil,
        scope: CodexTrendScope = .allAccounts,
        currentIdentity: CodexTrendIdentityContext? = nil
    ) throws -> CodexLocalUsageSummary {
        let logsPath = resolvedDatabasePath(explicitPath: databasePath)

        let now = nowProvider()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOf7Days = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        let startOfLast30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfYesterday
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let startOf24Hours = calendar.date(byAdding: .hour, value: -23, to: startOfCurrentHour) ?? startOfCurrentHour

        let events: [ParsedTokenEvent]
        var diagnostics: CodexLocalUsageDiagnostics?
        switch scope {
        case .allAccounts:
            let sessionRoots = resolvedSessionRoots(
                explicitRoot: sessionsRootPath,
                explicitArchivedRoot: archivedSessionsRootPath
            )
            events = scanSessionTokenEvents(
                sessionRoots: sessionRoots,
                startOfLast30Days: startOfLast30Days
            )
            diagnostics = CodexLocalUsageDiagnostics(
                matchedRows: events.count,
                parsedEvents: events.count,
                attributableEvents: 0,
                latestEventAt: events.map(\.eventAt).max(),
                source: .sessions
            )
        case .currentAccount:
            guard fileManager.fileExists(atPath: logsPath) else {
                throw CodexLocalUsageServiceError.databaseNotFound(logsPath)
            }
            let scanResult = scanIdentityLogEvents(
                databasePath: logsPath,
                startOfLast30Days: startOfLast30Days
            )
            events = scanResult.events
            diagnostics = scanResult.diagnostics
        }

        var todayAccumulator = PeriodAccumulator()
        var yesterdayAccumulator = PeriodAccumulator()
        var last30Accumulator = PeriodAccumulator()
        var hourly24Buckets: [Date: PeriodAccumulator] = [:]
        var daily7Buckets: [Date: PeriodAccumulator] = [:]
        var attributableEvents = 0
        var latestAttributableEventAt: Date?

        for event in events {
            if event.eventAt < startOfLast30Days {
                continue
            }
            guard Self.shouldInclude(event: event, scope: scope, currentIdentity: currentIdentity) else {
                continue
            }

            attributableEvents += 1
            if latestAttributableEventAt == nil || event.eventAt > (latestAttributableEventAt ?? .distantPast) {
                latestAttributableEventAt = event.eventAt
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

        let hourly24 = buildHourlyTrendPoints(
            buckets: hourly24Buckets,
            startOfCurrentHour: startOfCurrentHour
        )
        let daily7 = buildDailyTrendPoints(
            buckets: daily7Buckets,
            startOfToday: startOfToday
        )

        if var value = diagnostics {
            value.attributableEvents = attributableEvents
            value.latestEventAt = latestAttributableEventAt ?? value.latestEventAt
            diagnostics = value
        }

        return CodexLocalUsageSummary(
            today: todayAccumulator.summary,
            yesterday: yesterdayAccumulator.summary,
            last30Days: last30Accumulator.summary,
            hourly24: hourly24,
            daily7: daily7,
            databasePath: logsPath,
            generatedAt: now,
            diagnostics: diagnostics
        )
    }

    private func resolvedSessionRoots(explicitRoot: String?, explicitArchivedRoot: String?) -> [String] {
        if let explicitRoot {
            var roots = [explicitRoot]
            if let explicitArchivedRoot {
                roots.append(explicitArchivedRoot)
            }
            return roots
        }

        let codexRoot = "\(NSHomeDirectory())/.codex"
        return [
            "\(codexRoot)/sessions",
            "\(codexRoot)/archived_sessions"
        ]
    }

    private func scanSessionTokenEvents(
        sessionRoots: [String],
        startOfLast30Days: Date
    ) -> [ParsedTokenEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: startOfLast30Days) ?? startOfLast30Days
        let files = sessionJSONLFilePaths(roots: sessionRoots, cutoff: cutoff)
        if files.isEmpty {
            return []
        }

        var events: [ParsedTokenEvent] = []
        events.reserveCapacity(1024)
        for filePath in files {
            parseSessionTokenEvents(filePath: filePath, startOfLast30Days: startOfLast30Days, output: &events)
        }
        return events
    }

    private func sessionJSONLFilePaths(roots: [String], cutoff: Date) -> [String] {
        var output: [String] = []
        for root in roots {
            guard fileManager.fileExists(atPath: root),
                  let enumerator = fileManager.enumerator(
                    at: URL(fileURLWithPath: root, isDirectory: true),
                    includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "jsonl" else {
                    continue
                }
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else {
                    continue
                }

                if let modifiedAt = values.contentModificationDate, modifiedAt < cutoff {
                    continue
                }
                output.append(fileURL.path)
            }
        }
        return output.sorted()
    }

    private func parseSessionTokenEvents(
        filePath: String,
        startOfLast30Days: Date,
        output: inout [ParsedTokenEvent]
    ) {
        var state = SessionTokenScannerState()

        Self.scanJSONLLines(atPath: filePath) { line in
            guard line.contains("\"type\":\"") else {
                return
            }
            let isEventMsg = line.contains("\"type\":\"event_msg\"")
            let isTurnContext = line.contains("\"type\":\"turn_context\"")
            let isSessionMeta = line.contains("\"type\":\"session_meta\"")
            guard isEventMsg || isTurnContext || isSessionMeta else {
                return
            }
            if isEventMsg, !line.contains("\"token_count\"") {
                return
            }

            guard let data = line.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = object["type"] as? String else {
                return
            }

            if type == "session_meta" {
                return
            }

            if type == "turn_context" {
                let payload = object["payload"] as? [String: Any]
                let info = payload?["info"] as? [String: Any]
                state.currentModel = Self.normalizedModelID(
                    Self.stringValue(payload?["model"])
                        ?? Self.stringValue(info?["model"])
                )
                return
            }

            guard type == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  Self.stringValue(payload["type"]) == "token_count",
                  let timestampText = Self.stringValue(object["timestamp"]),
                  let eventAt = Self.parseISODate(timestampText) else {
                return
            }

            let info = payload["info"] as? [String: Any]
            let model = Self.normalizedModelID(
                Self.stringValue(info?["model"])
                    ?? Self.stringValue(info?["model_name"])
                    ?? Self.stringValue(payload["model"])
                    ?? state.currentModel
            )

            var deltaTokens = 0
            if let totalUsage = info?["total_token_usage"] as? [String: Any],
               let snapshotTotal = Self.sessionTokenTotal(from: totalUsage) {
                let signature = "T|\(timestampText)|\(snapshotTotal)"
                guard state.seenTokenSnapshots.insert(signature).inserted else {
                    return
                }

                if snapshotTotal >= state.previousTotalTokens {
                    deltaTokens = snapshotTotal - state.previousTotalTokens
                } else {
                    deltaTokens = 0
                }
                state.previousTotalTokens = snapshotTotal
            } else if let lastUsage = info?["last_token_usage"] as? [String: Any],
                      let lastTokens = Self.sessionTokenTotal(from: lastUsage) {
                let signature = "L|\(timestampText)|\(lastTokens)"
                guard state.seenTokenSnapshots.insert(signature).inserted else {
                    return
                }

                deltaTokens = max(0, lastTokens)
                state.previousTotalTokens += deltaTokens
            } else {
                return
            }

            guard deltaTokens > 0 else {
                return
            }
            guard eventAt >= startOfLast30Days else {
                return
            }

            output.append(
                ParsedTokenEvent(
                    signature: "session|\(filePath)|\(timestampText)|\(deltaTokens)|\(model)",
                    eventAt: eventAt,
                    modelID: model,
                    totalTokens: deltaTokens,
                    accountID: nil,
                    email: nil
                )
            )
        }
    }

    private func scanIdentityLogEvents(
        databasePath: String,
        startOfLast30Days: Date
    ) -> IdentityLogScanResult {
        let startEpoch = Int64(startOfLast30Days.timeIntervalSince1970)
        let query = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE ts IS NOT NULL
          AND ts >= ?
          AND feedback_log_body IS NOT NULL
          AND (
            ltrim(feedback_log_body) LIKE 'event.name=codex.sse_event%'
            OR ltrim(feedback_log_body) LIKE 'event.name="codex.sse_event"%'
          )
          AND (
            feedback_log_body LIKE '%event.kind=response.completed%'
            OR feedback_log_body LIKE '%event.kind="response.completed"%'
          )
        ORDER BY ts DESC
        LIMIT ?;
        """

        var database: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            return IdentityLogScanResult(
                events: [],
                diagnostics: CodexLocalUsageDiagnostics(
                    matchedRows: 0,
                    parsedEvents: 0,
                    attributableEvents: 0,
                    latestEventAt: nil,
                    source: .strict
                )
            )
        }
        defer {
            sqlite3_close(database)
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return IdentityLogScanResult(
                events: [],
                diagnostics: CodexLocalUsageDiagnostics(
                    matchedRows: 0,
                    parsedEvents: 0,
                    attributableEvents: 0,
                    latestEventAt: nil,
                    source: .strict
                )
            )
        }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, startEpoch)
        sqlite3_bind_int(statement, 2, Int32(maxRowCount))

        var dedupedEvents: [String: ParsedTokenEvent] = [:]
        var matchedRows = 0
        var parsedEvents = 0
        var latestParsedEventAt: Date?

        while true {
            let stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else {
                break
            }

            matchedRows += 1

            guard let timestampText = Self.sqliteColumnText(statement, index: 0),
                  let rowEventAt = Self.parseTimestampDate(timestampText),
                  let body = Self.sqliteColumnText(statement, index: 1) else {
                continue
            }
            if rowEventAt < startOfLast30Days {
                break
            }
            guard Self.containsTokenSignal(body) else {
                continue
            }

            guard var event = Self.parseCompletedEvent(from: body, fallbackEventAt: rowEventAt) else {
                continue
            }
            parsedEvents += 1
            if event.eventAt < startOfLast30Days {
                continue
            }
            if latestParsedEventAt == nil || event.eventAt > (latestParsedEventAt ?? .distantPast) {
                latestParsedEventAt = event.eventAt
            }

            if let existing = dedupedEvents[event.signature] {
                if existing.totalTokens == event.totalTokens {
                    dedupedEvents[event.signature] = existing.mergedIdentity(with: event)
                    continue
                }
                event.signature += "#tok=\(event.totalTokens)"
            }

            if let existing = dedupedEvents[event.signature],
               existing.totalTokens == event.totalTokens {
                dedupedEvents[event.signature] = existing.mergedIdentity(with: event)
            } else {
                dedupedEvents[event.signature] = event
            }
        }

        return IdentityLogScanResult(
            events: Array(dedupedEvents.values),
            diagnostics: CodexLocalUsageDiagnostics(
                matchedRows: matchedRows,
                parsedEvents: parsedEvents,
                attributableEvents: 0,
                latestEventAt: latestParsedEventAt,
                source: .strict
            )
        )
    }

    private static func shouldInclude(
        event: ParsedTokenEvent,
        scope: CodexTrendScope,
        currentIdentity: CodexTrendIdentityContext?
    ) -> Bool {
        guard scope == .currentAccount else { return true }
        guard let currentIdentity else { return false }

        if let expectedAccountID = currentIdentity.accountID {
            if let eventAccountID = event.accountID {
                if eventAccountID == expectedAccountID {
                    return true
                }
                // Some Codex logs emit a stable account_id that differs from the UI-selected identity,
                // but still carry a trustworthy email. Fall back to email in this case.
                if let expectedEmail = currentIdentity.email {
                    return event.email == expectedEmail
                }
                return false
            }
            if let expectedEmail = currentIdentity.email {
                return event.email == expectedEmail
            }
            return false
        }

        if let expectedEmail = currentIdentity.email {
            return event.email == expectedEmail
        }

        return false
    }

    private func resolvedDatabasePath(explicitPath: String?) -> String {
        if let explicitPath {
            return explicitPath
        }
        return "\(NSHomeDirectory())/.codex/logs_2.sqlite"
    }

    private static func parseCompletedEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        let firstNonWhitespace = body.unicodeScalars.first {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        if firstNonWhitespace == "{" || firstNonWhitespace == "[" {
            if let event = parseCompletedJSONEvent(from: body, fallbackEventAt: fallbackEventAt) {
                return event
            }
            return parseCompletedLogfmtEvent(from: body, fallbackEventAt: fallbackEventAt)
        }
        return parseCompletedLogfmtEvent(from: body, fallbackEventAt: fallbackEventAt)
    }

    private static func containsTokenSignal(_ body: String) -> Bool {
        body.contains("input_token_count")
            || body.contains("output_token_count")
            || body.contains("cached_token_count")
            || body.contains("reasoning_token_count")
            || body.contains("tool_token_count")
            || body.contains("total_tokens")
            || body.contains("total_token_count")
            || body.contains("input_tokens")
            || body.contains("output_tokens")
            || body.contains("cached_tokens")
            || body.contains("\"usage\"")
    }

    private static func parseCompletedJSONEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        guard let data = body.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let event = root["event"] as? [String: Any]
        let eventName = stringValue(event?["name"])
            ?? stringValue(root["event_name"])
            ?? stringValue(root["name"])
        let eventKind = stringValue(event?["kind"])
            ?? stringValue(root["event_kind"])
            ?? stringValue(root["kind"])
        guard eventName == "codex.sse_event", eventKind == "response.completed" else {
            return nil
        }

        let tokenContainers: [[String: Any]] = [
            event,
            (event?["usage"] as? [String: Any]),
            root,
            (root["usage"] as? [String: Any]),
            ((event?["response"] as? [String: Any])?["usage"] as? [String: Any]),
            ((root["response"] as? [String: Any])?["usage"] as? [String: Any])
        ].compactMap { $0 }

        var totalTokens = 0
        for container in tokenContainers {
            let sum = tokenCount(from: container)
            if sum > 0 {
                totalTokens = sum
                break
            }
        }
        guard totalTokens > 0 else { return nil }

        let response = event?["response"] as? [String: Any]
        let rootResponse = root["response"] as? [String: Any]
        let rootUser = root["user"] as? [String: Any]
        let eventUser = event?["user"] as? [String: Any]
        let modelID = normalizedModelID(
            stringValue(event?["model"])
                ?? stringValue(response?["model"])
                ?? stringValue(root["model"])
                ?? stringValue(rootResponse?["model"])
        )
        let eventAt = parseISODate(
            stringValue(event?["timestamp"])
                ?? stringValue(root["event.timestamp"])
                ?? stringValue(root["timestamp"])
                ?? stringValue(root["event_timestamp"])
        ) ?? fallbackEventAt
        let accountID = normalizedAccountID(
            stringValue(eventUser?["account_id"])
                ?? stringValue(eventUser?["accountId"])
                ?? stringValue(rootUser?["account_id"])
                ?? stringValue(rootUser?["accountId"])
                ?? stringValue(root["user.account_id"])
                ?? stringValue(root["account_id"])
                ?? stringValue(root["accountId"])
        )
        let email = normalizedEmail(
            stringValue(eventUser?["email"])
                ?? stringValue(rootUser?["email"])
                ?? stringValue(root["user.email"])
                ?? stringValue(root["email"])
        )

        let signature = buildSignature(
            source: "json",
            responseID: stringValue(response?["id"]) ?? stringValue(rootResponse?["id"]) ?? stringValue(root["response_id"]),
            conversationID: stringValue((root["conversation"] as? [String: Any])?["id"]) ?? stringValue(root["conversation.id"]) ?? stringValue(root["conversation_id"]),
            threadID: stringValue((root["thread"] as? [String: Any])?["id"]) ?? stringValue(root["thread.id"]) ?? stringValue(root["thread_id"]),
            turnID: stringValue((root["turn"] as? [String: Any])?["id"]) ?? stringValue(root["turn.id"]) ?? stringValue(root["turn_id"]),
            submissionID: stringValue((root["submission"] as? [String: Any])?["id"]) ?? stringValue(root["submission.id"]) ?? stringValue(root["submission_id"]),
            eventTimestamp: stringValue(event?["timestamp"]) ?? stringValue(root["event.timestamp"]) ?? stringValue(root["event_timestamp"]),
            modelID: modelID,
            totalTokens: totalTokens,
            fallbackEventAt: eventAt,
            fallbackBody: body
        )

        return ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            accountID: accountID,
            email: email
        )
    }

    private static func parseCompletedLogfmtEvent(from body: String, fallbackEventAt: Date) -> ParsedTokenEvent? {
        let fields = parseLogfmtFields(body)
        let eventName = normalizedIdentityField(fields["event.name"])
        let eventKind = normalizedIdentityField(fields["event.kind"])
        guard eventName == "codex.sse_event", eventKind == "response.completed" else {
            return nil
        }

        let totalTokens = tokenCount(from: fields)
        guard totalTokens > 0 else {
            return nil
        }

        let modelID = normalizedModelID(fields["model"] ?? fields["slug"])

        let eventAt = parseISODate(fields["event.timestamp"]) ?? fallbackEventAt
        let accountID = normalizedAccountID(
            fields["user.account_id"]
                ?? fields["user.accountId"]
                ?? fields["account_id"]
                ?? fields["accountId"]
        )
        let email = normalizedEmail(fields["user.email"] ?? fields["email"])

        let signature = buildSignature(
            source: "logfmt",
            responseID: fields["response.id"] ?? fields["event.id"],
            conversationID: fields["conversation.id"],
            threadID: fields["thread.id"],
            turnID: fields["turn.id"],
            submissionID: fields["submission.id"],
            eventTimestamp: fields["event.timestamp"],
            modelID: modelID,
            totalTokens: totalTokens,
            fallbackEventAt: eventAt,
            fallbackBody: body
        )

        return ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            accountID: accountID,
            email: email
        )
    }

    private static func buildSignature(
        source: String,
        responseID: String?,
        conversationID: String?,
        threadID: String?,
        turnID: String?,
        submissionID: String?,
        eventTimestamp: String?,
        modelID: String,
        totalTokens: Int,
        fallbackEventAt: Date,
        fallbackBody: String
    ) -> String {
        var components: [String] = ["source=\(source)"]

        if let responseID = trimmed(responseID) {
            components.append("response=\(responseID)")
        }
        if let conversationID = trimmed(conversationID) {
            components.append("conversation=\(conversationID)")
        }
        if let threadID = trimmed(threadID) {
            components.append("thread=\(threadID)")
        }
        if let turnID = trimmed(turnID) {
            components.append("turn=\(turnID)")
        }
        if let submissionID = trimmed(submissionID) {
            components.append("submission=\(submissionID)")
        }
        if let eventTimestamp = trimmed(eventTimestamp) {
            components.append("eventAt=\(eventTimestamp)")
        } else {
            components.append("eventAt=\(Int(fallbackEventAt.timeIntervalSince1970))")
        }

        components.append("model=\(modelID)")
        components.append("tokens=\(totalTokens)")

        if components.count <= 4 {
            components.append("hash=\(stableHash(of: fallbackBody))")
        }

        return components.joined(separator: "|")
    }

    private static func stableHash(of text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func parseLogfmtFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        fields.reserveCapacity(32)

        let scalars = Array(text.unicodeScalars)
        var index = 0

        func isWhitespace(_ scalar: UnicodeScalar) -> Bool {
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        while index < scalars.count {
            while index < scalars.count, isWhitespace(scalars[index]) {
                index += 1
            }
            guard index < scalars.count else { break }

            let keyStart = index
            while index < scalars.count,
                  !isWhitespace(scalars[index]),
                  scalars[index] != "=" {
                index += 1
            }

            guard index < scalars.count, scalars[index] == "=" else {
                while index < scalars.count, !isWhitespace(scalars[index]) {
                    index += 1
                }
                continue
            }

            let key = String(String.UnicodeScalarView(scalars[keyStart..<index]))
            index += 1
            if key.isEmpty {
                continue
            }

            var value = ""
            if index < scalars.count, scalars[index] == "\"" {
                index += 1
                var escaped = false
                while index < scalars.count {
                    let scalar = scalars[index]
                    index += 1
                    if escaped {
                        value.unicodeScalars.append(scalar)
                        escaped = false
                        continue
                    }
                    if scalar == "\\" {
                        escaped = true
                        continue
                    }
                    if scalar == "\"" {
                        break
                    }
                    value.unicodeScalars.append(scalar)
                }
                if escaped {
                    value.append("\\")
                }
            } else {
                let valueStart = index
                while index < scalars.count, !isWhitespace(scalars[index]) {
                    index += 1
                }
                value = String(String.UnicodeScalarView(scalars[valueStart..<index]))
            }

            if fields[key] == nil {
                fields[key] = value
            }
        }

        return fields
    }

    private static func tokenCount(from container: [String: Any]) -> Int {
        if let total = intValue(container["total_tokens"]) ?? intValue(container["total_token_count"]), total > 0 {
            return total
        }

        let keys = [
            "input_token_count",
            "output_token_count",
            "cached_token_count",
            "reasoning_token_count",
            "tool_token_count",
            "input_tokens",
            "output_tokens",
            "cached_tokens",
            "reasoning_tokens",
            "tool_tokens",
            "reasoning_output_tokens",
            "cached_input_tokens",
            "cache_read_input_tokens"
        ]
        var total = 0
        for key in keys {
            guard let value = intValue(container[key]) else { continue }
            total += max(0, value)
        }
        return total
    }

    private static func tokenCount(from fields: [String: String]) -> Int {
        if let total = intValue(fields["total_tokens"]) ?? intValue(fields["total_token_count"]), total > 0 {
            return total
        }

        let keys = [
            "input_token_count",
            "output_token_count",
            "cached_token_count",
            "reasoning_token_count",
            "tool_token_count",
            "input_tokens",
            "output_tokens",
            "cached_tokens",
            "reasoning_tokens",
            "tool_tokens",
            "reasoning_output_tokens",
            "cached_input_tokens",
            "cache_read_input_tokens"
        ]

        var total = 0
        for key in keys {
            guard let value = intValue(fields[key]) else { continue }
            total += max(0, value)
        }
        return total
    }

    private static func sessionTokenTotal(from usage: [String: Any]) -> Int? {
        if let total = intValue(usage["total_tokens"]) ?? intValue(usage["total_token_count"]), total >= 0 {
            return total
        }

        let keys = [
            "input_tokens",
            "cached_input_tokens",
            "cache_read_input_tokens",
            "output_tokens",
            "reasoning_output_tokens",
            "tool_tokens"
        ]
        var total = 0
        var hasAny = false
        for key in keys {
            if let value = intValue(usage[key]) {
                total += max(0, value)
                hasAny = true
            }
        }
        return hasAny ? total : nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String {
            return intValue(value)
        }
        return nil
    }

    private static func intValue(_ value: String?) -> Int? {
        guard let value = trimmed(value) else { return nil }
        if let integer = Int(value) { return integer }
        if let double = Double(value) { return Int(double.rounded()) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            return trimmed(value)
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = trimmed(raw) else { return nil }
        if let date = isoFormatterWithFractional.date(from: raw) {
            return date
        }
        return isoFormatterBasic.date(from: raw)
    }

    nonisolated(unsafe) private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func normalizedModelID(_ raw: String?) -> String {
        trimmed(raw) ?? "unknown"
    }

    private static func normalizedAccountID(_ raw: String?) -> String? {
        guard var value = normalizedIdentityField(raw)?.lowercased() else { return nil }
        if value.hasPrefix("tenant:account:") {
            value = String(value.dropFirst("tenant:account:".count))
        }
        if value.hasPrefix("account:") {
            value = String(value.dropFirst("account:".count))
        }
        return trimmed(value)
    }

    private static func normalizedEmail(_ raw: String?) -> String? {
        normalizedIdentityField(raw)?.lowercased()
    }

    private static func normalizedIdentityField(_ raw: String?) -> String? {
        guard var value = trimmed(raw) else { return nil }

        if value.hasPrefix("\\\"") && value.hasSuffix("\\\"") && value.count >= 4 {
            value = String(value.dropFirst(2).dropLast(2))
        }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }

        value = value.replacingOccurrences(of: "\\\"", with: "\"")
        value = value.replacingOccurrences(of: "\\\\", with: "\\")

        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }

        return trimmed(value)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTimestampDate(_ raw: String) -> Date? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        if value > 1_000_000_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000_000_000)
        }
        if value > 1_000_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000_000)
        }
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1_000)
        }
        return Date(timeIntervalSince1970: value)
    }

    private static func sqliteColumnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private static func hexData(from raw: String) -> Data? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count.isMultiple(of: 2) else { return nil }

        var output = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteString = String(normalized[index..<nextIndex])
            guard let value = UInt8(byteString, radix: 16) else { return nil }
            output.append(value)
            index = nextIndex
        }
        return output
    }

    private static func scanJSONLLines(
        atPath path: String,
        maxLineBytes: Int = 512 * 1024,
        onLine: (String) -> Void
    ) {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return
        }
        defer {
            try? handle.close()
        }

        let newline = Data([0x0A])
        var buffer = Data()

        while true {
            let chunk = try? handle.read(upToCount: 64 * 1024)
            guard let chunk else {
                break
            }
            if chunk.isEmpty {
                if !buffer.isEmpty, buffer.count <= maxLineBytes,
                   let line = String(data: buffer, encoding: .utf8) {
                    onLine(line)
                }
                break
            }

            buffer.append(chunk)
            while let range = buffer.range(of: newline) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0..<range.upperBound)

                guard !lineData.isEmpty, lineData.count <= maxLineBytes,
                      let line = String(data: lineData, encoding: .utf8) else {
                    continue
                }
                onLine(line)
            }
        }
    }

    private func buildHourlyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        startOfCurrentHour: Date
    ) -> [CodexLocalUsageTrendPoint] {
        (0..<24).compactMap { offset -> CodexLocalUsageTrendPoint? in
            guard let hourStart = calendar.date(byAdding: .hour, value: -(23 - offset), to: startOfCurrentHour) else {
                return nil
            }
            let accumulator = buckets[hourStart] ?? PeriodAccumulator()
            return CodexLocalUsageTrendPoint(
                id: "h-\(Int(hourStart.timeIntervalSince1970))",
                startAt: hourStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses
            )
        }
    }

    private func buildDailyTrendPoints(
        buckets: [Date: PeriodAccumulator],
        startOfToday: Date
    ) -> [CodexLocalUsageTrendPoint] {
        (0..<7).compactMap { offset -> CodexLocalUsageTrendPoint? in
            guard let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: startOfToday) else {
                return nil
            }
            let accumulator = buckets[dayStart] ?? PeriodAccumulator()
            return CodexLocalUsageTrendPoint(
                id: "d-\(Int(dayStart.timeIntervalSince1970))",
                startAt: dayStart,
                totalTokens: accumulator.totalTokens,
                responses: accumulator.responses
            )
        }
    }
}

private struct SessionTokenScannerState {
    var currentModel: String?
    var previousTotalTokens: Int = 0
    var seenTokenSnapshots: Set<String> = []
}

private struct IdentityLogScanResult {
    var events: [ParsedTokenEvent]
    var diagnostics: CodexLocalUsageDiagnostics
}

private struct ParsedTokenEvent {
    var signature: String
    var eventAt: Date
    var modelID: String
    var totalTokens: Int
    var accountID: String?
    var email: String?

    func mergedIdentity(with other: ParsedTokenEvent) -> ParsedTokenEvent {
        ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            accountID: accountID ?? other.accountID,
            email: email ?? other.email
        )
    }
}

private struct PeriodAccumulator {
    var totalTokens = 0
    var responses = 0
    var byModel: [String: (tokens: Int, responses: Int)] = [:]

    mutating func consume(event: ParsedTokenEvent) {
        totalTokens += event.totalTokens
        responses += 1
        var model = byModel[event.modelID, default: (tokens: 0, responses: 0)]
        model.tokens += event.totalTokens
        model.responses += 1
        byModel[event.modelID] = model
    }

    var summary: CodexLocalUsagePeriodSummary {
        let models = byModel.map { key, value in
            CodexLocalUsageModelBreakdown(
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

        return CodexLocalUsagePeriodSummary(
            totalTokens: totalTokens,
            responses: responses,
            byModel: models
        )
    }
}
