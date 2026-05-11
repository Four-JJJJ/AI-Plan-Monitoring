import Foundation
import OhMyUsageApplication

struct SettingsResourceDiagnosticRowPresentation: Equatable, Identifiable {
    var id: String
    var title: String
    var value: String
    var detail: String
}

struct SettingsResourceDiagnosticsPresentation: Equatable {
    var title: String
    var rows: [SettingsResourceDiagnosticRowPresentation]
}

enum SettingsResourceDiagnosticsPresenter {
    static func presentation(
        diagnostics: RuntimeMemoryDiagnostics,
        localizedText: (String, String) -> String
    ) -> SettingsResourceDiagnosticsPresentation {
        let totalProfiles = diagnostics.codexProfileCount + diagnostics.claudeProfileCount
        let inFlightPrefetches = diagnostics.codexPrefetchInFlightCount + diagnostics.claudePrefetchInFlightCount
        let enabledProviderCount = max(diagnostics.enabledProviderCount, 0)
        let healthyProviderCount = max(enabledProviderCount - diagnostics.providerErrorCount, 0)

        return SettingsResourceDiagnosticsPresentation(
            title: localizedText("概览", "Overview"),
            rows: [
                SettingsResourceDiagnosticRowPresentation(
                    id: "snapshots",
                    title: localizedText("快照", "Snapshots"),
                    value: "\(diagnostics.snapshotCount)",
                    detail: localizedText("Provider 快照", "Provider snapshots")
                ),
                SettingsResourceDiagnosticRowPresentation(
                    id: "polls",
                    title: localizedText("刷新", "Refresh"),
                    value: "\(diagnostics.pollTaskCount)",
                    detail: localizedText("活跃轮询任务", "Active poll tasks")
                ),
                SettingsResourceDiagnosticRowPresentation(
                    id: "health",
                    title: localizedText("健康", "Health"),
                    value: "\(healthyProviderCount)/\(enabledProviderCount)",
                    detail: localizedText(
                        "正常 Provider · 异常 \(diagnostics.providerErrorCount)",
                        "Healthy providers · \(diagnostics.providerErrorCount) in error"
                    )
                ),
                SettingsResourceDiagnosticRowPresentation(
                    id: "profiles",
                    title: localizedText("账号", "Profiles"),
                    value: "\(totalProfiles)",
                    detail: localizedText(
                        "Codex \(diagnostics.codexProfileCount) · Claude \(diagnostics.claudeProfileCount)",
                        "Codex \(diagnostics.codexProfileCount) · Claude \(diagnostics.claudeProfileCount)"
                    )
                ),
                SettingsResourceDiagnosticRowPresentation(
                    id: "prefetch",
                    title: localizedText("预取", "Prefetch"),
                    value: "\(inFlightPrefetches)",
                    detail: localizedText(
                        "进行中 · 已尝试 \(diagnostics.codexPrefetchAttemptedIdentityCount + diagnostics.claudePrefetchAttemptedIdentityCount)",
                        "In flight · \(diagnostics.codexPrefetchAttemptedIdentityCount + diagnostics.claudePrefetchAttemptedIdentityCount) attempted"
                    )
                )
            ]
        )
    }
}
