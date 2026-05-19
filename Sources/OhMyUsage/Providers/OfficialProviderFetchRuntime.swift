import OhMyUsageDomain
import Foundation

protocol OfficialSnapshotCaching: Actor {
    func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot?
    func store(_ snapshot: UsageSnapshot, for key: String)
    func snapshotAny(for key: String) -> UsageSnapshot?
}

protocol OfficialFetchGating: Actor {
    func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T
}

enum OfficialProviderFetchRuntime {
    static func fetch(
        forceRefresh: Bool,
        cacheLookupKey: String,
        ttl: TimeInterval,
        cache: any OfficialSnapshotCaching,
        gate: any OfficialFetchGating,
        cacheStoreKey: (@Sendable () -> String)? = nil,
        load: @Sendable @escaping () async throws -> UsageSnapshot
    ) async throws -> UsageSnapshot {
        try await gate.withPermit {
            if !forceRefresh,
               let cached = await cache.snapshotIfFresh(for: cacheLookupKey, ttl: ttl) {
                return cached
            }

            do {
                let snapshot = try await load()
                let storeKey = cacheStoreKey?() ?? cacheLookupKey
                await cache.store(snapshot, for: storeKey)
                return snapshot
            } catch {
                if !forceRefresh,
                   let stale = await cache.snapshotAny(for: cacheLookupKey) {
                    return OfficialSnapshotFallback.make(from: stale)
                }
                throw error
            }
        }
    }
}

actor FetchedAtOfficialSnapshotCache: OfficialSnapshotCaching {
    private var snapshots: [String: UsageSnapshot] = [:]
    private var fetchedAt: [String: Date] = [:]

    func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot? {
        guard let snapshot = snapshots[key], let fetchedAt = fetchedAt[key] else { return nil }
        guard Date().timeIntervalSince(fetchedAt) <= ttl else { return nil }
        return snapshot
    }

    func store(_ snapshot: UsageSnapshot, for key: String) {
        snapshots[key] = snapshot
        fetchedAt[key] = Date()
    }

    func snapshotAny(for key: String) -> UsageSnapshot? {
        snapshots[key]
    }
}

actor SnapshotTimestampOfficialSnapshotCache: OfficialSnapshotCaching {
    private var snapshots: [String: UsageSnapshot] = [:]

    func snapshotIfFresh(for key: String, ttl: TimeInterval) -> UsageSnapshot? {
        guard let snapshot = snapshots[key] else { return nil }
        guard Date().timeIntervalSince(snapshot.updatedAt) <= ttl else { return nil }
        return snapshot
    }

    func store(_ snapshot: UsageSnapshot, for key: String) {
        snapshots[key] = snapshot
    }

    func snapshotAny(for key: String) -> UsageSnapshot? {
        snapshots[key]
    }
}

actor SerialOfficialFetchGate: OfficialFetchGating {
    private var inFlight = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
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
        if waiters.isEmpty {
            inFlight = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}

actor PassthroughOfficialFetchGate: OfficialFetchGating {
    func withPermit<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        try await operation()
    }
}
