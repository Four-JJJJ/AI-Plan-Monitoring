import Foundation

struct AppUpdateInfo: Equatable {
    var latestVersion: String
    var releaseURL: URL
    var downloadURL: URL?
}

actor AppUpdateService {
    static let repositoryURL = URL(string: "https://github.com/Four-JJJJ/AI-Plan-Monitor")!
    static let releasesURL = URL(string: "https://github.com/Four-JJJJ/AI-Plan-Monitor/releases/latest")!

    private struct GitHubRelease: Decodable {
        var tagName: String
        var htmlURL: URL
        var assets: [Asset]

        struct Asset: Decodable {
            var name: String
            var browserDownloadURL: URL

            private enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private let session: URLSession
    private let latestReleaseURL: URL

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(string: "https://api.github.com/repos/Four-JJJJ/AI-Plan-Monitor/releases/latest")!
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    func fetchLatestRelease() async throws -> AppUpdateInfo {
        var request = URLRequest(url: latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let normalized = Self.normalizeVersion(release.tagName)
        let dmgAsset = release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        return AppUpdateInfo(
            latestVersion: normalized,
            releaseURL: release.htmlURL,
            downloadURL: dmgAsset?.browserDownloadURL
        )
    }

    static func normalizeVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
