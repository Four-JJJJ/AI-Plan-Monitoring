import Foundation

enum AppVersionResolver {
    static func detectCurrentAppVersion(bundle: Bundle = .main) -> String {
        if let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "0.0.0"
    }

    static func detectNewestInstalledAppVersion(
        fallbackVersion: String,
        fileManager: FileManager = .default
    ) -> String {
        var newest = fallbackVersion
        for bundleURL in candidateInstalledAppBundleURLs(fileManager: fileManager) {
            guard let version = bundleVersion(at: bundleURL, fileManager: fileManager) else { continue }
            if isVersion(version, newerThan: newest) {
                newest = version
            }
        }
        return newest
    }

    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = parseVersionComponents(lhs)
        let right = parseVersionComponents(rhs)
        let maxCount = max(left.count, right.count)

        for index in 0..<maxCount {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func candidateInstalledAppBundleURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []

        if Bundle.main.bundleURL.pathExtension == "app" {
            urls.append(Bundle.main.bundleURL.standardizedFileURL)
        }

        let appBundleNames = ["oh-myusage.app", "AI Plan Monitor.app"]
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        for appBundleName in appBundleNames {
            urls.append(systemApplications.appendingPathComponent(appBundleName).standardizedFileURL)
            urls.append(userApplications.appendingPathComponent(appBundleName).standardizedFileURL)
        }

        var deduped: [URL] = []
        var seen: Set<String> = []
        for url in urls {
            let key = url.path
            if seen.insert(key).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }

    private static func bundleVersion(at bundleURL: URL, fileManager: FileManager = .default) -> String? {
        guard fileManager.fileExists(atPath: bundleURL.path),
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }

        if let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let value = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func parseVersionComponents(_ raw: String) -> [Int] {
        let normalized = AppUpdateService.normalizeVersion(raw)
        return normalized
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}
