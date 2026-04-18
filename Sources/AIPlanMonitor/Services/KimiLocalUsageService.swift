import Foundation

final class KimiLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let defaultSessionsRootPath: String?

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        defaultSessionsRootPath: String? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.defaultSessionsRootPath = defaultSessionsRootPath
    }

    func fetchSummary(
        scope: LocalUsageTrendScope = .allAccounts,
        sessionsRootPath: String? = nil
    ) throws -> LocalUsageSummary {
        _ = scope // v1: Kimi 仅支持全部账号，当前账号按全部账号处理。

        let sessionsRoot = resolvedSessionsRoot(explicitPath: sessionsRootPath)
        let now = nowProvider()
        let startOfLast30Days = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let events = scanSessionEvents(
            sessionsRoot: sessionsRoot,
            startOfLast30Days: startOfLast30Days
        )

        return LocalUsageSummaryBuilder.build(
            events: events,
            calendar: calendar,
            now: now,
            sourcePath: sessionsRoot
        )
    }

    private func resolvedSessionsRoot(explicitPath: String?) -> String {
        if let explicitPath {
            return explicitPath
        }
        if let defaultSessionsRootPath {
            return defaultSessionsRootPath
        }
        return "\(NSHomeDirectory())/.kimi/sessions"
    }

    private func scanSessionEvents(
        sessionsRoot: String,
        startOfLast30Days: Date
    ) -> [LocalUsageEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: startOfLast30Days) ?? startOfLast30Days
        let files = wireJSONLFilePaths(root: sessionsRoot, cutoff: cutoff)
        if files.isEmpty {
            return []
        }

        var output: [LocalUsageEvent] = []
        output.reserveCapacity(2048)

        for filePath in files {
            parseWireFile(
                filePath: filePath,
                startOfLast30Days: startOfLast30Days,
                output: &output
            )
        }

        return output
    }

    private func wireJSONLFilePaths(root: String, cutoff: Date) -> [String] {
        guard fileManager.fileExists(atPath: root),
              let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root, isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        var files: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "wire.jsonl" else {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            if let modifiedAt = values.contentModificationDate, modifiedAt < cutoff {
                continue
            }
            files.append(fileURL.path)
        }

        return files.sorted()
    }

    private func parseWireFile(
        filePath: String,
        startOfLast30Days: Date,
        output: inout [LocalUsageEvent]
    ) {
        let sessionID = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .lastPathComponent
        var previousSnapshotTokens = 0
        var seenSnapshots: Set<String> = []

        scanJSONLLines(atPath: filePath) { line in
            guard line.contains("\"StatusUpdate\""), line.contains("\"token_usage\"") else {
                return
            }

            guard let data = line.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let eventAt = Self.parseTimestampDate(root["timestamp"]),
                  eventAt >= startOfLast30Days,
                  let message = root["message"] as? [String: Any],
                  Self.stringValue(message["type"]) == "StatusUpdate",
                  let payload = message["payload"] as? [String: Any],
                  let usage = payload["token_usage"] as? [String: Any] else {
                return
            }

            let snapshotTotal = Self.tokenCount(from: usage)
            guard snapshotTotal > 0 else {
                return
            }

            let snapshotSignature = "\(sessionID)|\(root["timestamp"] ?? "")|\(snapshotTotal)"
            guard seenSnapshots.insert(snapshotSignature).inserted else {
                return
            }

            let delta = max(0, snapshotTotal - previousSnapshotTokens)
            previousSnapshotTokens = snapshotTotal
            guard delta > 0 else {
                return
            }

            let modelID = Self.stringValue(payload["model"])
                ?? Self.stringValue(message["model"])
                ?? "unknown"
            let messageID = Self.stringValue(payload["message_id"]) ?? "unknown-message"

            output.append(
                LocalUsageEvent(
                    signature: "kimi|\(sessionID)|\(messageID)|\(Int(eventAt.timeIntervalSince1970))|\(snapshotTotal)",
                    eventAt: eventAt,
                    modelID: modelID,
                    totalTokens: delta
                )
            )
        }
    }

    private func scanJSONLLines(
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

    private static func tokenCount(from usage: [String: Any]) -> Int {
        var total = 0
        for value in usage.values {
            guard let count = intValue(value) else { continue }
            total += max(0, count)
        }
        return total
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value.rounded()) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func parseTimestampDate(_ raw: Any?) -> Date? {
        if let value = raw as? Double {
            return Date(timeIntervalSince1970: value)
        }
        if let value = raw as? Int {
            return Date(timeIntervalSince1970: Double(value))
        }
        if let value = raw as? NSNumber {
            return Date(timeIntervalSince1970: value.doubleValue)
        }
        if let value = raw as? String, let parsed = Double(value) {
            return Date(timeIntervalSince1970: parsed)
        }
        return nil
    }
}
