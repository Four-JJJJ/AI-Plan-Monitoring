import Foundation
import XCTest
@testable import AIPlanMonitor

final class LocalSessionCompletionSignalMonitorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("local-session-signal-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testCodexSignalUsesLatestCompletedEventTimestamp() throws {
        let databasePath = temporaryDirectory.appendingPathComponent("logs_2.sqlite").path
        try createLogsTable(at: databasePath)
        try insertLog(
            ts: Int(try fixedDate("2026-04-20T10:00:00Z").timeIntervalSince1970),
            body: #"event.name="codex.sse_event" event.kind=response.completed model=gpt-5.4"#,
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-20T10:00:30Z").timeIntervalSince1970),
            body: #"event.name="codex.sse_event" event.kind=response.started model=gpt-5.4"#,
            at: databasePath
        )
        try insertLog(
            ts: Int(try fixedDate("2026-04-20T10:02:00Z").timeIntervalSince1970),
            body: #"event.name="codex.sse_event" event.kind=response.completed model=gpt-5.4"#,
            at: databasePath
        )

        let monitor = LocalSessionCompletionSignalMonitor(
            codexLogsPath: databasePath,
            claudeProjectsRoot: temporaryDirectory.path
        )

        XCTAssertEqual(monitor.latestCodexCompletionAt(), try fixedDate("2026-04-20T10:02:00Z"))
    }

    func testClaudeSignalFindsLatestAssistantUsageEvent() throws {
        let projectsRoot = temporaryDirectory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try writeJSONL(
            root: projectsRoot,
            relativePath: "workspace-a/session-a.jsonl",
            lines: [
                jsonLine([
                    "type": "assistant",
                    "timestamp": "2026-04-20T09:50:00Z",
                    "message": [
                        "id": "m1",
                        "usage": [
                            "input_tokens": 10,
                            "output_tokens": 5
                        ]
                    ]
                ]),
                jsonLine([
                    "type": "assistant",
                    "timestamp": "2026-04-20T10:03:00Z",
                    "message": [
                        "id": "m2",
                        "usage": [
                            "input_tokens": 20,
                            "output_tokens": 6
                        ]
                    ]
                ])
            ]
        )
        try writeJSONL(
            root: projectsRoot,
            relativePath: "workspace-b/session-b.jsonl",
            lines: [
                jsonLine([
                    "type": "user",
                    "timestamp": "2026-04-20T10:04:00Z",
                    "message": [
                        "id": "u1",
                        "content": "hello"
                    ]
                ]),
                jsonLine([
                    "type": "assistant",
                    "timestamp": "2026-04-20T10:06:00Z",
                    "message": [
                        "id": "m3",
                        "usage": [
                            "input_tokens": 8,
                            "output_tokens": 8
                        ]
                    ]
                ])
            ]
        )

        let monitor = LocalSessionCompletionSignalMonitor(
            codexLogsPath: temporaryDirectory.appendingPathComponent("missing.sqlite").path,
            claudeProjectsRoot: projectsRoot.path,
            claudeRecentFileWindow: 30 * 24 * 60 * 60
        )

        XCTAssertEqual(monitor.latestClaudeCompletionAt(), try fixedDate("2026-04-20T10:06:00Z"))
    }

    func testCoordinatorDebouncesRefreshWithinFifteenSeconds() throws {
        final class StubSignalSource: LocalSessionCompletionSignalSource {
            var codexSignalAt: Date?
            var claudeSignalAt: Date?

            func latestCodexCompletionAt() -> Date? { codexSignalAt }
            func latestClaudeCompletionAt() -> Date? { claudeSignalAt }
        }

        var now = try fixedDate("2026-04-20T10:00:00Z")
        let source = StubSignalSource()
        source.codexSignalAt = try fixedDate("2026-04-20T09:59:55Z")

        let coordinator = LocalSessionRefreshCoordinator(
            signalSource: source,
            minimumEventRefreshGap: 15,
            nowProvider: { now }
        )

        var codex = ProviderDescriptor.defaultOfficialCodex()
        codex.enabled = true

        XCTAssertEqual(coordinator.refreshCandidates(from: [codex]).map(\.id), ["codex-official"])

        source.codexSignalAt = try fixedDate("2026-04-20T10:00:05Z")
        now = try fixedDate("2026-04-20T10:00:10Z")
        XCTAssertTrue(coordinator.refreshCandidates(from: [codex]).isEmpty)

        now = try fixedDate("2026-04-20T10:00:16Z")
        XCTAssertEqual(coordinator.refreshCandidates(from: [codex]).map(\.id), ["codex-official"])
    }

    func testClaudeSignalEnumerationIsThrottledByInterval() throws {
        let projectsRoot = temporaryDirectory.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        let relativePath = "workspace-a/session-a.jsonl"

        try writeJSONL(
            root: projectsRoot,
            relativePath: relativePath,
            lines: [
                jsonLine([
                    "type": "assistant",
                    "timestamp": "2026-04-20T10:00:00Z",
                    "message": [
                        "id": "m1",
                        "usage": [
                            "input_tokens": 10,
                            "output_tokens": 5
                        ]
                    ]
                ])
            ]
        )

        var now = try fixedDate("2026-04-20T10:05:00Z")
        let monitor = LocalSessionCompletionSignalMonitor(
            codexLogsPath: temporaryDirectory.appendingPathComponent("missing.sqlite").path,
            claudeProjectsRoot: projectsRoot.path,
            claudeRecentFileWindow: 30 * 24 * 60 * 60,
            claudeEnumerationInterval: 120,
            nowProvider: { now }
        )

        XCTAssertEqual(monitor.latestClaudeCompletionAt(), try fixedDate("2026-04-20T10:00:00Z"))

        try writeJSONL(
            root: projectsRoot,
            relativePath: relativePath,
            lines: [
                jsonLine([
                    "type": "assistant",
                    "timestamp": "2026-04-20T10:06:00Z",
                    "message": [
                        "id": "m2",
                        "usage": [
                            "input_tokens": 20,
                            "output_tokens": 8
                        ]
                    ]
                ])
            ]
        )

        // Still within enumeration interval, should return cached value.
        XCTAssertEqual(monitor.latestClaudeCompletionAt(), try fixedDate("2026-04-20T10:00:00Z"))

        now = try fixedDate("2026-04-20T10:08:10Z")
        XCTAssertEqual(monitor.latestClaudeCompletionAt(), try fixedDate("2026-04-20T10:06:00Z"))
    }

    private func createLogsTable(at path: String) throws {
        let sql = "CREATE TABLE IF NOT EXISTS logs (ts REAL, feedback_log_body TEXT);"
        try runSQLite(databasePath: path, sql: sql)
    }

    private func insertLog(ts: Int, body: String, at path: String) throws {
        let escaped = body.replacingOccurrences(of: "'", with: "''")
        let sql = "INSERT INTO logs (ts, feedback_log_body) VALUES (\(ts), '\(escaped)');"
        try runSQLite(databasePath: path, sql: sql)
    }

    private func runSQLite(databasePath: String, sql: String) throws {
        guard let result = ShellCommand.run(
            executable: "/usr/bin/sqlite3",
            arguments: [databasePath, sql],
            timeout: 10
        ) else {
            XCTFail("sqlite3 command failed to start")
            return
        }
        if result.status != 0 {
            XCTFail("sqlite3 command failed: \(result.stderr)")
        }
    }

    private func writeJSONL(root: URL, relativePath: String, lines: [String]) throws {
        let fileURL = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func jsonLine(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "LocalSessionCompletionSignalMonitorTests", code: 1)
        }
        return date
    }
}
