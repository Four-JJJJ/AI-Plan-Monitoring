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

    func testIconPercentStyleDoesNotClipTopRightIconDetail() {
        let entries = [
            StatusBarDisplayEntry(icon: asymmetricIconWithTopRightDot(), name: "Kimi", valueText: "100%", percent: 100)
        ]

        let attributed = StatusBarDisplayRenderer.attributedString(entries: entries, style: .iconPercent)
        let attachments = collectAttachments(from: attributed)
        guard let image = attachments.first?.image else {
            XCTFail("Expected icon attachment image")
            return
        }

        XCTAssertTrue(
            hasOpaquePixel(in: image, region: NSRect(x: 12, y: 12, width: 4, height: 4)),
            "Icon top-right detail should remain visible and not be clipped."
        )
    }

    func testDarkForegroundStyleColorMapping() {
        let full = rgba(from: StatusBarForegroundStyle.dark.color())
        XCTAssertLessThan(full.red, 0.01)
        XCTAssertLessThan(full.green, 0.01)
        XCTAssertLessThan(full.blue, 0.01)
        XCTAssertEqual(full.alpha, 1.0, accuracy: 0.001)

        let alpha = rgba(from: StatusBarForegroundStyle.dark.color(opacity: 0.30))
        XCTAssertLessThan(alpha.red, 0.01)
        XCTAssertLessThan(alpha.green, 0.01)
        XCTAssertLessThan(alpha.blue, 0.01)
        XCTAssertEqual(alpha.alpha, 0.30, accuracy: 0.01)
    }

    func testLightForegroundStyleColorMapping() {
        let full = rgba(from: StatusBarForegroundStyle.light.color())
        XCTAssertGreaterThan(full.red, 0.99)
        XCTAssertGreaterThan(full.green, 0.99)
        XCTAssertGreaterThan(full.blue, 0.99)
        XCTAssertEqual(full.alpha, 1.0, accuracy: 0.001)

        let alpha = rgba(from: StatusBarForegroundStyle.light.color(opacity: 0.80))
        XCTAssertGreaterThan(alpha.red, 0.99)
        XCTAssertGreaterThan(alpha.green, 0.99)
        XCTAssertGreaterThan(alpha.blue, 0.99)
        XCTAssertEqual(alpha.alpha, 0.80, accuracy: 0.01)
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

    private func asymmetricIconWithTopRightDot() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 1, width: 7, height: 14)).fill()
        NSBezierPath(rect: NSRect(x: 13, y: 13, width: 2, height: 2)).fill()
        return image
    }

    private func hasOpaquePixel(in image: NSImage, region: NSRect) -> Bool {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.bitmapData
        else {
            return false
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let samplesPerPixel = bitmap.samplesPerPixel
        let bytesPerRow = bitmap.bytesPerRow
        let minX = max(0, Int(floor(region.minX)))
        let maxX = min(width - 1, Int(ceil(region.maxX)) - 1)
        let minY = max(0, Int(floor(region.minY)))
        let maxY = min(height - 1, Int(ceil(region.maxY)) - 1)
        guard minX <= maxX, minY <= maxY else { return false }

        for y in minY...maxY {
            for x in minX...maxX {
                let offset = y * bytesPerRow + x * samplesPerPixel
                let alpha = bitmap.hasAlpha ? Int(data[offset + samplesPerPixel - 1]) : 255
                if alpha > 16 {
                    return true
                }
            }
        }
        return false
    }

    private func rgba(from color: NSColor) -> (red: Double, green: Double, blue: Double, alpha: Double) {
        let resolved = color.usingColorSpace(.deviceRGB) ?? color
        return (
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            alpha: Double(resolved.alphaComponent)
        )
    }
}
