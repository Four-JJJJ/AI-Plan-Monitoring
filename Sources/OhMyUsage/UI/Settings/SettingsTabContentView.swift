import SwiftUI

struct SettingsTabContentView<
    Overview: View,
    General: View,
    MenuBar: View,
    UsageAnalytics: View,
    Permissions: View,
    LocalData: View,
    OfficialProviders: View,
    CustomProviders: View,
    Donate: View
>: View {
    var selectedTab: SettingsTab
    var overview: Overview
    var general: General
    var menuBar: MenuBar
    var usageAnalytics: UsageAnalytics
    var permissions: Permissions
    var localData: LocalData
    var officialProviders: OfficialProviders
    var customProviders: CustomProviders
    var donate: Donate

    init(
        selectedTab: SettingsTab,
        @ViewBuilder overview: () -> Overview,
        @ViewBuilder general: () -> General,
        @ViewBuilder menuBar: () -> MenuBar,
        @ViewBuilder usageAnalytics: () -> UsageAnalytics,
        @ViewBuilder permissions: () -> Permissions,
        @ViewBuilder localData: () -> LocalData,
        @ViewBuilder officialProviders: () -> OfficialProviders,
        @ViewBuilder customProviders: () -> CustomProviders,
        @ViewBuilder donate: () -> Donate
    ) {
        self.selectedTab = selectedTab
        self.overview = overview()
        self.general = general()
        self.menuBar = menuBar()
        self.usageAnalytics = usageAnalytics()
        self.permissions = permissions()
        self.localData = localData()
        self.officialProviders = officialProviders()
        self.customProviders = customProviders()
        self.donate = donate()
    }

    var body: some View {
        switch selectedTab {
        case .overview:
            overview
        case .general:
            general
        case .menuBar:
            menuBar
        case .usageAnalytics:
            usageAnalytics
        case .permissions:
            permissions
        case .localData:
            localData
        case .officialProviders:
            officialProviders
        case .customProviders:
            customProviders
        case .donate:
            donate
        }
    }
}
