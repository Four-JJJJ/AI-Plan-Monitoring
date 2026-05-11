import AppKit
import XCTest
@testable import OhMyUsage

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testRenderEmptyEntriesUsesFallbackImageOnlyMode() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)
        let fallbackImage = NSImage(size: NSSize(width: 16, height: 16))

        controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        )

        XCTAssertEqual(statusItem.button?.image, fallbackImage)
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "")
    }

    func testRenderEntriesUsesAttributedTitleAndClearsButtonImage() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)

        controller.render(
            entries: [
                StatusBarDisplayEntry(
                    icon: nil,
                    name: "Codex",
                    valueText: "72%",
                    percent: 72
                )
            ],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )

        XCTAssertEqual(statusItem.button?.image, nil)
        XCTAssertFalse(statusItem.button?.attributedTitle.string.isEmpty ?? true)
    }
}
