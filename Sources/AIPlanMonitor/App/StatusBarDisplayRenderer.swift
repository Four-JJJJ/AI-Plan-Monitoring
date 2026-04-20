import AppKit

struct StatusBarDisplayEntry {
    var icon: NSImage?
    var name: String
    var valueText: String
    var percent: Double?
}

enum StatusBarDisplayRenderer {
    static func attributedString(entries: [StatusBarDisplayEntry], style: StatusBarDisplayStyle) -> NSAttributedString {
        switch style {
        case .iconPercent:
            return IconPercentRenderer.attributedString(entries: entries)
        case .barNamePercent:
            return BarNamePercentRenderer.attributedString(entries: entries)
        }
    }

    static func interGroupSpacingCount(for entryCount: Int) -> Int {
        max(0, entryCount - 1)
    }

    static func barFillHeight(percent: Double?) -> CGFloat {
        BarNamePercentRenderer.barFillHeight(percent: percent)
    }

    private enum IconPercentRenderer {
        private static let interGroupSpacing: CGFloat = 16
        private static let iconSize = NSSize(width: 16, height: 16)
        private static let entryHeight: CGFloat = 16
        private static let entryYOffset: CGFloat = -4
        private static let textBandYOffset: CGFloat = 0
        private static var textFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .semibold) }
        private static var textColor: NSColor { .white }
        private static let groupSpacing: CGFloat = 4

        static func attributedString(entries: [StatusBarDisplayEntry]) -> NSAttributedString {
            guard !entries.isEmpty else { return NSAttributedString(string: "") }

            let result = NSMutableAttributedString()
            for (index, entry) in entries.enumerated() {
                if index > 0 {
                    result.append(interGroupSpacingAttachment())
                }
                result.append(entryAttachment(entry))
            }
            return result
        }

        private static func interGroupSpacingAttachment() -> NSAttributedString {
            StatusBarDisplayRenderer.spacerAttachment(
                width: interGroupSpacing,
                height: entryHeight,
                yOffset: entryYOffset,
                drawsImage: true
            )
        }

        private static func entryAttachment(_ entry: StatusBarDisplayEntry) -> NSAttributedString {
            let valueText = StatusBarDisplayRenderer.normalizedValueText(entry.valueText)
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor
            ]
            let valueSize = StatusBarDisplayRenderer.ceilTextSize((valueText as NSString).size(withAttributes: valueAttributes))
            let size = NSSize(
                width: iconSize.width + groupSpacing + valueSize.width,
                height: entryHeight
            )

            let image = NSImage(size: size)
            image.lockFocus()
            defer { image.unlockFocus() }

            if let icon = entry.icon {
                StatusBarDisplayRenderer.drawIconBoundsCentered(icon, in: NSRect(origin: .zero, size: iconSize))
            }

            StatusBarDisplayRenderer.drawText(
                valueText,
                attributes: valueAttributes,
                in: NSRect(
                    x: iconSize.width + groupSpacing,
                    y: textBandYOffset,
                    width: valueSize.width,
                    height: entryHeight
                )
            )

            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: entryYOffset, width: size.width, height: size.height)
            return NSAttributedString(attachment: attachment)
        }
    }

    private enum BarNamePercentRenderer {
        private static let interGroupSpacing: CGFloat = 16
        private static let barOuterSize = NSSize(width: 10, height: 20)
        private static let entryHeight: CGFloat = 20
        private static let entryYOffset: CGFloat = -6
        private static let barInnerWidth: CGFloat = 6
        private static let barInnerHeight: CGFloat = 16
        private static let barInnerOffsetX: CGFloat = 2
        private static let barInnerOffsetY: CGFloat = 2
        private static let contentSpacing: CGFloat = 4
        private static let barOuterCornerRadius: CGFloat = 3
        private static let barInnerCornerRadius: CGFloat = 2
        private static var barOuterColor: NSColor { NSColor.white.withAlphaComponent(0.30) }
        private static var barInnerColor: NSColor { .white }
        private static var nameFont: NSFont { NSFont.systemFont(ofSize: 10, weight: .regular) }
        private static var nameColor: NSColor { NSColor.white.withAlphaComponent(0.80) }
        private static var valueFont: NSFont { NSFont.systemFont(ofSize: 10, weight: .semibold) }
        private static var valueColor: NSColor { .white }
        private static let textVerticalOffset: CGFloat = -2

        static func attributedString(entries: [StatusBarDisplayEntry]) -> NSAttributedString {
            guard !entries.isEmpty else { return NSAttributedString(string: "") }

            let result = NSMutableAttributedString()
            for (index, entry) in entries.enumerated() {
                if index > 0 {
                    result.append(interGroupSpacingAttachment())
                }
                result.append(entryAttachment(entry))
            }
            return result
        }

        static func barFillHeight(percent: Double?) -> CGFloat {
            guard let percent else { return 0 }
            let normalized = min(max(percent, 0), 100)
            guard normalized > 0 else { return 0 }
            return max(1, round(barInnerHeight * normalized / 100))
        }

        private static func interGroupSpacingAttachment() -> NSAttributedString {
            StatusBarDisplayRenderer.spacerAttachment(
                width: interGroupSpacing,
                height: entryHeight,
                yOffset: entryYOffset,
                drawsImage: true
            )
        }

        private static func entryAttachment(_ entry: StatusBarDisplayEntry) -> NSAttributedString {
            let nameText = StatusBarDisplayRenderer.normalizedNameText(entry.name)
            let valueText = StatusBarDisplayRenderer.normalizedValueText(entry.valueText)
            let nameAttributes: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: nameColor
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: valueColor
            ]
            let nameSize = StatusBarDisplayRenderer.ceilTextSize((nameText as NSString).size(withAttributes: nameAttributes))
            let valueSize = StatusBarDisplayRenderer.ceilTextSize((valueText as NSString).size(withAttributes: valueAttributes))
            let textWidth = max(nameSize.width, valueSize.width)
            let size = NSSize(
                width: barOuterSize.width + contentSpacing + textWidth,
                height: barOuterSize.height
            )

            let image = NSImage(size: size)
            image.lockFocus()
            defer { image.unlockFocus() }

            let outerRect = NSRect(origin: .zero, size: barOuterSize)
            let outerPath = NSBezierPath(
                roundedRect: outerRect,
                xRadius: barOuterCornerRadius,
                yRadius: barOuterCornerRadius
            )
            barOuterColor.setFill()
            outerPath.fill()

            let fillHeight = barFillHeight(percent: entry.percent)
            if fillHeight > 0 {
                let fillRect = NSRect(
                    x: barInnerOffsetX,
                    y: barInnerOffsetY,
                    width: barInnerWidth,
                    height: fillHeight
                )
                let fillPath = NSBezierPath(
                    roundedRect: fillRect,
                    xRadius: barInnerCornerRadius,
                    yRadius: barInnerCornerRadius
                )
                barInnerColor.setFill()
                fillPath.fill()
            }

            StatusBarDisplayRenderer.drawText(
                nameText,
                attributes: nameAttributes,
                in: NSRect(
                    x: barOuterSize.width + contentSpacing,
                    y: 10 + textVerticalOffset,
                    width: textWidth,
                    height: 10
                ),
                lineHeight: 10
            )
            StatusBarDisplayRenderer.drawText(
                valueText,
                attributes: valueAttributes,
                in: NSRect(
                    x: barOuterSize.width + contentSpacing,
                    y: textVerticalOffset,
                    width: textWidth,
                    height: 10
                ),
                lineHeight: 10
            )

            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: entryYOffset, width: size.width, height: size.height)
            return NSAttributedString(attachment: attachment)
        }
    }

    private static func normalizedNameText(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "API" : trimmed
    }

    private static func normalizedValueText(_ valueText: String) -> String {
        let trimmed = valueText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
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

    private static func drawIconBoundsCentered(_ icon: NSImage, in targetRect: NSRect) {
        let sourceRect = NSRect(origin: .zero, size: icon.size)
        guard sourceRect.width > 0, sourceRect.height > 0 else {
            icon.draw(in: targetRect)
            return
        }

        let scale = min(targetRect.width / sourceRect.width, targetRect.height / sourceRect.height)
        let drawSize = NSSize(width: sourceRect.width * scale, height: sourceRect.height * scale)
        let drawOrigin = NSPoint(
            x: targetRect.minX + floor((targetRect.width - drawSize.width) / 2),
            y: targetRect.minY + floor((targetRect.height - drawSize.height) / 2)
        )

        let drawRect = NSRect(
            x: drawOrigin.x,
            y: drawOrigin.y,
            width: drawSize.width,
            height: drawSize.height
        )
        icon.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1.0)
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
