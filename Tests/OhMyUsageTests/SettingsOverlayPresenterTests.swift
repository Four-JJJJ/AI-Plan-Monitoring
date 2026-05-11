import OhMyUsageApplication
import XCTest
@testable import OhMyUsage

final class SettingsOverlayPresenterTests: XCTestCase {
    func testPresentationBuildsResetDialogCopyAndOverlayFlag() {
        var dialogState = SettingsDialogState()
        dialogState.permissionPrompt = .resetLocalData

        let presentation = SettingsOverlayPresenter.presentation(
            dialogState: dialogState,
            hasOAuthImportDialog: false,
            language: .zhHans,
            text: { _ in "unused" }
        )

        XCTAssertEqual(presentation.activeKind, .resetData)
        XCTAssertTrue(presentation.showsModalOverlay)
        XCTAssertEqual(presentation.resetDialog.title, "重置本地应用数据")
        XCTAssertEqual(presentation.resetDialog.cancelTitle, "我再想想")
        XCTAssertEqual(presentation.resetDialog.confirmTitle, "重置数据")
    }

    func testPresentationPrefersOAuthImportWhenOnlyOAuthAndNewAPISiteAreVisible() {
        var dialogState = SettingsDialogState()
        dialogState.isNewAPISiteDialogPresented = true

        let presentation = SettingsOverlayPresenter.presentation(
            dialogState: dialogState,
            hasOAuthImportDialog: true,
            language: .en,
            text: {
                switch $0 {
                case .resetLocalDataTitle: return "Reset Local App Data"
                case .resetLocalDataConfirm: return "Reset description"
                case .permissionCancel: return "Cancel"
                case .resetLocalDataAction: return "Reset"
                default: return ""
                }
            }
        )

        XCTAssertEqual(presentation.activeKind, .oauthImport)
        XCTAssertTrue(presentation.showsModalOverlay)
        XCTAssertEqual(presentation.resetDialog.title, "Reset Local App Data")
        XCTAssertEqual(presentation.resetDialog.cancelTitle, "Cancel")
        XCTAssertEqual(presentation.resetDialog.confirmTitle, "Reset")
    }
}
