import AppKit
import XCTest
@testable import AIPlanMonitor

final class StatusBarDisplayRendererTests: XCTestCase {
    func testIconPercentStyleUsesFixedInterGroupSpacingWithoutSeparator() {
        let entries = [
            StatusBarDisplayEntry(icon: testIcon(), name: "Codex", valueText: "78%", percent: 78),
            StatusBarDisplayEntry(icon: testIcon(), name: "Claude", valueText: "53%", percent: 53)
        ]

        let attributed = StatusBarDisplayRenderer.attributedString(entries: entries, style: .iconPercent)
        let attachments = collectAttachments(from: attributed)
        let entryCount = attachments.filter { $0.bounds.height == 16 && $0.bounds.width > 16 }.count
        let spacingCount = attachments.filter { $0.bounds.width == 16 && $0.bounds.height == 16 }.count
        let separatorCount = attachments.filter { $0.bounds.width == 1 }.count

        XCTAssertEqual(entryCount, 2)
        XCTAssertEqual(spacingCount, 1)
        XCTAssertEqual(separatorCount, 0)
    }

    func testBarFillHeightMappingHandlesZeroMidAndFull() {
        XCTAssertEqual(StatusBarDisplayRenderer.barFillHeight(percent: nil), 0)
        XCTAssertEqual(StatusBarDisplayRenderer.barFillHeight(percent: 0), 0)
        XCTAssertEqual(StatusBarDisplayRenderer.barFillHeight(percent: 10), 2)
        XCTAssertEqual(StatusBarDisplayRenderer.barFillHeight(percent: 50), 8)
        XCTAssertEqual(StatusBarDisplayRenderer.barFillHeight(percent: 100), 16)
    }

    func testBarNamePercentStyleUsesFixedInterGroupSpacingWithoutSeparator() {
        let entries = [
            StatusBarDisplayEntry(icon: nil, name: "Codex", valueText: "78%", percent: 78),
            StatusBarDisplayEntry(icon: nil, name: "Claude", valueText: "100%", percent: 100),
            StatusBarDisplayEntry(icon: nil, name: "Kimi", valueText: "10%", percent: 10)
        ]

        let attributed = StatusBarDisplayRenderer.attributedString(entries: entries, style: .barNamePercent)
        let attachments = collectAttachments(from: attributed)
        let barCount = attachments.filter { $0.bounds.height == 20 && $0.bounds.width > 16 }.count
        let spacingCount = attachments.filter { $0.bounds.width == 16 && $0.bounds.height == 20 }.count
        let separatorCount = attachments.filter { $0.bounds.width == 1 }.count

        XCTAssertEqual(barCount, entries.count)
        XCTAssertEqual(spacingCount, StatusBarDisplayRenderer.interGroupSpacingCount(for: entries.count))
        XCTAssertEqual(spacingCount, 2)
        XCTAssertEqual(separatorCount, 0)
    }

    func testSingleEntryHasNoInterGroupSpacing() {
        let entries = [
            StatusBarDisplayEntry(icon: testIcon(), name: "Codex", valueText: "78%", percent: 78)
        ]

        let attributed = StatusBarDisplayRenderer.attributedString(entries: entries, style: .iconPercent)
        let attachments = collectAttachments(from: attributed)
        let spacingCount = attachments.filter { $0.bounds.width == 16 }.count

        XCTAssertEqual(spacingCount, 0)
    }

    private func collectAttachments(from attributed: NSAttributedString) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            result.append(attachment)
        }
        return result
    }

    private func testIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        return image
    }
}
