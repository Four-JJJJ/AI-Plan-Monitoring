import Foundation
import XCTest

final class MonolithRetirementBoundaryTests: XCTestCase {
    func testCoordinatorsAndPresentersDoNotDependOnAppViewModelNestedDisplayTypes() throws {
        let files = [
            "Sources/OhMyUsage/App/AppConfigurationMutationCoordinator.swift",
            "Sources/OhMyUsage/App/AppSettingsPersistenceFeedbackCoordinator.swift",
            "Sources/OhMyUsage/UI/Presenters/MenuDashboardPresenter.swift"
        ]

        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for file in files {
            let fileURL = rootURL.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("AppViewModel."),
                "\(file) should use top-level display models instead of AppViewModel nested types"
            )
        }

        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        for nestedDefinition in [
            "enum UpdateDisplayTone",
            "struct SettingsUpdateDisplayState",
            "struct MenuUpdateDisplayState",
            "struct SettingsPersistenceDisplayState"
        ] {
            XCTAssertFalse(
                appViewModel.contains(nestedDefinition),
                "AppViewModel.swift should not re-own \(nestedDefinition)"
            )
        }
    }

    func testProviderMetadataCatalogLivesWithProviderModels() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderMetadataCatalog.swift")
        let serviceCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/ProviderMetadataCatalog.swift")
        let presentationModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderPresentationModels.swift")
        let catalogSource = try String(contentsOf: modelCatalogURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: modelCatalogURL.path),
            "ProviderMetadataCatalog should stay beside provider model policy instead of living in Services"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: serviceCatalogURL.path),
            "ProviderMetadataCatalog is pure provider metadata and should not create a Models -> Services dependency"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: presentationModelsURL.path),
            "ProviderPresentation and ProviderCapabilities should be model values, not service facade types"
        )
        XCTAssertFalse(
            catalogSource.contains("Bundle.module"),
            "ProviderMetadataCatalog should not reach into package resources while it lives with model policy"
        )
    }

    func testProviderMetadataCatalogStaysAsFacadeOverFocusedMetadataCatalogs() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let modelCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderMetadataCatalog.swift")
        let relayCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/OfficialRelayMetadataCatalog.swift")
        let typeCatalogURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderTypeMetadataCatalog.swift")
        let catalogSource = try String(contentsOf: modelCatalogURL, encoding: .utf8)
        let catalogLineCount = catalogSource.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(
            catalogLineCount,
            180,
            "ProviderMetadataCatalog should stay as a small facade after splitting type and relay metadata"
        )
        XCTAssertFalse(
            catalogSource.contains("officialRelayMetadata"),
            "ProviderMetadataCatalog should not directly own the official relay metadata array"
        )
        XCTAssertFalse(
            catalogSource.contains("providerTypeMetadata"),
            "ProviderMetadataCatalog should not directly own provider type metadata"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: relayCatalogURL.path),
            "Official relay metadata should live in OfficialRelayMetadataCatalog"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: typeCatalogURL.path),
            "Provider type metadata should live in ProviderTypeMetadataCatalog"
        )
    }

    func testProviderModelsDoesNotOwnAppConfigDefinition() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for appConfigResponsibility in [
            "struct AppConfig",
            "migratedWithSiteDefaults",
            "migrateOfficialRelayProvidersToStableIDs"
        ] {
            XCTAssertFalse(
                providerModels.contains(appConfigResponsibility),
                "ProviderModels.swift should keep provider descriptors separate from app-level configuration models"
            )
        }

        let appConfigURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfigModels.swift")
        let appConfigModels = try String(contentsOf: appConfigURL, encoding: .utf8)
        XCTAssertTrue(appConfigModels.contains("struct AppConfig"))

        let appConfigMigrationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AppConfig+SiteDefaultsMigration.swift")
        let appConfigMigration = try String(contentsOf: appConfigMigrationURL, encoding: .utf8)
        XCTAssertTrue(appConfigMigration.contains("migratedWithSiteDefaults"))
    }

    func testProviderModelsDoesNotOwnAuthConfigCredentialHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        XCTAssertFalse(providerModels.contains("extension AuthConfig"))

        let authHelpersURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/AuthConfig+CredentialHelpers.swift")
        let authHelpers = try String(contentsOf: authHelpersURL, encoding: .utf8)
        XCTAssertTrue(authHelpers.contains("func withFallback"))
        XCTAssertTrue(authHelpers.contains("func normalizedCredentialServiceName"))
    }

    func testProviderModelsDoesNotOwnDefaultProviderConstructors() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for defaultConstructor in [
            "defaultOfficialCodex",
            "defaultOfficialRelaySite",
            "defaultOpenAilinyu",
            "defaultHongmacc"
        ] {
            XCTAssertFalse(
                providerModels.contains(defaultConstructor),
                "ProviderModels.swift should keep default provider constructors in ProviderDescriptor+Defaults.swift"
            )
        }

        let defaultsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+Defaults.swift")
        let defaults = try String(contentsOf: defaultsURL, encoding: .utf8)
        XCTAssertTrue(defaults.contains("defaultOfficialCodex"))
        XCTAssertTrue(defaults.contains("defaultOpenAilinyu"))
    }

    func testProviderModelsDoesNotOwnProviderDefaultConfigurationHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for defaultHelper in [
            "static func defaultOfficialBaseURL",
            "static func defaultOfficialConfig",
            "static func defaultKimiConfig"
        ] {
            XCTAssertFalse(
                providerModels.contains(defaultHelper),
                "ProviderModels.swift should keep provider default configuration helpers in ProviderDescriptor+OfficialDefaults.swift"
            )
        }

        let officialDefaultsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+OfficialDefaults.swift")
        let officialDefaults = try String(contentsOf: officialDefaultsURL, encoding: .utf8)
        XCTAssertTrue(officialDefaults.contains("defaultOfficialConfig"))
        XCTAssertTrue(officialDefaults.contains("defaultKimiConfig"))
    }

    func testProviderModelsDoesNotOwnOfficialRelayMetadataPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for relayMetadataResponsibility in [
            "var officialRelayAdapterID",
            "var isOfficialRelayProvider",
            "static var officialRelayDefaultProviderIDs",
            "static func officialRelayDefaultBaseURL"
        ] {
            XCTAssertFalse(
                providerModels.contains(relayMetadataResponsibility),
                "ProviderModels.swift should keep official relay metadata policy in ProviderDescriptor+OfficialRelayMetadata.swift"
            )
        }

        let metadataURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+OfficialRelayMetadata.swift")
        let metadata = try String(contentsOf: metadataURL, encoding: .utf8)
        XCTAssertTrue(metadata.contains("isOfficialRelayProvider"))
        XCTAssertTrue(metadata.contains("ProviderMetadataCatalog.officialRelayDefaultProviderIDs"))
    }

    func testProviderModelsDoesNotOwnRelayDefaultAndOverrideMigrationHelpers() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for relayHelperDefinition in [
            "static func makeOpenRelay",
            "static func defaultRelayConfig",
            "static func defaultRelayBalanceAccount",
            "static func normalizeRelayBaseURL",
            "func looksLikeGenericDefaultOverride",
            "func migrateGenericNewAPIDefaultOverride",
            "func looksLikeTemplateDefaultOverride"
        ] {
            XCTAssertFalse(
                providerModels.contains(relayHelperDefinition),
                "ProviderModels.swift should keep relay defaults and override migration helpers in focused ProviderDescriptor extensions"
            )
        }

        let relayDefaultsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+RelayDefaults.swift")
        let relayDefaults = try String(contentsOf: relayDefaultsURL, encoding: .utf8)
        XCTAssertTrue(relayDefaults.contains("static func defaultRelayConfig"))
        XCTAssertTrue(relayDefaults.contains("static func normalizeRelayBaseURL"))

        let relayOverrideURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+RelayOverrideMigration.swift")
        let relayOverride = try String(contentsOf: relayOverrideURL, encoding: .utf8)
        XCTAssertTrue(relayOverride.contains("migrateGenericNewAPIDefaultOverride"))
        XCTAssertTrue(relayOverride.contains("looksLikeTemplateDefaultOverride"))
    }

    func testProviderModelsDoesNotOwnLegacyRelayMigrationPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for legacyRelayMigrationDefinition in [
            "var legacyRelayImportIdentity",
            "var isLegacyRelayExample"
        ] {
            XCTAssertFalse(
                providerModels.contains(legacyRelayMigrationDefinition),
                "ProviderModels.swift should keep legacy relay migration policy in ProviderDescriptor+LegacyRelayMigration.swift"
            )
        }

        let migrationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+LegacyRelayMigration.swift")
        let migration = try String(contentsOf: migrationURL, encoding: .utf8)
        XCTAssertTrue(migration.contains("legacyRelayImportIdentity"))
        XCTAssertTrue(migration.contains("isLegacyRelayExample"))
    }

    func testProviderModelsDoesNotOwnRelayViewOrDisplayPreferenceDerivations() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        for derivedProperty in [
            "var relayManifest",
            "var relayDisplayMode",
            "var relayViewConfig",
            "var displaysUsedQuota",
            "var traeDisplaysAmount",
            "var supportedOfficialSourceModes",
            "var supportsOfficialManualCookieInput"
        ] {
            XCTAssertFalse(
                providerModels.contains(derivedProperty),
                "ProviderModels.swift should keep relay view and display preference derivations in focused ProviderDescriptor extensions"
            )
        }

        let relayViewURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+RelayViewConfig.swift")
        let relayView = try String(contentsOf: relayViewURL, encoding: .utf8)
        XCTAssertTrue(relayView.contains("relayViewConfig"))
        XCTAssertTrue(relayView.contains("relayManifest"))

        let displayPreferencesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+DisplayPreferences.swift")
        let displayPreferences = try String(contentsOf: displayPreferencesURL, encoding: .utf8)
        XCTAssertTrue(displayPreferences.contains("displaysUsedQuota"))
        XCTAssertTrue(displayPreferences.contains("supportsOfficialManualCookieInput"))
    }

    func testProviderModelsDoesNotOwnNormalizationPolicy() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let providerModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderModels.swift")
        let providerModels = try String(contentsOf: providerModelsURL, encoding: .utf8)

        XCTAssertFalse(
            providerModels.contains("func normalized()"),
            "ProviderModels.swift should keep normalization policy in ProviderDescriptor+Normalization.swift"
        )

        let normalizationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/ProviderDescriptor+Normalization.swift")
        let normalization = try String(contentsOf: normalizationURL, encoding: .utf8)
        XCTAssertTrue(normalization.contains("func normalized()"))
        XCTAssertTrue(normalization.contains("normalizedOfficialProvider"))
        XCTAssertTrue(normalization.contains("normalizedRelayProvider"))
        XCTAssertTrue(normalization.contains("normalizedKimiProvider"))
    }

    func testSettingsDraftModelsDelegateRelaySeedDerivation() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let settingsDraftModelsURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Models/SettingsDraftModels.swift")
        let settingsDraftModels = try String(contentsOf: settingsDraftModelsURL, encoding: .utf8)

        XCTAssertTrue(settingsDraftModels.contains("RelaySettingsDraftSeed"))
        XCTAssertFalse(
            settingsDraftModels.contains("relayViewConfig"),
            "SettingsDraftModels.swift should use RelaySettingsDraftSeed instead of deriving relay view config directly"
        )
    }

    func testModelRelayDescriptorDerivationsUseResolverInsteadOfSharedRegistry() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = [
            "Sources/OhMyUsage/Models/RelaySettingsDraftSeed.swift",
            "Sources/OhMyUsage/Models/ProviderDescriptor+OfficialRelayMetadata.swift",
            "Sources/OhMyUsage/Models/ProviderDescriptor+LegacyRelayMigration.swift"
        ]

        for file in files {
            let fileURL = rootURL.appendingPathComponent(file)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(
                source.contains("RelayAdapterRegistry.shared"),
                "\(file) should resolve relay descriptors through RelayProviderDescriptorResolver instead of the shared registry"
            )
        }
    }

    func testAppViewModelDelegatesUsageAnalyticsRefresh() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(appViewModel.contains("UsageAnalyticsRefreshCoordinator"))
        for directDependency in [
            "UsageAnalyticsRepository",
            "UsageAnalyticsSnapshotCacheStore",
            "usageAnalyticsRefreshTask",
            "usageAnalyticsRefreshGeneration"
        ] {
            XCTAssertFalse(
                appViewModel.contains(directDependency),
                "AppViewModel.swift should delegate usage analytics refresh internals instead of owning \(directDependency)"
            )
        }
    }

    func testAppViewModelStatusBarDisplayResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let statusBarDisplayURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+StatusBarDisplay.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: statusBarDisplayURL.path),
            "Status bar display preferences should live in AppViewModel+StatusBarDisplay.swift"
        )

        if FileManager.default.fileExists(atPath: statusBarDisplayURL.path) {
            let statusBarDisplay = try String(contentsOf: statusBarDisplayURL, encoding: .utf8)
            for focusedResponsibility in [
                "statusBarDisplayConfigDidChangeNotification",
                "func setStatusBarProvider",
                "func setStatusBarDisplayEnabled",
                "func applyStatusBarPreferencesMutation",
                "func notifyStatusBarDisplayConfigChanged"
            ] {
                XCTAssertTrue(
                    statusBarDisplay.contains(focusedResponsibility),
                    "AppViewModel+StatusBarDisplay.swift should own \(focusedResponsibility)"
                )
            }
        }

        for appViewModelResponsibility in [
            "statusBarDisplayConfigDidChangeNotification",
            "func setStatusBarProvider",
            "func setStatusBarDisplayEnabled",
            "func applyStatusBarPreferencesMutation",
            "func notifyStatusBarDisplayConfigChanged"
        ] {
            XCTAssertFalse(
                appViewModel.contains(appViewModelResponsibility),
                "AppViewModel.swift should delegate status bar display responsibilities instead of owning \(appViewModelResponsibility)"
            )
        }
    }

    func testAppViewModelOfficialProfileResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let officialProfilesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+OfficialProfiles.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: officialProfilesURL.path),
            "Official profile menu, OAuth import, save/remove, and switching responsibilities should live in AppViewModel+OfficialProfiles.swift"
        )

        if FileManager.default.fileExists(atPath: officialProfilesURL.path) {
            let officialProfiles = try String(contentsOf: officialProfilesURL, encoding: .utf8)
            for focusedResponsibility in [
                "func codexSlotViewModels()",
                "func claudeSlotViewModels()",
                "func oauthImportState(for providerType: ProviderType)",
                "func startOAuthImport(providerType: ProviderType, slotID: CodexSlotID)",
                "func cancelOAuthImport(providerType: ProviderType)",
                "func saveCodexProfile(slotID: CodexSlotID, displayName: String, note: String?, authJSON: String)",
                "func removeCodexProfile(slotID: CodexSlotID)",
                "func saveClaudeProfile(",
                "func removeClaudeProfile(slotID: CodexSlotID)",
                "func switchCodexProfile(slotID: CodexSlotID) async",
                "func switchClaudeProfile(slotID: CodexSlotID) async"
            ] {
                XCTAssertTrue(
                    officialProfiles.contains(focusedResponsibility),
                    "AppViewModel+OfficialProfiles.swift should own \(focusedResponsibility)"
                )
                XCTAssertFalse(
                    appViewModel.contains(focusedResponsibility),
                    "AppViewModel.swift should delegate official profile responsibilities instead of owning \(focusedResponsibility)"
                )
            }
        }
    }

    func testUsageAnalyticsValueTypesLiveInApplicationTarget() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let applicationTypesURL = rootURL.appendingPathComponent("Sources/OhMyUsageApplication/UsageAnalyticsTypes.swift")
        let executableTypesURL = rootURL.appendingPathComponent("Sources/OhMyUsage/Services/UsageAnalyticsTypes.swift")
        let executableTypes = try String(contentsOf: executableTypesURL, encoding: .utf8)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: applicationTypesURL.path),
            "Usage analytics pure value types should move into the application target"
        )

        if FileManager.default.fileExists(atPath: applicationTypesURL.path) {
            let applicationTypes = try String(contentsOf: applicationTypesURL, encoding: .utf8)
            for valueTypeDefinition in [
                "struct UsageMetricTotals",
                "enum UsageAnalyticsFilterMode",
                "enum UsageAnalyticsRange",
                "struct UsageAnalyticsFilter",
                "enum UsageAnalyticsRecordSource",
                "struct UsageAnalyticsRecord",
                "struct UsageAnalyticsSnapshot"
            ] {
                XCTAssertTrue(
                    applicationTypes.contains(valueTypeDefinition),
                    "OhMyUsageApplication should own \(valueTypeDefinition)"
                )
            }
        }

        for executableDefinition in [
            "struct UsageMetricTotals",
            "enum UsageAnalyticsFilterMode",
            "enum UsageAnalyticsRange",
            "struct UsageAnalyticsFilter",
            "enum UsageAnalyticsRecordSource",
            "struct UsageAnalyticsRecord",
            "struct UsageAnalyticsSnapshot"
        ] {
            XCTAssertFalse(
                executableTypes.contains(executableDefinition),
                "Executable Services should import usage analytics value types instead of owning \(executableDefinition)"
            )
        }
    }

    func testAppViewModelDoesNotOwnPermissionAndResetImplementations() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)

        for implementationSignature in [
            "func openSystemSettings(",
            "func resetLocalAppData()",
            "func refreshPermissionStatuses("
        ] {
            XCTAssertFalse(
                appViewModel.contains(implementationSignature),
                "AppViewModel.swift should move \(implementationSignature) into focused AppViewModel extensions"
            )
        }
    }

    func testAppViewModelProviderConfigurationResponsibilitiesStayInFocusedExtension() throws {
        let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appViewModelURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel.swift")
        let providerConfigurationURL = rootURL.appendingPathComponent("Sources/OhMyUsage/App/AppViewModel+ProviderConfiguration.swift")
        let appViewModel = try String(contentsOf: appViewModelURL, encoding: .utf8)
        let appViewModelLineCount = appViewModel.split(separator: "\n", omittingEmptySubsequences: false).count

        XCTAssertLessThanOrEqual(
            appViewModelLineCount,
            1200,
            "AppViewModel.swift should stay below the provider configuration split budget"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: providerConfigurationURL.path),
            "Provider, credential, relay, and official settings responsibilities should live in AppViewModel+ProviderConfiguration.swift"
        )

        guard FileManager.default.fileExists(atPath: providerConfigurationURL.path) else {
            return
        }

        let providerConfiguration = try String(contentsOf: providerConfigurationURL, encoding: .utf8)
        for focusedResponsibility in [
            "func setEnabled(",
            "func reorderEnabledProviders(",
            "func setLowThreshold(",
            "func commitProviderThreshold(",
            "func hasToken(for descriptor:",
            "func savedTokenLength(for descriptor:",
            "func saveToken(_ token: String, for descriptor:",
            "func saveTokenAndRestart(_ token: String, for descriptor:",
            "func saveToken(_ token: String, auth:",
            "func saveTokenAndRestart(_ token: String, auth:",
            "func hasOfficialManualCookie(",
            "func savedOfficialManualCookieLength(",
            "func saveOfficialManualCookie(",
            "func saveOfficialManualCookieAndRestart(",
            "func invalidateCredentialLookupCache()",
            "func addRelaySiteDraft(",
            "func addOpenRelay(",
            "func removeProvider(providerID:",
            "func updateOpenProviderSettings(",
            "func saveRelayDraft(",
            "func relayDescriptorForPreview(",
            "func testRelayDraft(",
            "func importRelayDraftFromBrowser(",
            "func updateThirdPartyQuotaDisplayMode(",
            "func relayAdapterName(",
            "func relayAuthSource(",
            "func relayFetchHealth(",
            "func relayValueFreshness(",
            "func testRelayConnection(providerID:",
            "func testRelayConnection(descriptor:",
            "func updateOfficialProviderSettings(",
            "func saveOfficialDraft(",
            "func saveOfficialCredentialAndSettings("
        ] {
            XCTAssertTrue(
                providerConfiguration.contains(focusedResponsibility),
                "AppViewModel+ProviderConfiguration.swift should own \(focusedResponsibility)"
            )
            XCTAssertFalse(
                appViewModel.contains(focusedResponsibility),
                "AppViewModel.swift should not re-own provider configuration responsibility \(focusedResponsibility)"
            )
        }
    }
}
