import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let viewModel: AppViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var refreshTimer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let statusIconSize: CGFloat = 18
    private let statusSpacing: CGFloat = 4
    private let protectedOutsideClickBundleIDs: Set<String> = [
        "com.apple.securityagent",
        "com.apple.systemsettings",
        "com.apple.systempreferences",
        "com.apple.preference.security.remoteservice"
    ]
    private lazy var statusFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private lazy var codexStatusImage: NSImage? = {
        if let image = bundledImage(named: "codex_icon", ext: "png") ?? bundledImage(named: "codex_icon", ext: "svg") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        return nil
    }()
    private lazy var kimiStatusImage: NSImage? = {
        if let image = bundledImage(named: "kimi_icon", ext: "png") ?? bundledImage(named: "kimi_icon", ext: "svg") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        return nil
    }()
    private lazy var relayStatusImage: NSImage? = {
        if let image = bundledImage(named: "relay_icon", ext: "png") ?? bundledImage(named: "relay_icon", ext: "svg") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        return nil
    }()
    private lazy var appStatusImage: NSImage? = {
        if let image = NSApp.applicationIconImage?.copy() as? NSImage, image.isValid {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        let workspaceIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
        if workspaceIcon.isValid {
            workspaceIcon.size = NSSize(width: statusIconSize, height: statusIconSize)
            workspaceIcon.isTemplate = false
            return workspaceIcon
        }
        if let image = bundledMainImage(named: "AppIcon", ext: "icns") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        if let image = bundledImage(named: "AppIcon", ext: "icns") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        if let image = NSApp.applicationIconImage?.copy() as? NSImage {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        if let image = bundledImage(named: "app_icon_source", ext: "png") {
            image.size = NSSize(width: statusIconSize, height: statusIconSize)
            image.isTemplate = false
            return image
        }
        return nil
    }()

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
        viewModel.start()
        refreshStatusDisplay()
        startRefreshTimer()
        showInitialPopoverIfNeeded()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.font = statusFont
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = false
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        let rootView = MenuContentView(viewModel: viewModel)
        let controller = NSHostingController(rootView: rootView)
        controller.view.frame = NSRect(x: 0, y: 0, width: 384, height: 640)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 384, height: 640)
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    private func refreshStatusDisplay() {
        guard let button = statusItem.button else { return }
        let statusProvider = viewModel.statusBarProvider()
        let text = statusText(for: statusProvider)
        button.image = image(for: statusProvider)
        button.image?.size = NSSize(width: statusIconSize, height: statusIconSize)
        button.title = ""
        button.attributedTitle = statusAttributedTitle(
            for: text,
            appearance: button.effectiveAppearance
        )
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        refreshStatusDisplay()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startOutsideClickMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
        refreshStatusDisplay()
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusDisplay()
            }
        }
    }

    private func showInitialPopoverIfNeeded() {
        guard viewModel.shouldShowPermissionGuide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.viewModel.shouldShowPermissionGuide,
                  !self.popover.isShown,
                  let button = self.statusItem.button else { return }
            self.refreshStatusDisplay()
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.startOutsideClickMonitoring()
        }
    }

    private func statusText(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "" }

        if provider.type == .codex,
           let activeSlot = viewModel.codexSlotViewModels().first(where: { $0.isActive }),
           let percent = fiveHourPercent(from: activeSlot.snapshot) {
            return "\(Int(percent.rounded()))%"
        }

        guard let snapshot = viewModel.snapshots[provider.id] else {
            return ""
        }

        if provider.family == .thirdParty {
            guard let remaining = snapshot.remaining else { return "" }
            return formattedAmount(remaining)
        }

        if let percent = preferredPercent(from: snapshot) {
            return "\(Int(percent.rounded()))%"
        }
        if let remaining = snapshot.remaining {
            return formattedAmount(remaining)
        }
        return ""
    }

    private func preferredPercent(from snapshot: UsageSnapshot) -> Double? {
        if let percent = fiveHourPercent(from: snapshot) {
            return percent
        }
        if let window = snapshot.quotaWindows.first {
            return window.remainingPercent
        }
        if let remaining = snapshot.remaining, remaining >= 0, remaining <= 100, snapshot.unit == "%" {
            return remaining
        }
        return nil
    }

    private func fiveHourPercent(from snapshot: UsageSnapshot) -> Double? {
        if let session = snapshot.quotaWindows.first(where: { $0.kind == .session }) {
            return session.remainingPercent
        }
        if let titled = snapshot.quotaWindows.first(where: { window in
            let lower = window.title.lowercased()
            return lower.contains("5h") || lower.contains("session")
        }) {
            return titled.remainingPercent
        }
        return nil
    }

    private func formattedAmount(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.0f", value)
        }
        if abs(value) >= 100 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func statusTextAttributes(for appearance: NSAppearance) -> [NSAttributedString.Key: Any] {
        let isDarkAppearance = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor: NSColor = isDarkAppearance
            ? NSColor.white.withAlphaComponent(0.95)
            : NSColor.labelColor
        return [
            .font: statusFont,
            .foregroundColor: textColor
        ]
    }

    private func statusAttributedTitle(for text: String, appearance: NSAppearance) -> NSAttributedString {
        guard !text.isEmpty else {
            return NSAttributedString(string: "")
        }

        let result = NSMutableAttributedString()
        let spacer = NSTextAttachment()
        spacer.bounds = NSRect(x: 0, y: 0, width: statusSpacing, height: 1)
        result.append(NSAttributedString(attachment: spacer))
        result.append(NSAttributedString(
            string: text,
            attributes: statusTextAttributes(for: appearance)
        ))
        return result
    }

    private func image(for provider: ProviderDescriptor?) -> NSImage? {
        guard let provider else {
            if let appStatusImage { return appStatusImage }
            let fallback = NSImage(systemSymbolName: "app.badge", accessibilityDescription: "AI Plan Monitor")
            fallback?.isTemplate = true
            return fallback
        }
        switch provider.type {
        case .codex:
            if let codexStatusImage { return codexStatusImage }
            let fallback = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
            fallback?.isTemplate = true
            return fallback
        case .kimi:
            if let kimiStatusImage { return kimiStatusImage }
            let fallback = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi")
            fallback?.isTemplate = true
            return fallback
        case .relay, .open, .dragon, .claude, .gemini, .copilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf:
            if let relayStatusImage { return relayStatusImage }
            let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: "Relay")
            fallback?.isTemplate = true
            return fallback
        }
    }

    private func bundledImage(named name: String, ext: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func bundledMainImage(named name: String, ext: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfNeededForOutsideClick()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfNeededForOutsideClick()
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func closePopoverIfNeededForOutsideClick() {
        guard popover.isShown else { return }
        guard !isPermissionPromptForegroundApp() else { return }
        let mouseLocation = NSEvent.mouseLocation
        if isInsidePopover(mouseLocation) || isInsideStatusItem(mouseLocation) {
            return
        }
        popover.performClose(nil)
    }

    private func isPermissionPromptForegroundApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() else {
            return false
        }
        if protectedOutsideClickBundleIDs.contains(bundleID) {
            return true
        }
        return bundleID.contains("securityagent")
            || bundleID.contains("systemsettings")
            || bundleID.contains("systempreferences")
    }

    private func isInsidePopover(_ screenPoint: NSPoint) -> Bool {
        guard let frame = popover.contentViewController?.view.window?.frame else { return false }
        return frame.contains(screenPoint)
    }

    private func isInsideStatusItem(_ screenPoint: NSPoint) -> Bool {
        guard
            let button = statusItem.button,
            let window = button.window
        else {
            return false
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        return rectOnScreen.contains(screenPoint)
    }
}
