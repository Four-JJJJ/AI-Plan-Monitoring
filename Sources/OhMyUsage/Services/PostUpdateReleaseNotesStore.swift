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
    private static let pendingDefaultsKey = "OhMyUsage.PendingPostUpdateReleaseNotes"

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

        if AppVersionResolver.isVersion(normalizedCurrentVersion, newerThan: normalizedPendingVersion) {
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
}
