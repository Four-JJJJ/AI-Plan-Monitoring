import Foundation
@testable import OhMyUsage

func makeTestKeychain(fileManager: FileManager = .default) -> KeychainService {
    KeychainService(storageURL: makeTestKeychainStorageURL(fileManager: fileManager))
}

func makeTestKeychainStorageURL(fileManager: FileManager = .default) -> URL {
    fileManager.temporaryDirectory
        .appendingPathComponent("OhMyUsageTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("keychain.json")
}
