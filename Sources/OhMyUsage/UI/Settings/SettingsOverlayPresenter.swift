import OhMyUsageApplication
import Foundation

struct SettingsResetDialogPresentation: Equatable {
    var title: String
    var description: String
    var cancelTitle: String
    var confirmTitle: String
}

struct SettingsOverlayPresentation: Equatable {
    var activeKind: SettingsModalOverlayKind?
    var showsModalOverlay: Bool
    var resetDialog: SettingsResetDialogPresentation
}

enum SettingsOverlayPresenter {
    static func presentation(
        dialogState: SettingsDialogState,
        hasOAuthImportDialog: Bool,
        language: AppLanguage,
        text: (L10nKey) -> String
    ) -> SettingsOverlayPresentation {
        let activeKind = SettingsModalOverlayKind.resolve(
            showsResetDataDialog: dialogState.permissionPrompt == .resetLocalData,
            showsCodexProfileEditorDialog: dialogState.codexProfileEditor != nil,
            showsClaudeProfileEditorDialog: dialogState.claudeProfileEditor != nil,
            showsOAuthImportDialog: hasOAuthImportDialog,
            showsNewAPISiteDialog: dialogState.isNewAPISiteDialogPresented
        )

        let resetDialog = SettingsResetDialogPresentation(
            title: language == .zhHans ? "重置本地应用数据" : text(.resetLocalDataTitle),
            description: language == .zhHans
                ? "确认后会清理本地配置、Codex 账号槽位、启动项和 oh-myusage 的钥匙串内容。应用会恢复成接近首次安装状态；系统通知、全盘访问等 macOS 授权不会被自动撤销"
                : text(.resetLocalDataConfirm),
            cancelTitle: language == .zhHans ? "我再想想" : text(.permissionCancel),
            confirmTitle: language == .zhHans ? "重置数据" : text(.resetLocalDataAction)
        )

        return SettingsOverlayPresentation(
            activeKind: activeKind,
            showsModalOverlay: activeKind != nil,
            resetDialog: resetDialog
        )
    }
}
