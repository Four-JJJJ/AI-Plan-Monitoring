import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private var lastRenderSignature: RenderSignature?

    init(statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)) {
        self.statusItem = statusItem
    }

    var button: NSStatusBarButton? {
        statusItem.button
    }

    func configure(target: AnyObject, action: Selector) {
        guard let button = statusItem.button else { return }
        lastRenderSignature = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = false
        button.target = target
        button.action = action
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @discardableResult
    func render(
        entries: [StatusBarDisplayEntry],
        style: StatusBarDisplayStyle,
        foregroundStyle: StatusBarForegroundStyle,
        fallbackImage: NSImage?
    ) -> Bool {
        guard let button = statusItem.button else { return false }
        let signature = Self.renderSignature(
            entries: entries,
            style: style,
            foregroundStyle: foregroundStyle,
            fallbackImage: fallbackImage
        )
        guard signature != lastRenderSignature else { return false }

        if entries.isEmpty {
            button.image = fallbackImage ?? Self.defaultFallbackImage()
            button.imagePosition = .imageOnly
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            lastRenderSignature = signature
            return true
        }

        button.image = nil
        button.title = ""
        button.imagePosition = .imageLeading
        button.attributedTitle = StatusBarDisplayRenderer.attributedString(
            entries: entries,
            style: style,
            foregroundStyle: foregroundStyle
        )
        lastRenderSignature = signature
        return true
    }

    private static func defaultFallbackImage() -> NSImage? {
        AppIconImageProvider.image(size: 16)
    }

    private static func renderSignature(
        entries: [StatusBarDisplayEntry],
        style: StatusBarDisplayStyle,
        foregroundStyle: StatusBarForegroundStyle,
        fallbackImage: NSImage?
    ) -> RenderSignature {
        guard !entries.isEmpty else {
            if let fallbackImage {
                return .fallback(.provided(fallbackImage))
            }
            return .fallback(.defaultImage)
        }

        return .entries(
            style: style,
            foregroundStyle: foregroundStyle,
            entries: entries.map {
                EntrySignature(
                    name: $0.name,
                    valueText: $0.valueText,
                    percent: $0.percent,
                    icon: iconSignature($0.icon)
                )
            }
        )
    }

    private static func iconSignature(_ icon: NSImage?) -> IconSignature {
        guard let icon else { return .none }
        return .provided(icon)
    }

    private enum RenderSignature: Equatable {
        case fallback(FallbackImageSignature)
        case entries(
            style: StatusBarDisplayStyle,
            foregroundStyle: StatusBarForegroundStyle,
            entries: [EntrySignature]
        )
    }

    private enum FallbackImageSignature: Equatable {
        case provided(NSImage)
        case defaultImage

        static func == (lhs: FallbackImageSignature, rhs: FallbackImageSignature) -> Bool {
            switch (lhs, rhs) {
            case (.defaultImage, .defaultImage):
                return true
            case let (.provided(lhsImage), .provided(rhsImage)):
                return lhsImage === rhsImage
            default:
                return false
            }
        }
    }

    private struct EntrySignature: Equatable {
        var name: String
        var valueText: String
        var percent: Double?
        var icon: IconSignature
    }

    private enum IconSignature: Equatable {
        case none
        case provided(NSImage)

        static func == (lhs: IconSignature, rhs: IconSignature) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case let (.provided(lhsImage), .provided(rhsImage)):
                return lhsImage === rhsImage
            default:
                return false
            }
        }
    }
}
