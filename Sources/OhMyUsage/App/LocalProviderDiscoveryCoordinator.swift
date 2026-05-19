import OhMyUsageDomain
import Foundation

@MainActor
final class LocalProviderDiscoveryCoordinator {
    func discoverLocalProviders(
        candidates: [ProviderDescriptor],
        makeProvider: (ProviderDescriptor) -> UsageProvider,
        handleFetchedSnapshot: @escaping @MainActor (ProviderDescriptor, UsageSnapshot) -> Void,
        clearProviderError: @escaping @MainActor (String) -> Void,
        clearProviderFailures: @escaping @MainActor (String) -> Void,
        markLastUpdatedAt: @escaping @MainActor (Date) -> Void,
        setProviderEnabled: @escaping @MainActor (String) -> Void,
        normalizeStatusBarSelections: @escaping @MainActor () -> Void,
        persistConfiguration: @escaping @MainActor () -> Bool,
        restartPolling: @escaping @MainActor () -> Void,
        notifyStatusBarDisplayConfigChanged: @escaping @MainActor () -> Void,
        displayNameForDiscovery: @escaping (ProviderDescriptor) -> String,
        nothingFoundText: String,
        language: AppLanguage
    ) async -> String {
        guard !candidates.isEmpty else {
            return nothingFoundText
        }

        var discoveredNames: [String] = []
        for descriptor in candidates {
            let provider = makeProvider(descriptor)
            do {
                let fetched = try await provider.fetch(forceRefresh: true)
                handleFetchedSnapshot(descriptor, fetched)
                clearProviderError(descriptor.id)
                clearProviderFailures(descriptor.id)
                markLastUpdatedAt(Date())
                setProviderEnabled(descriptor.id)
                discoveredNames.append(displayNameForDiscovery(descriptor))
            } catch {
                continue
            }
        }

        normalizeStatusBarSelections()
        guard !discoveredNames.isEmpty else {
            return nothingFoundText
        }

        _ = persistConfiguration()
        restartPolling()
        notifyStatusBarDisplayConfigChanged()
        return Localizer.localDiscoveryFoundBody(providerNames: discoveredNames, language: language)
    }
}
