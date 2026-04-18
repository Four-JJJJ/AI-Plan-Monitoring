import Foundation

final class ClaudeLocalUsageService {
    private let fileManager: FileManager
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let defaultClaudeRootPath: String?

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        defaultClaudeRootPath: String? = nil
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.nowProvider = nowProvider
        self.defaultClaudeRootPath = defaultClaudeRootPath
    }

    func fetchSummary(
        scope: LocalUsageTrendScope = .allAccounts,
        currentConfigDir: String? = nil,
        allConfigDirs: [String] = []
    ) throws -> LocalUsageSummary {
        let roots = resolvedProjectRoots(
            scope: scope,
            currentConfigDir: currentConfigDir,
            allConfigDirs: allConfigDirs
        )
        let now = nowProvider()
        let startOfLast30Days = calendar.date(
            byAdding: .day,
            value: -29,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let events = scanProjectEvents(
            projectRoots: roots,
            startOfLast30Days: startOfLast30Days
        )

        return LocalUsageSummaryBuilder.build(
            events: events,
            calendar: calendar,
            now: now,
            sourcePath: roots.joined(separator: ", ")
        )
    }

    private func resolvedProjectRoots(
        scope: LocalUsageTrendScope,
        currentConfigDir: String?,
        allConfigDirs: [String]
    ) -> [String] {
        let defaultRoot = resolvedDefaultProjectsRoot()
        let normalizedAllConfigDirs = allConfigDirs.compactMap(Self.normalizedDirectoryPath)
        let allRoots = Self.uniquePaths(
            [defaultRoot]
                + normalizedAllConfigDirs.map { Self.projectsRoot(fromConfigDir: $0) }
        )

        switch scope {
        case .allAccounts:
            return allRoots
        case .currentAccount:
            if let currentConfigDir = Self.normalizedDirectoryPath(currentConfigDir) {
                let currentRoot = Self.projectsRoot(fromConfigDir: currentConfigDir)
                if fileManager.fileExists(atPath: currentRoot) {
                    return [currentRoot]
                }
            }
            return [defaultRoot]
        }
    }

    private func resolvedDefaultProjectsRoot() -> String {
        if let explicit = Self.normalizedDirectoryPath(defaultClaudeRootPath) {
            return explicit
        }
        return "\(NSHomeDirectory())/.claude/projects"
    }

    private func scanProjectEvents(
        projectRoots: [String],
        startOfLast30Days: Date
    ) -> [LocalUsageEvent] {
        let cutoff = calendar.date(byAdding: .day, value: -1, to: startOfLast30Days) ?? startOfLast30Days
        let files = jsonlFilePaths(roots: projectRoots, cutoff: cutoff)
        if files.isEmpty {
            return []
        }

        var dedupedEvents: [String: LocalUsageEvent] = [:]
        dedupedEvents.reserveCapacity(1024)

        for filePath in files {
            scanJSONLLines(atPath: filePath) { line in
                guard line.contains("\"type\":\"assistant\""), line.contains("\"usage\"") else {
                    return
                }

                guard let data = line.data(using: .utf8),
                      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return
                }

                let type = Self.stringValue(root["type"])
                guard type == "assistant" else { return }

                guard let message = root["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                guard let eventAt = Self.parseISODate(Self.stringValue(root["timestamp"])),
                      eventAt >= startOfLast30Days else {
                    return
                }

                let totalTokens = Self.tokenCount(from: usage)
                guard totalTokens > 0 else { return }

                let modelID = Self.stringValue(message["model"]) ?? "unknown"
                let signature = Self.eventSignature(root: root, message: message, fallbackLine: line)
                let event = LocalUsageEvent(
                    signature: signature,
                    eventAt: eventAt,
                    modelID: modelID,
                    totalTokens: totalTokens
                )

                if let existing = dedupedEvents[signature] {
                    if event.totalTokens > existing.totalTokens {
                        dedupedEvents[signature] = event
                    } else if event.totalTokens == existing.totalTokens,
                              event.eventAt > existing.eventAt {
                        dedupedEvents[signature] = event
                    }
                } else {
                    dedupedEvents[signature] = event
                }
            }
        }

        return Array(dedupedEvents.values)
    }

    private func jsonlFilePaths(roots: [String], cutoff: Date) -> [String] {
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

    private static func projectsRoot(fromConfigDir configDir: String) -> String {
        URL(fileURLWithPath: configDir, isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .path
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func uniquePaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for path in paths {
            if seen.insert(path).inserted {
                output.append(path)
            }
        }
        return output
    }

    private static func eventSignature(
        root: [String: Any],
        message: [String: Any],
        fallbackLine: String
    ) -> String {
        let sessionID = stringValue(root["sessionId"]) ?? "unknown-session"
        if let messageID = stringValue(message["id"])
            ?? stringValue(root["uuid"])
            ?? stringValue(root["parentUuid"]) {
            return "claude|\(sessionID)|\(messageID)"
        }
        return "claude|\(sessionID)|hash=\(stableHash(of: fallbackLine))"
    }

    private static func tokenCount(from usage: [String: Any]) -> Int {
        let keys = [
            "input_tokens",
            "output_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
            "reasoning_output_tokens",
            "tool_tokens"
        ]

        var total = 0
        for key in keys {
            guard let value = intValue(usage[key]) else { continue }
            total += max(0, value)
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

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw = stringValue(raw) else { return nil }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: raw) {
            return date
        }

        let formatterBasic = ISO8601DateFormatter()
        formatterBasic.formatOptions = [.withInternetDateTime]
        return formatterBasic.date(from: raw)
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

    private static func stableHash(of text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
