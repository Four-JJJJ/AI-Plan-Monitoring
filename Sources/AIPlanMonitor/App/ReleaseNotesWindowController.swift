import AppKit

@MainActor
final class ReleaseNotesWindowController: NSObject, NSWindowDelegate {
    static let shared = ReleaseNotesWindowController()

    private let releaseNotesService = AppUpdateService()
    private let bodyFont = NSFont.systemFont(ofSize: 14)
    private let minContentSize = NSSize(width: 520, height: 220)
    private let maxContentSize = NSSize(width: 920, height: 720)
    private let bodyHorizontalInset: CGFloat = 28
    private let bodyVerticalInset: CGFloat = 28
    private let extraScrollChromeWidth: CGFloat = 22
    private let buttonRowHeight: CGFloat = 52
    private var window: NSWindow?
    private var textView: NSTextView?
    private var openButton: NSButton?
    private var currentReleaseURL: URL?
    private var loadRequestID = UUID()

    private override init() {
        super.init()
    }

    func show(releaseNotes: PendingPostUpdateReleaseNotes) {
        let window = ensureWindow()
        window.title = title(for: releaseNotes.version)
        currentReleaseURL = releaseNotes.releaseURL
        loadRequestID = UUID()
        setBodyText(loadingText())
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)

        let requestID = loadRequestID
        Task { [weak self] in
            guard let self else { return }

            let bodyText: String
            do {
                let fetched = try await self.releaseNotesService.fetchReleaseNotesBody(
                    forVersion: releaseNotes.version
                )
                bodyText = fetched.isEmpty ? self.emptyText() : fetched
            } catch {
                bodyText = self.failedText()
            }

            guard self.loadRequestID == requestID else { return }
            self.setBodyText(bodyText)
        }
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = bodyFont
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        self.textView = textView

        let scrollView = NSScrollView(frame: .zero)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        let openButton = NSButton(
            title: buttonTitle(),
            target: self,
            action: #selector(openReleasePage)
        )
        openButton.bezelStyle = .rounded
        self.openButton = openButton

        let buttonRow = NSStackView(views: [openButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas
        buttonRow.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let contentStack = NSStackView(views: [scrollView, buttonRow])
        contentStack.orientation = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .visible
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = frameSize(forContentSize: minContentSize)
        panel.contentView = container
        self.window = panel
        return panel
    }

    private func setBodyText(_ text: String) {
        textView?.string = text
        updateWindowSize(for: text)
        textView?.scrollToBeginningOfDocument(nil)
    }

    private func updateWindowSize(for text: String) {
        guard let window else { return }

        let contentSize = preferredContentSize(for: text)
        let targetFrameSize = frameSize(forContentSize: contentSize)
        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - targetFrameSize.width / 2,
            y: currentFrame.midY - targetFrameSize.height / 2
        )

        window.setFrame(
            NSRect(origin: newOrigin, size: targetFrameSize),
            display: true,
            animate: true
        )
    }

    private func preferredContentSize(for text: String) -> NSSize {
        let maxAvailableSize = maximumAvailableContentSize()
        let clampedMaxWidth = min(maxAvailableSize.width, maxContentSize.width)
        let clampedMaxHeight = min(maxAvailableSize.height, maxContentSize.height)
        let width = preferredBodyWidth(for: text, maximumContentWidth: clampedMaxWidth)
        let bodyHeight = preferredBodyHeight(
            for: text,
            bodyWidth: width - bodyHorizontalInset - extraScrollChromeWidth
        )

        return NSSize(
            width: min(max(minContentSize.width, width), clampedMaxWidth),
            height: min(
                max(minContentSize.height, bodyHeight + bodyVerticalInset + buttonRowHeight),
                clampedMaxHeight
            )
        )
    }

    private func preferredBodyWidth(for text: String, maximumContentWidth: CGFloat) -> CGFloat {
        let maxBodyWidth = maximumContentWidth - bodyHorizontalInset - extraScrollChromeWidth
        let minBodyWidth = minContentSize.width - bodyHorizontalInset - extraScrollChromeWidth
        let widestLine = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .reduce(CGFloat.zero) { partialResult, line in
                max(partialResult, measuredSingleLineWidth(for: line))
            }

        let targetBodyWidth = min(max(minBodyWidth, widestLine), maxBodyWidth)
        return targetBodyWidth + bodyHorizontalInset + extraScrollChromeWidth
    }

    private func preferredBodyHeight(for text: String, bodyWidth: CGFloat) -> CGFloat {
        let constrainedWidth = max(200, bodyWidth)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: constrainedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont],
            context: nil
        )
        return ceil(measured.height)
    }

    private func measuredSingleLineWidth(for line: String) -> CGFloat {
        let candidate = line.isEmpty ? " " : line
        let measured = (candidate as NSString).size(withAttributes: [.font: bodyFont])
        return ceil(measured.width)
    }

    private func maximumAvailableContentSize() -> NSSize {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return maxContentSize
        }
        return NSSize(
            width: max(minContentSize.width, visibleFrame.width - 120),
            height: max(minContentSize.height, visibleFrame.height - 120)
        )
    }

    private func frameSize(forContentSize contentSize: NSSize) -> NSSize {
        guard let window else {
            return contentSize
        }
        return window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    private func title(for version: String) -> String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return "AI Plan Monitor \(version) 更新说明"
        }
        return "AI Plan Monitor \(version) Release Notes"
    }

    private func buttonTitle() -> String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return "打开 Release 页面"
        }
        return "Open Release Page"
    }

    private func loadingText() -> String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return "正在加载当前版本的更新说明…"
        }
        return "Loading release notes for this version..."
    }

    private func emptyText() -> String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return "当前版本没有填写更新说明。"
        }
        return "No release notes were provided for this version."
    }

    private func failedText() -> String {
        if Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true {
            return "加载更新说明失败。你仍然可以点击下方按钮打开 Release 页面查看。"
        }
        return "Failed to load the release notes. You can still open the release page below."
    }

    @objc
    private func openReleasePage() {
        guard let currentReleaseURL else { return }
        NSWorkspace.shared.open(currentReleaseURL)
    }
}
