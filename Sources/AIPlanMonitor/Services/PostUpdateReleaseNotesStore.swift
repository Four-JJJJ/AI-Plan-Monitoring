import Foundation

struct PendingPostUpdateReleaseNotes: Codable, Equatable {
    var version: String
    var releaseURL: URL
    var notesURL: URL?
    var createdAt: Date

    var displayURL: URL {
        notesURL ?? releaseURL
    }
}

protocol PostUpdateReleaseNotesStoring: AnyObject {
    func schedulePresentation(for update: AppUpdateInfo)
    func consumePresentationIfNeeded(currentVersion: String) -> PendingPostUpdateReleaseNotes?
    func reset()
}

final class PostUpdateReleaseNotesStore: PostUpdateReleaseNotesStoring {
    private static let pendingDefaultsKey = "AIPlanMonitor.PendingPostUpdateReleaseNotes"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func schedulePresentation(for update: AppUpdateInfo) {
        let pending = PendingPostUpdateReleaseNotes(
            version: AppUpdateService.normalizeVersion(update.latestVersion),
            releaseURL: update.releaseURL,
            notesURL: update.notesURL,
            createdAt: Date()
        )
        guard let data = try? encoder.encode(pending) else { return }
        defaults.set(data, forKey: Self.pendingDefaultsKey)
    }

    func consumePresentationIfNeeded(currentVersion: String) -> PendingPostUpdateReleaseNotes? {
        guard let pending = loadPendingPresentation() else { return nil }

        let normalizedCurrentVersion = AppUpdateService.normalizeVersion(currentVersion)
        let normalizedPendingVersion = AppUpdateService.normalizeVersion(pending.version)

        if normalizedCurrentVersion == normalizedPendingVersion {
            reset()
            return pending
        }

        if Self.isVersion(normalizedCurrentVersion, newerThan: normalizedPendingVersion) {
            reset()
        }

        return nil
    }

    func reset() {
        defaults.removeObject(forKey: Self.pendingDefaultsKey)
    }

    private func loadPendingPresentation() -> PendingPostUpdateReleaseNotes? {
        guard let data = defaults.data(forKey: Self.pendingDefaultsKey) else {
            return nil
        }
        guard let pending = try? decoder.decode(PendingPostUpdateReleaseNotes.self, from: data) else {
            defaults.removeObject(forKey: Self.pendingDefaultsKey)
            return nil
        }
        return pending
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = parseVersionComponents(lhs)
        let right = parseVersionComponents(rhs)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }

    private static func parseVersionComponents(_ raw: String) -> [Int] {
        AppUpdateService.normalizeVersion(raw)
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}
