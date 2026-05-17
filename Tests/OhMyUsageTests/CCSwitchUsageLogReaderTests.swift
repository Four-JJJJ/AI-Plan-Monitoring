import Foundation
import XCTest
@testable import OhMyUsage

final class CCSwitchUsageLogReaderTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ccswitch-usage-reader-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    func testReadUsageLogsNormalizesProxySessionPlaceholderAndRollupRows() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let eventAt = try fixedDate("2026-05-16T10:30:00Z")
        let rollupDate = "2026-05-15"
        try runSQLite(
            databasePath: databaseURL.path,
            sql: """
            INSERT INTO providers (id, app_type, name) VALUES ('relay-a', 'codex', 'FourJ Relay');
            INSERT INTO providers (id, app_type, name) VALUES ('relay-b', 'claude', 'Claude Relay');
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES (
                'req-proxy', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 100, 50,
                20, 10, 200, \(Int(eventAt.timeIntervalSince1970)), NULL
            );
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES (
                'req-session', '_codex_session', 'codex', 'gpt-5.4', 'gpt-5.4', 30, 10,
                5, 0, 500, \(Int(eventAt.timeIntervalSince1970)), 'session'
            );
            INSERT INTO usage_daily_rollups (
                date, app_type, provider_id, model, request_count, success_count, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens
            ) VALUES (
                '\(rollupDate)', 'claude', 'relay-b', 'claude-sonnet-4-6', 3, 2, 9, 6, 5, 4
            );
            """
        )

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let result = reader.readUsageLogs(
            since: try fixedDate("2026-05-15T00:00:00Z"),
            until: try fixedDate("2026-05-17T00:00:00Z")
        )

        XCTAssertTrue(result.diagnostics.isEmpty)
        XCTAssertEqual(result.records.count, 3)

        let proxy = try XCTUnwrap(result.records.first { $0.requestID == "req-proxy" })
        XCTAssertEqual(proxy.source, .proxy)
        XCTAssertEqual(proxy.providerName, "FourJ Relay")
        XCTAssertEqual(proxy.inputTokens, 80)
        XCTAssertEqual(proxy.outputTokens, 50)
        XCTAssertEqual(proxy.cacheReadTokens, 20)
        XCTAssertEqual(proxy.cacheWriteTokens, 10)
        XCTAssertEqual(proxy.requestCount, 1)
        XCTAssertEqual(proxy.successCount, 1)

        let session = try XCTUnwrap(result.records.first { $0.requestID == "req-session" })
        XCTAssertEqual(session.source, .session)
        XCTAssertEqual(session.providerName, "Codex (Session)")
        XCTAssertEqual(session.inputTokens, 25)
        XCTAssertEqual(session.successCount, 0)

        let rollup = try XCTUnwrap(result.records.first { $0.source == .dailyRollup })
        XCTAssertEqual(rollup.providerName, "Claude Relay")
        XCTAssertEqual(rollup.requestCount, 3)
        XCTAssertEqual(rollup.successCount, 2)
        XCTAssertEqual(rollup.inputTokens, 9)
        XCTAssertEqual(rollup.cacheReadTokens, 5)
        XCTAssertEqual(rollup.cacheWriteTokens, 4)
    }

    func testReadUsageLogsReturnsEmptyDiagnosticWhenDatabaseIsMissing() throws {
        let reader = CCSwitchUsageLogReader(
            databasePath: temporaryDirectory.appendingPathComponent("missing.db").path
        )

        let result = reader.readUsageLogs(
            since: try fixedDate("2026-05-15T00:00:00Z"),
            until: try fixedDate("2026-05-17T00:00:00Z")
        )

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.diagnostics.contains { $0.contains("未检测到 cc-switch 请求日志") })
    }

    func testReadUsageLogsKeepsEpochPrecisionAtRangeBoundaries() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("cc-switch-boundary.db")
        try createCCSwitchSchema(at: databaseURL.path)

        let since = try fixedDate("2026-05-16T10:00:00Z")
        let until = try fixedDate("2026-05-16T11:00:00Z")
        let middle = try fixedDate("2026-05-16T10:30:00Z")
        let late = try fixedDate("2026-05-16T10:45:00Z")
        let nearEnd = try fixedDate("2026-05-16T10:59:59Z")
        let before = try fixedDate("2026-05-16T09:59:59Z")

        try runSQLite(
            databasePath: databaseURL.path,
            sql: """
            INSERT INTO proxy_request_logs (
                request_id, provider_id, app_type, model, request_model, input_tokens, output_tokens,
                cache_read_tokens, cache_creation_tokens, status_code, created_at, data_source
            ) VALUES
                ('req-sec', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(since.timeIntervalSince1970)), NULL),
                ('req-ms', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(middle.timeIntervalSince1970 * 1_000)), NULL),
                ('req-us', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(late.timeIntervalSince1970 * 1_000_000)), NULL),
                ('req-ns', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(nearEnd.timeIntervalSince1970 * 1_000_000_000)), NULL),
                ('req-before', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(before.timeIntervalSince1970)), NULL),
                ('req-end', 'relay-a', 'codex', 'gpt-5.5', 'gpt-5.5', 10, 5, 0, 0, 200, \(Int64(until.timeIntervalSince1970)), NULL);
            """
        )

        let reader = CCSwitchUsageLogReader(databasePath: databaseURL.path)
        let result = reader.readUsageLogs(since: since, until: until)
        let requestIDs = result.records.map(\.requestID).sorted()

        XCTAssertEqual(requestIDs, ["req-ms", "req-ns", "req-sec", "req-us"])
    }

    private func createCCSwitchSchema(at path: String) throws {
        try runSQLite(
            databasePath: path,
            sql: """
            CREATE TABLE providers (
                id TEXT PRIMARY KEY,
                app_type TEXT,
                name TEXT
            );
            CREATE TABLE proxy_request_logs (
                request_id TEXT PRIMARY KEY,
                provider_id TEXT NOT NULL,
                app_type TEXT NOT NULL,
                model TEXT NOT NULL,
                request_model TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER,
                status_code INTEGER,
                created_at INTEGER,
                data_source TEXT
            );
            CREATE TABLE usage_daily_rollups (
                date TEXT,
                app_type TEXT,
                provider_id TEXT,
                model TEXT,
                request_count INTEGER,
                success_count INTEGER,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cache_read_tokens INTEGER,
                cache_creation_tokens INTEGER
            );
            """
        )
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

    private func fixedDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw NSError(domain: "CCSwitchUsageLogReaderTests", code: 1)
        }
        return date
    }
}
