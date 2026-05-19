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

        let didRender = controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        )

        XCTAssertTrue(didRender)
        XCTAssertEqual(statusItem.button?.image, fallbackImage)
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "")
    }

    func testRenderEntriesUsesAttributedTitleAndClearsButtonImage() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)

        let didRender = controller.render(
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

        XCTAssertTrue(didRender)
        XCTAssertEqual(statusItem.button?.image, nil)
        XCTAssertFalse(statusItem.button?.attributedTitle.string.isEmpty ?? true)
    }

    func testRenderEntriesWithSameSignatureKeepsExistingAttributedTitle() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)
        let entries = [
            StatusBarDisplayEntry(
                icon: NSImage(size: NSSize(width: 16, height: 16)),
                name: "Codex",
                valueText: "72%",
                percent: 72
            )
        ]

        let firstRenderDidRender = controller.render(
            entries: entries,
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )
        let firstTitle = statusItem.button?.attributedTitle

        let secondRenderDidRender = controller.render(
            entries: entries,
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )
        let secondTitle = statusItem.button?.attributedTitle

        XCTAssertTrue(firstRenderDidRender)
        XCTAssertFalse(secondRenderDidRender)
        XCTAssertTrue(firstTitle === secondTitle)
    }

    func testRenderEntriesWithChangedSignatureReplacesAttributedTitle() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)

        let firstRenderDidRender = controller.render(
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
        let firstTitle = statusItem.button?.attributedTitle

        let secondRenderDidRender = controller.render(
            entries: [
                StatusBarDisplayEntry(
                    icon: nil,
                    name: "Codex",
                    valueText: "73%",
                    percent: 73
                )
            ],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )
        let secondTitle = statusItem.button?.attributedTitle

        XCTAssertTrue(firstRenderDidRender)
        XCTAssertTrue(secondRenderDidRender)
        XCTAssertFalse(firstTitle === secondTitle)
        XCTAssertFalse(statusItem.button?.attributedTitle.string.isEmpty ?? true)
    }

    func testRenderEntriesWithChangedIconReplacesAttributedTitle() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)

        let firstRenderDidRender = controller.render(
            entries: [
                StatusBarDisplayEntry(
                    icon: NSImage(size: NSSize(width: 16, height: 16)),
                    name: "Codex",
                    valueText: "72%",
                    percent: 72
                )
            ],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )
        let firstTitle = statusItem.button?.attributedTitle

        let secondRenderDidRender = controller.render(
            entries: [
                StatusBarDisplayEntry(
                    icon: NSImage(size: NSSize(width: 16, height: 16)),
                    name: "Codex",
                    valueText: "72%",
                    percent: 72
                )
            ],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: nil
        )
        let secondTitle = statusItem.button?.attributedTitle

        XCTAssertTrue(firstRenderDidRender)
        XCTAssertTrue(secondRenderDidRender)
        XCTAssertFalse(firstTitle === secondTitle)
    }

    func testRenderEmptyEntriesWithSameFallbackImageKeepsExistingAttributedTitle() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)
        let fallbackImage = NSImage(size: NSSize(width: 16, height: 16))

        let firstRenderDidRender = controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        )
        let firstTitle = statusItem.button?.attributedTitle

        let secondRenderDidRender = controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        )
        let secondTitle = statusItem.button?.attributedTitle

        XCTAssertTrue(firstRenderDidRender)
        XCTAssertFalse(secondRenderDidRender)
        XCTAssertTrue(firstTitle === secondTitle)
        XCTAssertEqual(statusItem.button?.image, fallbackImage)
    }

    func testRenderEmptyEntriesWithChangedFallbackImageUpdatesImage() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)
        let firstImage = NSImage(size: NSSize(width: 16, height: 16))
        let secondImage = NSImage(size: NSSize(width: 18, height: 18))

        let firstRenderDidRender = controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: firstImage
        )
        let secondRenderDidRender = controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: secondImage
        )

        XCTAssertTrue(firstRenderDidRender)
        XCTAssertTrue(secondRenderDidRender)
        XCTAssertEqual(statusItem.button?.image, secondImage)
        XCTAssertEqual(statusItem.button?.attributedTitle.string, "")
    }

    func testConfigureClearsRenderCache() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let controller = StatusItemController(statusItem: statusItem)
        let fallbackImage = NSImage(size: NSSize(width: 16, height: 16))

        XCTAssertTrue(controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        ))
        XCTAssertFalse(controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        ))

        controller.configure(target: self, action: #selector(noopAction))

        XCTAssertTrue(controller.render(
            entries: [],
            style: .iconPercent,
            foregroundStyle: .light,
            fallbackImage: fallbackImage
        ))
    }

    @objc
    private func noopAction() {
    }
}
