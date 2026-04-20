import AppKit
import CryptoKit
import Foundation

struct AppUpdateAsset: Equatable {
    var url: URL
    var sha256: String?
    var size: Int64?
}

struct AppUpdateInfo: Equatable {
    var latestVersion: String
    var releaseURL: URL
    var notesURL: URL?
    var publishedAt: Date?
    var zipAsset: AppUpdateAsset?
    var dmgAsset: AppUpdateAsset?

    var downloadURL: URL? {
        zipAsset?.url ?? dmgAsset?.url
    }
}

struct PreparedAppUpdate {
    var version: String
    var appBundleURL: URL
    var workingDirectoryURL: URL
}

enum AppUpdateError: LocalizedError {
    case invalidMetadata
    case missingZipAsset
    case checksumMismatch
    case extractedAppNotFound
    case unsupportedInstallLocation

    var errorDescription: String? {
        switch self {
        case .invalidMetadata:
            return "Invalid update metadata"
        case .missingZipAsset:
            return "No macOS ZIP asset is available for automatic update"
        case .checksumMismatch:
            return "Downloaded update checksum mismatch"
        case .extractedAppNotFound:
            return "Updated app bundle was not found in the extracted archive"
        case .unsupportedInstallLocation:
            return "Automatic update requires running from an .app bundle"
        }
    }
}

