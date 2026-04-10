import Foundation
import Dispatch

final class CodexProvider: UsageProvider, @unchecked Sendable {
    private static let cache = CodexSnapshotCache()
    private static let gate = CodexFetchGate()
    private let cacheTTL: TimeInterval = 15

    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor) {
        self.descriptor = descriptor
    }

    func fetch() async throws -> UsageSnapshot {
        try await fetch(forceRefresh: false)
    }

    func fetch(forceRefresh: Bool) async throws -> UsageSnapshot {
        try await Self.gate.withPermit { [self] in
            if !forceRefresh,
               let cached = await Self.cache.snapshotIfFresh(ttl: self.cacheTTL) {
                return cached
            }

            do {
                var responses = try self.runCodexRPC(keepAliveSeconds: 3.0)
                if responses["2"] == nil || responses["3"] == nil {
                    // Some Codex builds return rate limits late; keep stdin open longer once.
                    responses = try self.runCodexRPC(keepAliveSeconds: 10.0)
                }
                if responses["2"] == nil || responses["3"] == nil {
                    // Final slow-path attempt for machines where app-server startup is delayed.
                    responses = try self.runCodexRPC(keepAliveSeconds: 18.0)
                }

                guard let accountResult = responses["2"] else {
                    throw ProviderError.invalidResponse("missing account/read response")
                }

                guard let limitsResult = responses["3"] else {
                    throw ProviderError.invalidResponse("missing account/rateLimits/read response")
                }

                let accountData = try JSONSerialization.data(withJSONObject: accountResult)
                let limitsData = try JSONSerialization.data(withJSONObject: limitsResult)

                let account = try JSONDecoder().decode(CodexAccountReadResult.self, from: accountData)
                let limits = try JSONDecoder().decode(CodexRateLimitsReadResult.self, from: limitsData)

                let primaryUsed = limits.rateLimits.primary.usedPercent
                let secondaryUsed = limits.rateLimits.secondary.usedPercent
                let primaryRemaining = max(0, 100 - primaryUsed)
                let secondaryRemaining = max(0, 100 - secondaryUsed)
                let remaining = primaryRemaining

                let status: SnapshotStatus = remaining <= self.descriptor.threshold.lowRemaining ? .warning : .ok
                let note = "Plan \(account.account.planType ?? "unknown") | Primary \(Int(primaryUsed))% used | Secondary \(Int(secondaryUsed))% used"

                let snapshot = UsageSnapshot(
                    source: self.descriptor.id,
                    status: status,
                    remaining: remaining,
                    used: primaryUsed,
                    limit: 100,
                    unit: "%",
                    updatedAt: Date(),
                    note: note,
                    rawMeta: [
                        "sourceMode": "rpc",
                        "email": account.account.email ?? "",
                        "planType": account.account.planType ?? "",
                        "primaryUsedPercent": String(primaryUsed),
                        "secondaryUsedPercent": String(secondaryUsed),
                        "primaryRemainingPercent": String(primaryRemaining),
                        "secondaryRemainingPercent": String(secondaryRemaining),
                        "primaryResetAt": String(limits.rateLimits.primary.resetsAt),
                        "secondaryResetAt": String(limits.rateLimits.secondary.resetsAt),
                        "creditsBalance": limits.rateLimits.credits.balance
                    ]
                )

                await Self.cache.store(snapshot)
                return snapshot
            } catch {
                if let stale = await Self.cache.snapshotAny() {
                    var fallback = stale
                    fallback.status = .warning
                    fallback.note = "\(stale.note) | cached"
                    fallback.updatedAt = Date()
                    return fallback
                }
                throw error
            }
        }
    }

    private func runCodexRPC(keepAliveSeconds: TimeInterval) throws -> [String: [String: Any]] {
        guard let codexPath = resolveCodexExecutablePath() else {
            throw ProviderError.unavailable("Unable to locate codex CLI. Set CODEX_CLI_PATH or install Codex.app.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()

        let messages = [
            #"{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"AIBalanceMonitor","version":"0.1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"2","method":"account/read","params":{}}"#,
            #"{"jsonrpc":"2.0","id":"3","method":"account/rateLimits/read","params":{}}"#
        ]

        let payload = messages.joined(separator: "\n") + "\n"
        if let data = payload.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }

        // Keep stdin open briefly so slower methods (e.g. rateLimits/read) can complete.
        Thread.sleep(forTimeInterval: keepAliveSeconds)
        try? inputPipe.fileHandleForWriting.close()

        var forceTerminated = false
        let waitResult = terminated.wait(timeout: .now() + max(14.0, keepAliveSeconds + 8.0))
        if waitResult == .timedOut {
            forceTerminated = true
            process.terminate()
            if terminated.wait(timeout: .now() + 1.0) == .timedOut {
                process.interrupt()
                _ = terminated.wait(timeout: .now() + 1.0)
            }
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard let outputText = String(data: outputData, encoding: .utf8) else {
            throw ProviderError.invalidResponse("stdout is not UTF-8")
        }

        var resultsByID: [String: [String: Any]] = [:]

        for line in outputText.split(separator: "\n") {
            guard line.first == "{" else { continue }
            guard let data = String(line).data(using: .utf8) else { continue }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ProviderError.invalidResponse(message)
            }

            let id: String?
            if let stringID = json["id"] as? String {
                id = stringID
            } else if let intID = json["id"] as? Int {
                id = String(intID)
            } else if let numericID = json["id"] as? NSNumber {
                id = numericID.stringValue
            } else {
                id = nil
            }

            guard let id,
                  let result = json["result"] as? [String: Any] else {
                continue
            }

            resultsByID[id] = result
        }

        if process.terminationStatus != 0 && !forceTerminated {
            let stderr = String(data: errData, encoding: .utf8) ?? "unknown stderr"
            throw ProviderError.commandFailed(stderr)
        }

        if resultsByID["2"] == nil || resultsByID["3"] == nil {
            if forceTerminated {
                throw ProviderError.timeout("codex app-server timeout")
            }
            throw ProviderError.invalidResponse("missing account/read or account/rateLimits/read response")
        }

        return resultsByID
    }

    private func resolveCodexExecutablePath() -> String? {
        let manager = FileManager.default

        let explicit = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"]
        let staticCandidates: [String] = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]

        let envPath = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let pathCandidates = envPath
            .split(separator: ":")
            .map { "\($0)/codex" }

        let candidates = [explicit].compactMap { $0 } + staticCandidates + pathCandidates
        for path in candidates where manager.isExecutableFile(atPath: path) {
            // Avoid the GUI launcher executable; it spawns Codex.app windows/processes.
            if isGuiLauncher(path) {
                continue
            }
            return path
        }
        return nil
    }

    private func isGuiLauncher(_ path: String) -> Bool {
        path.contains("/Applications/Codex.app/Contents/MacOS/codex")
    }
}

