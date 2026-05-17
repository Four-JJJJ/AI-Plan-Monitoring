import Foundation

enum ProviderPresentationRegistry {
    static func presentation(for provider: ProviderDescriptor?) -> ProviderPresentation {
        ProviderDefinitionRegistry.presentation(for: provider)
    }

    static func displayName(for provider: ProviderDescriptor?) -> String {
        ProviderDefinitionRegistry.presentation(for: provider).displayName
    }

    static func iconName(for provider: ProviderDescriptor?) -> String {
        ProviderDefinitionRegistry.presentation(for: provider).iconName
    }

    static func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        ProviderDefinitionRegistry.presentation(for: provider).fallbackSystemIcon
    }
}

enum QuotaMetricDisplayFactory {
    static func preferredMetricCount(for provider: ProviderDescriptor) -> Int {
        ProviderDefinitionRegistry.preferredMetricCount(for: provider)
    }
}
