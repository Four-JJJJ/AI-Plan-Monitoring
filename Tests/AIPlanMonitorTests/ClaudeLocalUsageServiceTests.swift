import Foundation
import XCTest
@testable import AIPlanMonitor

final class ClaudeLocalUsageServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaultProjectsRoot: URL!
    private var configADirectory: URL!
    private var configBDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-local-usage-tests-\(UUID().uuidString)", isDirectory: true)
        defaultProjectsRoot = temporaryDirectory.appendingPathComponent("default-projects", isDirectory: true)
        configADirectory = temporaryDirectory.appendingPathComponent("config-a", isDirectory: true)
        configBDirectory = temporaryDirectory.appendingPathComponent("config-b", isDirectory: true)

        try FileManager.default.createDirectory(at: defaultProjectsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configADirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configBDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testFetchSummaryParsesUsageAndDedupesDuplicateAssistantMessage() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "workspace-a/session-a.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T10:00:00Z",
                    sessionID: "session-a",
                    uuid: "line-1",
                    messageID: "msg-1",
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 5,
                    cacheCreation: 3,
                    cacheRead: 2
                ),
                assistantLine(
                    timestamp: "2026-04-18T10:00:01Z",
                    sessionID: "session-a",
                    uuid: "line-2",
                    messageID: "msg-1", // duplicate assistant message id
                    model: "claude-sonnet-4-6",
                    input: 10,
                    output: 7,
                    cacheCreation: 3,
                    cacheRead: 2
                ),
                assistantLine(
                    timestamp: "2026-04-17T11:00:00Z",
                    sessionID: "session-a",
                    uuid: "line-3",
                    messageID: "msg-2",
                    model: "claude-opus-4",
                    input: 12,
                    output: 8,
                    cacheCreation: 4,
                    cacheRead: 6
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let summary = try service.fetchSummary(scope: .allAccounts)

        XCTAssertEqual(summary.today.totalTokens, 22)
        XCTAssertEqual(summary.today.responses, 1)
        XCTAssertEqual(summary.yesterday.totalTokens, 30)
        XCTAssertEqual(summary.yesterday.responses, 1)
        XCTAssertEqual(summary.last30Days.totalTokens, 52)
        XCTAssertEqual(summary.last30Days.responses, 2)
        XCTAssertEqual(summary.hourly24.count, 24)
        XCTAssertEqual(summary.daily7.count, 7)
    }

    func testFetchSummaryCurrentAndAllScopesUseExpectedRoots() throws {
        let now = try fixedDate("2026-04-18T12:00:00Z")
        try writeProjectFile(
            root: defaultProjectsRoot,
            relativePath: "default/default.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:00:00Z",
                    sessionID: "default-session",
                    uuid: "default-line",
                    messageID: "default-msg",
                    model: "claude-sonnet-4-6",
                    input: 4,
                    output: 4,
                    cacheCreation: 1,
                    cacheRead: 1
                )
            ]
        )
        try writeProjectFile(
            root: configADirectory.appendingPathComponent("projects", isDirectory: true),
            relativePath: "a/a.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:10:00Z",
                    sessionID: "a-session",
                    uuid: "a-line",
                    messageID: "a-msg",
                    model: "claude-sonnet-4-6",
                    input: 8,
                    output: 8,
                    cacheCreation: 4,
                    cacheRead: 5
                )
            ]
        )
        try writeProjectFile(
            root: configBDirectory.appendingPathComponent("projects", isDirectory: true),
            relativePath: "b/b.jsonl",
            lines: [
                assistantLine(
                    timestamp: "2026-04-18T09:20:00Z",
                    sessionID: "b-session",
                    uuid: "b-line",
                    messageID: "b-msg",
                    model: "claude-opus-4",
                    input: 9,
                    output: 10,
                    cacheCreation: 3,
                    cacheRead: 4
                )
            ]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let service = ClaudeLocalUsageService(
            calendar: calendar,
            nowProvider: { now },
            defaultClaudeRootPath: defaultProjectsRoot.path
        )

        let currentSummary = try service.fetchSummary(
            scope: .currentAccount,
            currentConfigDir: configADirectory.path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(currentSummary.today.totalTokens, 25)
        XCTAssertEqual(currentSummary.today.responses, 1)

        let allSummary = try service.fetchSummary(
            scope: .allAccounts,
            currentConfigDir: configADirectory.path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(allSummary.today.totalTokens, 61)
        XCTAssertEqual(allSummary.today.responses, 3)

        let fallbackSummary = try service.fetchSummary(
            scope: .currentAccount,
            currentConfigDir: temporaryDirectory.appendingPathComponent("missing-config", isDirectory: true).path,
            allConfigDirs: [configADirectory.path, configBDirectory.path]
        )
        XCTAssertEqual(fallbackSummary.today.totalTokens, 10)
        XCTAssertEqual(fallbackSummary.today.responses, 1)
    }

    private func writeProjectFile(root: URL, relativePath: String, lines: [String]) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func assistantLine(
        timestamp: String,
        sessionID: String,
        uuid: String,
        messageID: String,
        model: String,
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> String {
        jsonLine([
            "timestamp": timestamp,
            "sessionId": sessionID,
            "uuid": uuid,
            "type": "assistant",
            "message": [
                "id": messageID,
                "model": model,
                "usage": [
                    "input_tokens": input,
                    "output_tokens": output,
                    "cache_creation_input_tokens": cacheCreation,
                    "cache_read_input_tokens": cacheRead
                ]
            ]
        ])
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "ClaudeLocalUsageServiceTests", code: 1)
        }
        return date
    }
}
