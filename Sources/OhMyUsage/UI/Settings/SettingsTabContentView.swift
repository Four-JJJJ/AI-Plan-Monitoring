import SwiftUI

struct SettingsTabContentView<
    Overview: View,
    General: View,
    MenuBar: View,
    Permissions: View,
    LocalData: View,
    OfficialProviders: View,
    CustomProviders: View
>: View {
    var selectedTab: SettingsTab
    var overview: Overview
    var general: General
    var menuBar: MenuBar
    var permissions: Permissions
    var localData: LocalData
    var officialProviders: OfficialProviders
    var customProviders: CustomProviders

    init(
        selectedTab: SettingsTab,
        @ViewBuilder overview: () -> Overview,
        @ViewBuilder general: () -> General,
        @ViewBuilder menuBar: () -> MenuBar,
        @ViewBuilder permissions: () -> Permissions,
        @ViewBuilder localData: () -> LocalData,
        @ViewBuilder officialProviders: () -> OfficialProviders,
        @ViewBuilder customProviders: () -> CustomProviders
    ) {
        self.selectedTab = selectedTab
        self.overview = overview()
        self.general = general()
        self.menuBar = menuBar()
        self.permissions = permissions()
        self.localData = localData()
        self.officialProviders = officialProviders()
        self.customProviders = customProviders()
    }

    var body: some View {
        switch selectedTab {
        case .overview:
            overview
        case .general:
            general
        case .menuBar:
            menuBar
        case .permissions:
            permissions
        case .localData:
            localData
        case .officialProviders:
            officialProviders
        case .customProviders:
            customProviders
        }
    }
}
