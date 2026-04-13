#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: generate_dmg_install_card.swift <output-path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let canvasSize = NSSize(width: 900, height: 900)
let image = NSImage(size: canvasSize)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fputs("failed to create graphics context\n", stderr)
    exit(1)
}

let background = NSColor(calibratedWhite: 0.98, alpha: 1)
let cardFill = NSColor.white
let cardStroke = NSColor(calibratedWhite: 0.88, alpha: 1)
let titleColor = NSColor.black
let subtitleColor = NSColor(calibratedWhite: 0.33, alpha: 1)
let noteColor = NSColor(calibratedWhite: 0.45, alpha: 1)
let accent = NSColor(calibratedRed: 0.11, green: 0.45, blue: 0.95, alpha: 1)

context.setFillColor(background.cgColor)
context.fill(CGRect(origin: .zero, size: canvasSize))

let cardRect = NSRect(x: 40, y: 40, width: 820, height: 820)
let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 42, yRadius: 42)
cardFill.setFill()
cardPath.fill()
cardStroke.setStroke()
cardPath.lineWidth = 2
cardPath.stroke()

func paragraphStyle(alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 4) -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.lineSpacing = lineSpacing
    return style
}

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 54, weight: .bold),
    .foregroundColor: titleColor,
    .paragraphStyle: paragraphStyle(alignment: .center, lineSpacing: 6)
]
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .medium),
    .foregroundColor: subtitleColor,
    .paragraphStyle: paragraphStyle(alignment: .center, lineSpacing: 6)
]
let stepBadgeAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraphStyle(alignment: .center, lineSpacing: 0)
]
let stepTitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
    .foregroundColor: titleColor,
    .paragraphStyle: paragraphStyle(alignment: .left, lineSpacing: 6)
]
let stepBodyAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 26, weight: .regular),
    .foregroundColor: subtitleColor,
    .paragraphStyle: paragraphStyle(alignment: .left, lineSpacing: 8)
]
let noteAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 24, weight: .regular),
    .foregroundColor: noteColor,
    .paragraphStyle: paragraphStyle(alignment: .center, lineSpacing: 8)
]

("安装 AI Plan Monitor" as NSString)
    .draw(in: NSRect(x: 90, y: 700, width: 720, height: 70), withAttributes: titleAttrs)

("1. 拖动左侧 app 到右侧 Applications\n2. 首次打开请右键“打开”\n3. 若被拦截：系统设置 -> 隐私与安全性 -> 仍要打开" as NSString)
    .draw(in: NSRect(x: 95, y: 555, width: 710, height: 120), withAttributes: subtitleAttrs)

func drawStep(number: String, title: String, body: String, y: CGFloat) {
    let badgeRect = NSRect(x: 105, y: y + 45, width: 54, height: 54)
    let badgePath = NSBezierPath(ovalIn: badgeRect)
    accent.setFill()
    badgePath.fill()

    let badgeTextRect = badgeRect.offsetBy(dx: 0, dy: 6)
    (number as NSString).draw(in: badgeTextRect, withAttributes: stepBadgeAttrs)

    (title as NSString).draw(in: NSRect(x: 180, y: y + 58, width: 560, height: 40), withAttributes: stepTitleAttrs)
    (body as NSString).draw(in: NSRect(x: 180, y: y, width: 560, height: 52), withAttributes: stepBodyAttrs)
}

drawStep(
    number: "1",
    title: "拖动安装",
    body: "把左侧 AI Plan Monitor.app\n拖到右侧 Applications 文件夹。",
    y: 380
)

drawStep(
    number: "2",
    title: "右键打开",
    body: "如果系统拦截，请去“应用程序”里\n右键 AI Plan Monitor，选择“打开”。",
    y: 250
)

drawStep(
    number: "3",
    title: "仍被拦截时",
    body: "打开“系统设置” -> “隐私与安全性”\n找到 AI Plan Monitor，点击“仍要打开”。",
    y: 120
)

("提示：把这个窗口里的说明图保留着即可，不需要再额外打开文本说明。" as NSString)
    .draw(in: NSRect(x: 90, y: 62, width: 720, height: 34), withAttributes: noteAttrs)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("failed to write png: \(error)\n", stderr)
    exit(1)
}
