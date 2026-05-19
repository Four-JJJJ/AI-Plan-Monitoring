import Foundation
import OhMyUsageDomain

enum RelayIconMetadataCatalog {
    static func iconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }
        let relayID = (provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? "").lowercased()
        let relayBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        let host = URL(string: relayBaseURL)?.host?.lowercased() ?? ""
        let providerName = provider.name.lowercased()
        let relaySignals = "\(relayID)|\(host)|\(providerName)"
        if relaySignals.contains("moonshot") || relaySignals.contains("moonsho") || relaySignals.contains("kimi") {
            return "menu_kimi_icon"
        }
        if relaySignals.contains("deepseek") {
            return "menu_deepseek_icon"
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return "menu_mimo_icon"
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return "menu_minimax_icon"
        }
        return nil
    }
}