actor AppUpdateService {
    static let owner = "Four-JJJJ"
    static let repository = "AI-Plan-Monitor"
    static let repositoryURL = URL(string: "https://github.com/\(owner)/\(repository)")!
    static let releasesURL = URL(string: "https://github.com/\(owner)/\(repository)/releases/latest")!
    static let metadataURL = URL(string: "https://github.com/\(owner)/\(repository)/releases/latest/download/latest.json")!

    private struct ReleaseManifest: Decodable {
        var version: String
        var pubDate: Date?
        var releaseURL: URL?
        var notesURL: URL?
        var assets: Assets

        struct Assets: Decodable {
            var macOSZip: Asset?
            var macOSDMG: Asset?

            private enum CodingKeys: String, CodingKey {
                case macOSZip = "macos_zip"
                case macOSDMG = "macos_dmg"
            }
        }

        struct Asset: Decodable {
            var url: URL
            var sha256: String?
            var size: Int64?
        }

        private enum CodingKeys: String, CodingKey {
            case version
            case pubDate = "pub_date"
            case releaseURL = "release_url"
            case notesURL = "notes_url"
            case assets
        }
    }

    private let session: URLSession
    private let latestMetadataURL: URL
    private let fileManager: FileManager

    init(
        session: URLSession = .shared,
        latestMetadataURL: URL = metadataURL,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.latestMetadataURL = latestMetadataURL
        self.fileManager = fileManager
    }

    func fetchLatestRelease() async throws -> AppUpdateInfo {
        var request = URLRequest(url: latestMetadataURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ReleaseManifest.self, from: data)
        let normalizedVersion = Self.normalizeVersion(manifest.version)
        guard !normalizedVersion.isEmpty else {
            throw AppUpdateError.invalidMetadata
        }

        return AppUpdateInfo(
            latestVersion: normalizedVersion,
            releaseURL: manifest.releaseURL ?? Self.releasesURL,
            notesURL: manifest.notesURL,
            publishedAt: manifest.pubDate,
            zipAsset: manifest.assets.macOSZip.map { AppUpdateAsset(url: $0.url, sha256: $0.sha256, size: $0.size) },
            dmgAsset: manifest.assets.macOSDMG.map { AppUpdateAsset(url: $0.url, sha256: $0.sha256, size: $0.size) }
        )
    }

    func prepareUpdate(_ update: AppUpdateInfo) async throws -> PreparedAppUpdate {
        guard let asset = update.zipAsset else {
            throw AppUpdateError.missingZipAsset
        }

        let root = fileManager.temporaryDirectory
            .appendingPathComponent("AIPlanMonitorUpdate-\(UUID().uuidString)", isDirectory: true)
        let downloadURL = root.appendingPathComponent("AIPlanMonitorUpdate.zip")
        let extractRoot = root.appendingPathComponent("Extracted", isDirectory: true)

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: extractRoot, withIntermediateDirectories: true)

        var request = URLRequest(url: asset.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.setValue("AIPlanMonitor", forHTTPHeaderField: "User-Agent")

        let (temporaryFileURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if fileManager.fileExists(atPath: downloadURL.path) {
            try fileManager.removeItem(at: downloadURL)
        }
        try fileManager.moveItem(at: temporaryFileURL, to: downloadURL)

        if let expectedHash = asset.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedHash.isEmpty {
            let actualHash = try Self.sha256Hex(for: downloadURL)
            if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                throw AppUpdateError.checksumMismatch
            }
        }

        try Self.runProcess(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", downloadURL.path, extractRoot.path]
        )

        guard let appBundleURL = Self.findAppBundle(in: extractRoot, fileManager: fileManager) else {
            throw AppUpdateError.extractedAppNotFound
        }

        return PreparedAppUpdate(
            version: update.latestVersion,
            appBundleURL: appBundleURL,
            workingDirectoryURL: root
        )
    }

    func installPreparedUpdate(_ prepared: PreparedAppUpdate, over currentAppURL: URL = Bundle.main.bundleURL) throws {
        let standardizedCurrentAppURL = currentAppURL.standardizedFileURL
        guard standardizedCurrentAppURL.pathExtension == "app" else {
            throw AppUpdateError.unsupportedInstallLocation
        }

        let installerScriptURL = prepared.workingDirectoryURL.appendingPathComponent("install_update.sh")
        let sourceAppURL = prepared.appBundleURL.standardizedFileURL
        let targetAppURL = standardizedCurrentAppURL
        let backupAppURL = prepared.workingDirectoryURL
            .appendingPathComponent("\(targetAppURL.deletingPathExtension().lastPathComponent) Backup.app")
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = Self.installScript(
            sourceAppPath: sourceAppURL.path,
            targetAppPath: targetAppURL.path,
            backupAppPath: backupAppURL.path,
            workingDirectoryPath: prepared.workingDirectoryURL.path,
            pid: pid
        )
        try script.write(to: installerScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installerScriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [installerScriptURL.path]
        try process.run()
    }

    static func normalizeVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            if data.isEmpty {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func findAppBundle(in root: URL, fileManager: FileManager) -> URL? {
        if root.pathExtension == "app" {
            return root
        }

        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app" {
                return item
            }
        }
        return nil
    }

    private static func runProcess(executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "AppUpdateService.Process",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? message! : "Update helper process failed"]
            )
        }
    }

    private static func installScript(
        sourceAppPath: String,
        targetAppPath: String,
        backupAppPath: String,
        workingDirectoryPath: String,
        pid: Int32
    ) -> String {
        let source = shellSingleQuoted(sourceAppPath)
        let target = shellSingleQuoted(targetAppPath)
        let backup = shellSingleQuoted(backupAppPath)
        let workingDir = shellSingleQuoted(workingDirectoryPath)

        return """
        #!/bin/sh
        set -eu

        SOURCE_APP=\(source)
        TARGET_APP=\(target)
        BACKUP_APP=\(backup)
        WORKING_DIR=\(workingDir)
        TARGET_DIR="$(dirname "$TARGET_APP")"
        STAGING_APP="$TARGET_DIR/.AI Plan Monitor.update.app"
        PID_TO_WAIT=\(pid)

        wait_for_exit() {
          while kill -0 "$PID_TO_WAIT" 2>/dev/null; do
            sleep 1
          done
          sleep 1
        }

        install_without_privileges() {
          rm -rf "$STAGING_APP" "$BACKUP_APP"
          /usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
          /usr/bin/xattr -dr com.apple.quarantine "$STAGING_APP" >/dev/null 2>&1 || true
          if [ -e "$TARGET_APP" ]; then
            mv "$TARGET_APP" "$BACKUP_APP"
          fi
          mv "$STAGING_APP" "$TARGET_APP"
        }

        install_with_privileges() {
          /usr/bin/osascript <<APPLESCRIPT
        do shell script "rm -rf " & quoted form of "$STAGING_APP" & " " & quoted form of "$BACKUP_APP" & "; " & ¬
          "/usr/bin/ditto " & quoted form of "$SOURCE_APP" & " " & quoted form of "$STAGING_APP" & "; " & ¬
          "/usr/bin/xattr -dr com.apple.quarantine " & quoted form of "$STAGING_APP" & " >/dev/null 2>&1 || true; " & ¬
          "if [ -e " & quoted form of "$TARGET_APP" & " ]; then mv " & quoted form of "$TARGET_APP" & " " & quoted form of "$BACKUP_APP" & "; fi; " & ¬
          "mv " & quoted form of "$STAGING_APP" & " " & quoted form of "$TARGET_APP" with administrator privileges
        APPLESCRIPT
        }

        wait_for_exit

        if [ -w "$TARGET_DIR" ] && { [ ! -e "$TARGET_APP" ] || [ -w "$TARGET_APP" ]; }; then
          install_without_privileges
        else
          install_with_privileges
        fi

        /usr/bin/open "$TARGET_APP"
        rm -rf "$BACKUP_APP"
        rm -rf "$WORKING_DIR"
        exit 0
        """
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
