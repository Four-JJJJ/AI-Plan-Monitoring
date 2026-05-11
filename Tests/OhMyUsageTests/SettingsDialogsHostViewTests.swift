import XCTest
@testable import OhMyUsage

final class SettingsDialogsHostViewTests: XCTestCase {
    func testResolvePrefersResetThenProfileEditorsThenOAuthThenNewAPISite() {
        XCTAssertEqual(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: true,
                showsCodexProfileEditorDialog: true,
                showsClaudeProfileEditorDialog: true,
                showsOAuthImportDialog: true,
                showsNewAPISiteDialog: true
            ),
            .resetData
        )
        XCTAssertEqual(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: false,
                showsCodexProfileEditorDialog: true,
                showsClaudeProfileEditorDialog: true,
                showsOAuthImportDialog: true,
                showsNewAPISiteDialog: true
            ),
            .codexProfileEditor
        )
        XCTAssertEqual(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: false,
                showsCodexProfileEditorDialog: false,
                showsClaudeProfileEditorDialog: true,
                showsOAuthImportDialog: true,
                showsNewAPISiteDialog: true
            ),
            .claudeProfileEditor
        )
        XCTAssertEqual(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: false,
                showsCodexProfileEditorDialog: false,
                showsClaudeProfileEditorDialog: false,
                showsOAuthImportDialog: true,
                showsNewAPISiteDialog: true
            ),
            .oauthImport
        )
        XCTAssertEqual(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: false,
                showsCodexProfileEditorDialog: false,
                showsClaudeProfileEditorDialog: false,
                showsOAuthImportDialog: false,
                showsNewAPISiteDialog: true
            ),
            .newAPISite
        )
        XCTAssertNil(
            SettingsModalOverlayKind.resolve(
                showsResetDataDialog: false,
                showsCodexProfileEditorDialog: false,
                showsClaudeProfileEditorDialog: false,
                showsOAuthImportDialog: false,
                showsNewAPISiteDialog: false
            )
        )
    }
}
