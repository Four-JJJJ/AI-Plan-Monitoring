import Foundation
import OhMyUsageApplication
import SwiftUI

extension SettingsView {
    var overlayPresentation: SettingsOverlayPresentation {
        SettingsOverlayPresenter.presentation(
            dialogState: dialogState,
            hasOAuthImportDialog: showsOAuthImportDialog,
            language: viewModel.language,
            text: { viewModel.text($0) }
        )
    }

    var showsResetDataDialog: Bool {
        dialogState.permissionPrompt == .resetLocalData
    }

    var showsCodexProfileEditorDialog: Bool {
        dialogState.codexProfileEditor != nil
    }

    var showsClaudeProfileEditorDialog: Bool {
        dialogState.claudeProfileEditor != nil
    }

    var showsNewAPISiteDialog: Bool {
        dialogState.isNewAPISiteDialogPresented
    }

    var activeOAuthImportDialogState: OAuthImportState? {
        if let codex = viewModel.oauthImportState(for: .codex), codex.isRunning {
            return codex
        }
        if let claude = viewModel.oauthImportState(for: .claude), claude.isRunning {
            return claude
        }
        return nil
    }

    var showsOAuthImportDialog: Bool {
        activeOAuthImportDialogState != nil
    }

    var resetDataConfirmDialog: some View {
        SettingsResetDialogView(
            title: overlayPresentation.resetDialog.title,
            description: overlayPresentation.resetDialog.description,
            cancelTitle: overlayPresentation.resetDialog.cancelTitle,
            confirmTitle: overlayPresentation.resetDialog.confirmTitle,
            onCancel: {
                dialogState.permissionPrompt = nil
            },
            onConfirm: {
                handlePermissionPrompt()
            }
        )
    }

    @ViewBuilder
    func settingsActionButton(
        _ title: String,
        prominent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(destructive ? Color(hex: 0xD83E3E) : nil)
        } else {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(destructive ? Color(hex: 0xD83E3E) : nil)
        }
    }

    @ViewBuilder
    func labeledToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .tint(.green)
            Spacer(minLength: 8)
            toggleStateBadge(isOn: isOn.wrappedValue)
        }
    }

    @ViewBuilder
    func toggleStateBadge(isOn: Bool) -> some View {
        Text(isOn ? viewModel.text(.toggleOn) : viewModel.text(.toggleOff))
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((isOn ? Color.green : Color.red).opacity(0.14))
            )
    }

    func settingsElapsedText(from date: Date) -> String {
        SettingsOverviewPresenter.elapsedText(
            from: date,
            now: runtimeState.settingsNow,
            language: viewModel.language
        )
    }

    func restartSettingsClockIfNeeded() {
        visibleClockController.restartClockIfNeeded(
            isVisible: viewModel.settingsWindowVisible,
            existingTask: &runtimeState.settingsClockTask
        ) { referenceDate in
            tickSettingsClock(referenceDate: referenceDate)
        }
    }

    func stopSettingsClock() {
        visibleClockController.stopClock(existingTask: &runtimeState.settingsClockTask)
    }

    func tickSettingsClock(referenceDate: Date = Date()) {
        visibleClockController.tick(referenceDate: referenceDate) { resolvedDate in
            runtimeState.settingsNow = resolvedDate
        }
    }
}
