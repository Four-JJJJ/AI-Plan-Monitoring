import Foundation

enum OfficialSnapshotFallback {
    static func make(from snapshot: UsageSnapshot) -> UsageSnapshot {
        var fallback = snapshot
        fallback.status = .warning
        fallback.valueFreshness = .cachedFallback
        fallback.note = snapshot.note.isEmpty ? "cached fallback" : "\(snapshot.note) | cached"
        fallback.updatedAt = Date()
        return fallback
    }
}
