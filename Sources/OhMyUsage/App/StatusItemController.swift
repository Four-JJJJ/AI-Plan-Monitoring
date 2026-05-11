import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    init(statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)) {
        self.statusItem = statusItem
    }

    var button: NSStatusBarButton? {
        statusItem.button
    }

    func configure(target: AnyObject, action: Selector) {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = false
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func render(
        entries: [StatusBarDisplayEntry],
        style: StatusBarDisplayStyle,
        foregroundStyle: StatusBarForegroundStyle,
        fallbackImage: NSImage?
    ) {
        guard let button = statusItem.button else { return }
        if entries.isEmpty {
            button.image = fallbackImage ?? Self.defaultFallbackImage()
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        button.image = nil
        button.title = ""
        button.imagePosition = .imageLeading
        button.attributedTitle = StatusBarDisplayRenderer.attributedString(
            entries: entries,
            style: style,
            foregroundStyle: foregroundStyle
        )
    }

    private static func defaultFallbackImage() -> NSImage? {
        AppIconImageProvider.image(size: 16)
    }
}
