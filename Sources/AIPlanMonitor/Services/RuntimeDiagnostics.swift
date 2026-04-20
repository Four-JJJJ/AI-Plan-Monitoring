import Foundation
import Darwin.Mach

enum RuntimeDiagnosticsLimits {
    static let snapshotNoteMaxLength = 384
    static let localUsageTrendCacheMaxEntries = 24
    static let thirdPartyBalanceBaselineCacheMaxEntries = 24
    static let localUsageTrendCacheEntryTTL: TimeInterval = 15 * 60
    static let localUsageTrendModelBreakdownCacheEntries = 0
    static let claudePrefetchMaxConcurrent = 2
    static let claudeSignalMaxTrackedFiles = 200
    static let jsonlMaxLineBytes = 512 * 1024
}

struct RuntimeMemoryDiagnostics: Equatable {
    var residentSizeBytes: UInt64?
    var snapshotCount: Int
    var codexProfileCount: Int
    var codexSlotCount: Int
    var claudeProfileCount: Int
    var claudeSlotCount: Int
    var codexPrefetchAttemptedIdentityCount: Int
    var codexPrefetchInFlightCount: Int
    var claudePrefetchAttemptedIdentityCount: Int
    var claudePrefetchInFlightCount: Int
    var pollTaskCount: Int
}

enum RuntimeMemoryProbe {
    static func residentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let status: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }

        guard status == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }
}
