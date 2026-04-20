import AppKit

struct StatusBarDisplayEntry {
    var icon: NSImage?
    var name: String
    var valueText: String
    var percent: Double?
}

enum StatusBarDisplayRenderer {
    private static let interGroupSpacing: CGFloat = 16

    private static let styleAIconSize = NSSize(width: 16, height: 16)
    private static let styleAEntryHeight: CGFloat = 16
    private static let styleAEntryYOffset: CGFloat = -6
    private static let styleATextBandYOffset: CGFloat = -1
    private static var styleATextFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }
    private static var styleATextColor: NSColor { .white }
    private static let styleAGroupSpacing: CGFloat = 4

    private static let styleBBarOuterSize = NSSize(width: 10, height: 20)
    private static let styleBEntryHeight: CGFloat = 20
    private static let styleBEntryYOffset: CGFloat = -5
    private static let styleBBarInnerWidth: CGFloat = 6
    private static let styleBBarInnerHeight: CGFloat = 16
    private static let styleBBarInnerOffsetX: CGFloat = 2
    private static let styleBBarInnerOffsetY: CGFloat = 2
    private static let styleBContentSpacing: CGFloat = 4
    private static let styleBBarOuterCornerRadius: CGFloat = 3
    private static let styleBBarInnerCornerRadius: CGFloat = 2
    private static var styleBBarOuterColor: NSColor { NSColor.white.withAlphaComponent(0.30) }
    private static var styleBBarInnerColor: NSColor { .white }
    private static var styleBNameFont: NSFont { NSFont.systemFont(ofSize: 10, weight: .regular) }
    private static var styleBNameColor: NSColor { NSColor.white.withAlphaComponent(0.80) }
    private static var styleBValueFont: NSFont { NSFont.systemFont(ofSize: 10, weight: .semibold) }
    private static var styleBValueColor: NSColor { .white }
    private static let styleBTextVerticalOffset: CGFloat = -1

    static func attributedString(entries: [StatusBarDisplayEntry], style: StatusBarDisplayStyle) -> NSAttributedString {
        guard !entries.isEmpty else { return NSAttributedString(string: "") }

        let result = NSMutableAttributedString()
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                result.append(interGroupSpacingAttachment(style: style))
            }
            appendEntry(entry, to: result, style: style)
        }
        return result
    }

    static func interGroupSpacingCount(for entryCount: Int) -> Int {
        max(0, entryCount - 1)
    }

    static func barFillHeight(percent: Double?) -> CGFloat {
        guard let percent else { return 0 }
        let normalized = min(max(percent, 0), 100)
        guard normalized > 0 else { return 0 }
        let availableHeight = styleBBarInnerHeight
        return max(1, round(availableHeight * normalized / 100))
    }

    private static func appendEntry(
        _ entry: StatusBarDisplayEntry,
        to result: NSMutableAttributedString,
        style: StatusBarDisplayStyle
    ) {
        switch style {
        case .iconPercent:
            result.append(styleAEntryAttachment(entry: entry, yOffset: styleAEntryYOffset))
        case .barNamePercent:
            result.append(styleBEntryAttachment(entry: entry, yOffset: styleBEntryYOffset))
        }
    }

    private static func interGroupSpacingAttachment(style: StatusBarDisplayStyle) -> NSAttributedString {
        let height: CGFloat
        let yOffset: CGFloat
        switch style {
        case .iconPercent:
            height = styleAEntryHeight
            yOffset = styleAEntryYOffset
        case .barNamePercent:
            height = styleBEntryHeight
            yOffset = styleBEntryYOffset
        }
        return spacerAttachment(width: interGroupSpacing, height: height, yOffset: yOffset, drawsImage: true)
    }

    private static func normalizedNameText(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "API" : trimmed
    }

    private static func normalizedValueText(_ valueText: String) -> String {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }

    private static func styleAEntryAttachment(entry: StatusBarDisplayEntry, yOffset: CGFloat) -> NSAttributedString {
        let valueText = normalizedValueText(entry.valueText)
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: styleATextFont,
            .foregroundColor: styleATextColor
        ]
        let valueSize = ceilTextSize((valueText as NSString).size(withAttributes: valueAttributes))
        let size = NSSize(
            width: styleAIconSize.width + styleAGroupSpacing + valueSize.width,
            height: styleAEntryHeight
        )

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let icon = entry.icon {
            drawIconOpticallyCentered(icon, in: NSRect(origin: .zero, size: styleAIconSize))
        }

        drawText(
            valueText,
            attributes: valueAttributes,
            in: NSRect(
                x: styleAIconSize.width + styleAGroupSpacing,
                y: styleATextBandYOffset,
                width: valueSize.width,
                height: styleAEntryHeight
            )
        )

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: yOffset, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func styleBEntryAttachment(entry: StatusBarDisplayEntry, yOffset: CGFloat) -> NSAttributedString {
        let nameText = normalizedNameText(entry.name)
        let valueText = normalizedValueText(entry.valueText)
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: styleBNameFont,
            .foregroundColor: styleBNameColor
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: styleBValueFont,
            .foregroundColor: styleBValueColor
        ]
        let nameSize = ceilTextSize((nameText as NSString).size(withAttributes: nameAttributes))
        let valueSize = ceilTextSize((valueText as NSString).size(withAttributes: valueAttributes))
        let textWidth = max(nameSize.width, valueSize.width)
        let size = NSSize(
            width: styleBBarOuterSize.width + styleBContentSpacing + textWidth,
            height: styleBBarOuterSize.height
        )

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let outerRect = NSRect(origin: .zero, size: styleBBarOuterSize)
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: styleBBarOuterCornerRadius, yRadius: styleBBarOuterCornerRadius)
        styleBBarOuterColor.setFill()
        outerPath.fill()

        let fillHeight = barFillHeight(percent: entry.percent)
        if fillHeight > 0 {
            let fillRect = NSRect(
                x: styleBBarInnerOffsetX,
                y: styleBBarInnerOffsetY,
                width: styleBBarInnerWidth,
                height: fillHeight
            )
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: styleBBarInnerCornerRadius, yRadius: styleBBarInnerCornerRadius)
            styleBBarInnerColor.setFill()
            fillPath.fill()
        }

        drawText(
            nameText,
            attributes: nameAttributes,
            in: NSRect(
                x: styleBBarOuterSize.width + styleBContentSpacing,
                y: 10 + styleBTextVerticalOffset,
                width: textWidth,
                height: 10
            ),
            lineHeight: 10
        )
        drawText(
            valueText,
            attributes: valueAttributes,
            in: NSRect(
                x: styleBBarOuterSize.width + styleBContentSpacing,
                y: styleBTextVerticalOffset,
                width: textWidth,
                height: 10
            ),
            lineHeight: 10
        )

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: yOffset, width: size.width, height: size.height)
        return NSAttributedString(attachment: attachment)
    }

    private static func spacerAttachment(
        width: CGFloat,
        height: CGFloat = 1,
        yOffset: CGFloat = 0,
        drawsImage: Bool = false
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()
        if drawsImage {
            let image = NSImage(size: NSSize(width: width, height: height))
            attachment.image = image
        }
        attachment.bounds = NSRect(x: 0, y: yOffset, width: width, height: height)
        return NSAttributedString(attachment: attachment)
    }

    private static func ceilTextSize(_ size: NSSize) -> NSSize {
        NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func drawIconOpticallyCentered(_ icon: NSImage, in targetRect: NSRect) {
        let metrics = iconOpticalMetrics(of: icon)
        let sourceRect = metrics?.bounds ?? NSRect(origin: .zero, size: icon.size)
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            icon.draw(in: targetRect)
            return
        }

        let scale = min(targetRect.width / sourceRect.width, targetRect.height / sourceRect.height)
        let drawSize = NSSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
        let targetCenter = NSPoint(x: targetRect.midX, y: targetRect.midY)
        let drawOrigin: NSPoint

        if let metrics {
            let mappedCentroid = NSPoint(
                x: (metrics.centroid.x - sourceRect.minX) * scale,
                y: (metrics.centroid.y - sourceRect.minY) * scale
            )
            drawOrigin = NSPoint(
                x: round(targetCenter.x - mappedCentroid.x),
                y: round(targetCenter.y - mappedCentroid.y)
            )
        } else {
            drawOrigin = NSPoint(
                x: targetRect.minX + floor((targetRect.width - drawSize.width) / 2),
                y: targetRect.minY + floor((targetRect.height - drawSize.height) / 2)
            )
        }

        let drawRect = NSRect(
            x: drawOrigin.x,
            y: drawOrigin.y,
            width: drawSize.width,
            height: drawSize.height
        )
        icon.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
    }

    private static func iconOpticalMetrics(of icon: NSImage) -> (bounds: NSRect, centroid: NSPoint)? {
        guard
            let tiff = icon.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.bitmapData
        else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let samplesPerPixel = bitmap.samplesPerPixel
        let bytesPerRow = bitmap.bytesPerRow
        let threshold = 16

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * samplesPerPixel
                let alpha: Int
                if bitmap.hasAlpha {
                    alpha = Int(data[offset + samplesPerPixel - 1])
                } else {
                    alpha = 255
                }
                if alpha > threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                    let weight = Double(alpha)
                    weightedX += Double(x) * weight
                    weightedY += Double(y) * weight
                    totalWeight += weight
                }
            }
        }

        guard maxX >= minX, maxY >= minY, totalWeight > 0 else {
            return nil
        }

        let pixelRect = NSRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard width > 0, height > 0 else {
            return (pixelRect, NSPoint(x: pixelRect.midX, y: pixelRect.midY))
        }

        // NSImage.draw(from:) expects source coordinates in image points, not raw bitmap pixels.
        let scaleX = icon.size.width / CGFloat(width)
        let scaleY = icon.size.height / CGFloat(height)
        let bounds = NSRect(
            x: pixelRect.origin.x * scaleX,
            y: pixelRect.origin.y * scaleY,
            width: pixelRect.size.width * scaleX,
            height: pixelRect.size.height * scaleY
        )
        let pixelCentroid = NSPoint(
            x: (weightedX / totalWeight) + 0.5,
            y: (weightedY / totalWeight) + 0.5
        )
        let centroid = NSPoint(
            x: pixelCentroid.x * scaleX,
            y: pixelCentroid.y * scaleY
        )
        return (bounds, centroid)
    }

    private static func drawText(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        in bandRect: NSRect,
        lineHeight: CGFloat? = nil
    ) {
        var drawAttributes = attributes
        if let lineHeight {
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.lineBreakMode = .byClipping
            drawAttributes[.paragraphStyle] = paragraph
        }
        let textSize = ceilTextSize((text as NSString).size(withAttributes: drawAttributes))
        let y = bandRect.origin.y + floor((bandRect.height - textSize.height) / 2)
        let drawRect = NSRect(
            x: bandRect.origin.x,
            y: y,
            width: max(bandRect.width, textSize.width),
            height: textSize.height
        )
        (text as NSString).draw(in: drawRect, withAttributes: drawAttributes)
    }
}