private actor CodexSnapshotCache {
    private var snapshot: UsageSnapshot?
    private var fetchedAt: Date?

    func snapshotIfFresh(ttl: TimeInterval) -> UsageSnapshot? {
        guard let snapshot, let fetchedAt else { return nil }
        guard Date().timeIntervalSince(fetchedAt) <= ttl else { return nil }
        return snapshot
    }

    func store(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        self.fetchedAt = Date()
    }

    func snapshotAny() -> UsageSnapshot? {
        snapshot
    }
}

private actor CodexFetchGate {
    private var inFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !inFlight {
            inFlight = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
            return
        }
        inFlight = false
    }
}

private struct CodexAccountReadResult: Decodable {
    struct Account: Decodable {
        let type: String?
        let email: String?
        let planType: String?
    }

    let account: Account
    let requiresOpenaiAuth: Bool
}

private struct CodexRateLimitsReadResult: Decodable {
    struct RateLimits: Decodable {
        struct UsageWindow: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int
            let resetsAt: Int
        }

        struct Credits: Decodable {
            let hasCredits: Bool
            let unlimited: Bool
            let balance: String
        }

        let limitId: String
        let limitName: String?
        let primary: UsageWindow
        let secondary: UsageWindow
        let credits: Credits
        let planType: String?
    }

    let rateLimits: RateLimits
}
