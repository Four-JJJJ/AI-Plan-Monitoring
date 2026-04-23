import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let viewModel: AppViewModel
    private let statusItem: NSStatusItem
    private var menuPanel: NSPanel?
    private var menuHostingController: NSHostingController<MenuContentView>?
    private var refreshTimer: Timer?
    private var wallpaperProbeTimer: Timer?
    private var wallpaperFollowUpWorkItems: [DispatchWorkItem] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    private var defaultNotificationObservers: [NSObjectProtocol] = []
    private var distributedNotificationObservers: [NSObjectProtocol] = []
    private let statusIconSize: CGFloat = 16
    private let popoverWidth: CGFloat = 316
    private let popoverMinHeight: CGFloat = 60
    private let popoverGapBelowStatusIcon: CGFloat = 1
    private let wallpaperProbeInterval: TimeInterval = 0.5
    private let wallpaperLuminanceCacheLimit = 12
    private let protectedOutsideClickBundleIDs: Set<String> = [
        "com.apple.securityagent",
        "com.apple.systemsettings",
        "com.apple.systempreferences",
        "com.apple.preference.security.remoteservice"
    ]
    private let popoverBackgroundColor = NSColor(
        calibratedRed: 0x23 / 255.0,
        green: 0x23 / 255.0,
        blue: 0x23 / 255.0,
        alpha: 1.0
    )
    private var providerStatusImageCache: [String: NSImage] = [:]
    private var wallpaperLuminanceCache: [String: Double] = [:]
    private var wallpaperLuminanceCacheOrder: [String] = []
    private var lastRenderedForegroundStyle: StatusBarForegroundStyle?
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
        super.init()
        configureStatusItem()
        configureMenuPanel()
        startWorkspaceObservation()
        viewModel.start()
        refreshStatusDisplay()
        startRefreshTimer()
        showInitialPopoverIfNeeded()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = false
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenuPanel() {
        let rootView = MenuContentView(viewModel: viewModel)
        let controller = NSHostingController(rootView: rootView)
        menuHostingController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: popoverWidth, height: popoverMinHeight)
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: popoverWidth, height: popoverMinHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .vibrantDark)
        panel.collectionBehavior = [.transient, .moveToActiveSpace]
        panel.contentViewController = controller
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        menuPanel = panel
        updatePopoverContentSizeIfNeeded()
    }

    private func refreshStatusDisplay() {
        guard let button = statusItem.button else { return }
        let foregroundStyle = resolvedForegroundStyle(for: button.window?.screen)
        lastRenderedForegroundStyle = foregroundStyle
        let displayProviders = viewModel.statusBarProvidersForDisplay()
        let entries = displayProviders.map { statusDisplayEntry(for: $0, foregroundStyle: foregroundStyle) }
        if entries.isEmpty {
            if let fallback = appStatusImage {
                button.image = fallback
                button.imagePosition = .imageOnly
            } else {
                let fallback = NSImage(systemSymbolName: "app.badge", accessibilityDescription: "AI Plan Monitor")
                fallback?.isTemplate = true
                button.image = fallback
                button.imagePosition = .imageOnly
            }
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            updatePopoverContentSizeIfNeeded()
            return
        }
        button.image = nil
        button.title = ""
        button.imagePosition = .imageLeading
        button.attributedTitle = StatusBarDisplayRenderer.attributedString(
            entries: entries,
            style: viewModel.statusBarDisplayStyle,
            foregroundStyle: foregroundStyle
        )
        updatePopoverContentSizeIfNeeded()
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        if isMenuPanelShown {
            closeMenuPanel()
            return
        }
        guard let button = statusItem.button else { return }
        showPopover(attachedTo: button)
    }

    private var isMenuPanelShown: Bool {
        menuPanel?.isVisible == true
    }

    private func closeMenuPanel() {
        guard isMenuPanelShown else { return }
        menuPanel?.orderOut(nil)
        stopOutsideClickMonitoring()
        refreshStatusDisplay()
    }

    private func updatePopoverContentSizeIfNeeded() {
        guard let controller = menuHostingController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let fitted = controller.sizeThatFits(in: NSSize(width: popoverWidth, height: .greatestFiniteMagnitude))
        let targetHeight = max(popoverMinHeight, ceil(fitted.height))
        let targetSize = NSSize(width: popoverWidth, height: targetHeight)

        if let panel = menuPanel,
           abs(panel.frame.size.height - targetHeight) > 0.5 {
            var frame = panel.frame
            let anchoredTop = frame.maxY
            frame.size = targetSize
            // 调整高度时保持顶部锚点不漂移，避免弹层与状态栏之间出现额外间隙。
            frame.origin.y = anchoredTop - frame.size.height
            panel.setFrame(frame, display: true)
        }

        if isMenuPanelShown, let button = statusItem.button {
            alignPopoverWindow(to: button)
        }
    }

    private func showPopover(attachedTo button: NSStatusBarButton) {
        refreshStatusDisplay()
        updatePopoverContentSizeIfNeeded()
        alignPopoverWindow(to: button)
        menuPanel?.orderFrontRegardless()
        startOutsideClickMonitoring()
    }

    private func statusIconRect(in button: NSStatusBarButton) -> NSRect {
        if let cell = button.cell as? NSButtonCell {
            let rect = cell.imageRect(forBounds: button.bounds)
            if rect.width > 0, rect.height > 0 {
                return rect
            }
        }
        return NSRect(
            x: button.bounds.minX,
            y: (button.bounds.height - statusIconSize) / 2,
            width: statusIconSize,
            height: statusIconSize
        )
    }

    private func alignPopoverWindow(to button: NSStatusBarButton) {
        guard
            let menuPanel,
            let statusItemWindow = button.window
        else {
            return
        }

        let iconRectInWindow = button.convert(statusIconRect(in: button), to: nil)
        let iconRectOnScreen = statusItemWindow.convertToScreen(iconRectInWindow)

        var frame = menuPanel.frame
        frame.origin.x = round(iconRectOnScreen.midX - (frame.width / 2))
        frame.origin.y = round(iconRectOnScreen.minY - popoverGapBelowStatusIcon - frame.height)

        if let screen = statusItemWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 4, dy: 4)
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }

        menuPanel.setFrame(frame, display: true)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusDisplay()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func startWorkspaceObservation() {
        stopWorkspaceObservation()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in workspaceNames {
            let observer = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWallpaperContextDidChange()
                }
            }
            workspaceNotificationObservers.append(observer)
        }

        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearWallpaperLuminanceCache()
                self?.refreshStatusDisplay()
            }
        }
        defaultNotificationObservers.append(screenObserver)

        let displayConfigObserver = NotificationCenter.default.addObserver(
            forName: AppViewModel.statusBarDisplayConfigDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusDisplay()
                self?.refreshWallpaperProbeState()
            }
        }
        defaultNotificationObservers.append(displayConfigObserver)

        let distributedCenter = DistributedNotificationCenter.default()
        let wallpaperNames: [Notification.Name] = [
            Notification.Name("com.apple.desktop"),
            Notification.Name("com.apple.desktop.changed")
        ]
        for name in wallpaperNames {
            let observer = distributedCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleWallpaperContextDidChange()
                }
            }
            distributedNotificationObservers.append(observer)
        }

        refreshWallpaperProbeState()
    }

    private func stopWorkspaceObservation() {
        guard
            !workspaceNotificationObservers.isEmpty
            || !defaultNotificationObservers.isEmpty
            || !distributedNotificationObservers.isEmpty
        else {
            return
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default
        let distributedCenter = DistributedNotificationCenter.default()
        for observer in workspaceNotificationObservers {
            workspaceCenter.removeObserver(observer)
        }
        for observer in defaultNotificationObservers {
            defaultCenter.removeObserver(observer)
        }
        for observer in distributedNotificationObservers {
            distributedCenter.removeObserver(observer)
        }
        workspaceNotificationObservers.removeAll()
        defaultNotificationObservers.removeAll()
        distributedNotificationObservers.removeAll()
        stopWallpaperProbeTimer()
        cancelWallpaperFollowUpRefreshes()
    }

    private func showInitialPopoverIfNeeded() {
        guard viewModel.shouldShowPermissionGuide else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self,
                  self.viewModel.shouldShowPermissionGuide,
                  !self.isMenuPanelShown,
                  let button = self.statusItem.button else { return }
            self.showPopover(attachedTo: button)
        }
    }

    private func statusText(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "" }

        if provider.type == .codex,
           let activeSlot = viewModel.codexSlotViewModels().first(where: { $0.isActive }),
           let percent = Self.fiveHourPercent(
               from: activeSlot.snapshot,
               displaysUsedQuota: provider.displaysUsedQuota
           ) {
            return "\(Int(percent.rounded()))%"
        }

        guard let snapshot = viewModel.snapshots[provider.id] else {
            return ""
        }

        if provider.family == .thirdParty {
            if provider.displaysUsedQuota, let used = snapshot.used {
                return formattedAmount(used)
            }
            guard let remaining = snapshot.remaining else { return "" }
            return formattedAmount(remaining)
        }

        if provider.traeDisplaysAmount,
           let amount = traePrimaryAmount(snapshot: snapshot, displaysUsedQuota: provider.displaysUsedQuota) {
            return TraeValueDisplayFormatter.format(amount, kind: .dollarBalance)
        }

        if let percent = preferredPercent(from: snapshot, provider: provider) {
            return "\(Int(percent.rounded()))%"
        }
        if provider.displaysUsedQuota, let used = snapshot.used {
            return formattedAmount(used)
        }
        if let remaining = snapshot.remaining {
            return formattedAmount(remaining)
        }
        return ""
    }

    private func statusDisplayName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        case .gemini:
            return "Gemini"
        case .copilot:
            return "GitHub Copilot"
        case .microsoftCopilot:
            return "Microsoft Copilot"
        case .zai:
            return "Z.ai"
        case .amp:
            return "Amp"
        case .cursor:
            return "Cursor"
        case .jetbrains:
            return "JetBrains"
        case .kiro:
            return "Kiro"
        case .windsurf:
            return "Windsurf"
        case .kimi:
            return provider.family == .official ? "Kimi Coding" : "Kimi"
        case .trae:
            return "Trae SOLO"
        case .openrouterCredits:
            return "OpenRouter Credits"
        case .openrouterAPI:
            return "OpenRouter API"
        case .ollamaCloud:
            return "Ollama Cloud"
        case .opencodeGo:
            return "OpenCode Go"
        case .relay, .open, .dragon:
            let trimmed = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "API" : trimmed
        }
    }

    private func statusPercent(for provider: ProviderDescriptor) -> Double? {
        if provider.type == .codex,
           let activeSlot = viewModel.codexSlotViewModels().first(where: { $0.isActive }),
           let percent = Self.fiveHourPercent(
               from: activeSlot.snapshot,
               displaysUsedQuota: provider.displaysUsedQuota
           ) {
            return percent
        }
        if viewModel.statusBarDisplayStyle == .barNamePercent,
           provider.family == .thirdParty,
           !provider.displaysUsedQuota,
           let percent = viewModel.thirdPartyBarPercent(for: provider.id) {
            return percent
        }
        guard let snapshot = viewModel.snapshots[provider.id] else { return nil }
        return preferredPercent(from: snapshot, provider: provider)
    }

    private func statusDisplayEntry(
        for provider: ProviderDescriptor,
        foregroundStyle: StatusBarForegroundStyle
    ) -> StatusBarDisplayEntry {
        StatusBarDisplayEntry(
            icon: image(for: provider, foregroundStyle: foregroundStyle),
            name: statusDisplayName(for: provider),
            valueText: statusText(for: provider),
            percent: statusPercent(for: provider)
        )
    }

    private func preferredPercent(from snapshot: UsageSnapshot, provider: ProviderDescriptor) -> Double? {
        if provider.type == .trae,
           let percent = Self.traePrimaryPercent(
            snapshot: snapshot,
            displaysUsedQuota: provider.displaysUsedQuota
           ) {
            return percent
        }
        if let percent = Self.fiveHourPercent(from: snapshot, displaysUsedQuota: provider.displaysUsedQuota) {
            return percent
        }
        if let window = snapshot.quotaWindows.first {
            return provider.displaysUsedQuota ? window.usedPercent : window.remainingPercent
        }
        if snapshot.unit == "%" {
            if provider.displaysUsedQuota,
               let used = snapshot.used,
               used >= 0, used <= 100 {
                return used
            }
            if let remaining = snapshot.remaining, remaining >= 0, remaining <= 100 {
                return remaining
            }
        }
        return nil
    }

    nonisolated static func traePrimaryPercent(
        snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        let primaryWindow = snapshot.quotaWindows.first(where: isTraeDollarWindow) ?? snapshot.quotaWindows.first
        if let primaryWindow {
            return displaysUsedQuota ? primaryWindow.usedPercent : primaryWindow.remainingPercent
        }
        if snapshot.unit == "%" {
            if displaysUsedQuota,
               let used = snapshot.used,
               used >= 0, used <= 100 {
                return used
            }
            if let remaining = snapshot.remaining,
               remaining >= 0, remaining <= 100 {
                return remaining
            }
        }
        return nil
    }

    nonisolated private static func isTraeDollarWindow(_ window: UsageQuotaWindow) -> Bool {
        let identifier = window.id.lowercased()
        let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return identifier.contains("dollar")
            || title.contains("dollar")
            || title.contains("美元")
    }

    private func traePrimaryAmount(
        snapshot: UsageSnapshot,
        displaysUsedQuota: Bool
    ) -> Double? {
        let primaryKey = displaysUsedQuota ? "dollarUsed" : "dollarRemaining"
        if let raw = snapshot.extras[primaryKey], let value = Double(raw) {
            return value
        }
        if displaysUsedQuota,
           let fallbackRaw = snapshot.extras["dollarRemaining"],
           let fallback = Double(fallbackRaw) {
            return fallback
        }
        if let window = snapshot.quotaWindows.first(where: Self.isTraeDollarWindow) ?? snapshot.quotaWindows.first {
            let displayPercent = displaysUsedQuota
                ? max(0, min(100, window.usedPercent))
                : max(0, min(100, window.remainingPercent))
            if let raw = snapshot.extras["dollarLimit"], let limit = Double(raw) {
                return max(0, limit * displayPercent / 100)
            }
        }
        return nil
    }

    nonisolated static func fiveHourPercent(
        from snapshot: UsageSnapshot,
        displaysUsedQuota: Bool = false
    ) -> Double? {
        if let session = snapshot.quotaWindows.first(where: { $0.kind == .session }) {
            return displaysUsedQuota ? session.usedPercent : session.remainingPercent
        }
        if let titled = snapshot.quotaWindows.first(where: { window in
            let lower = window.title.lowercased()
            return lower.contains("5h") || lower.contains("session")
        }) {
            return displaysUsedQuota ? titled.usedPercent : titled.remainingPercent
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

    private func resolvedForegroundStyle(for screen: NSScreen?) -> StatusBarForegroundStyle {
        if viewModel.statusBarAppearanceMode == .followWallpaper,
           let style = foregroundStyleFromStatusItemAppearance() {
            return style
        }
        let luminance = wallpaperLuminance(for: screen)
        return StatusBarAppearanceResolver.resolvedForegroundStyle(
            mode: viewModel.statusBarAppearanceMode,
            wallpaperLuminance: luminance
        )
    }

    private func foregroundStyleFromStatusItemAppearance() -> StatusBarForegroundStyle? {
        guard let button = statusItem.button else { return nil }
        let appearance = button.effectiveAppearance
        let names: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .aqua,
            .vibrantLight
        ]
        guard let matched = appearance.bestMatch(from: names) else {
            return nil
        }
        switch matched {
        case .darkAqua, .vibrantDark:
            return .light
        case .aqua, .vibrantLight:
            return .dark
        default:
            return nil
        }
    }

    private func wallpaperLuminance(for screen: NSScreen?) -> Double? {
        guard viewModel.statusBarAppearanceMode == .followWallpaper else {
            return nil
        }
        guard
            let resolvedScreen = screen ?? NSScreen.main,
            let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: resolvedScreen)
        else {
            return nil
        }
        let centerRatio = statusItemHorizontalCenterRatio(on: resolvedScreen)
        let cacheKey = wallpaperCacheKey(
            for: resolvedScreen,
            wallpaperURL: wallpaperURL,
            horizontalCenterRatio: centerRatio
        )
        if let cached = wallpaperLuminanceCache[cacheKey] {
            return cached
        }
        guard let wallpaper = NSImage(contentsOf: wallpaperURL) else {
            return nil
        }
        let luminance = StatusBarAppearanceResolver.wallpaperTopStripLuminance(
            from: wallpaper,
            horizontalCenterRatio: centerRatio
        )
        if let luminance {
            cacheWallpaperLuminance(luminance, forKey: cacheKey)
        }
        return luminance
    }

    private func wallpaperCacheKey(
        for screen: NSScreen,
        wallpaperURL: URL,
        horizontalCenterRatio: Double
    ) -> String {
        let screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
        let ratioBucket = Int((horizontalCenterRatio * 1000).rounded())
        return "\(screenID)|\(ratioBucket)|\(wallpaperURL.path)"
    }

    private func cacheWallpaperLuminance(_ value: Double, forKey key: String) {
        if wallpaperLuminanceCache[key] == nil {
            wallpaperLuminanceCacheOrder.append(key)
            if wallpaperLuminanceCacheOrder.count > wallpaperLuminanceCacheLimit {
                let evicted = wallpaperLuminanceCacheOrder.removeFirst()
                wallpaperLuminanceCache.removeValue(forKey: evicted)
            }
        }
        wallpaperLuminanceCache[key] = value
    }

    private func clearWallpaperLuminanceCache() {
        wallpaperLuminanceCache.removeAll(keepingCapacity: true)
        wallpaperLuminanceCacheOrder.removeAll(keepingCapacity: true)
    }

    private func refreshWallpaperProbeState() {
        if viewModel.statusBarAppearanceMode == .followWallpaper {
            startWallpaperProbeTimer()
        } else {
            stopWallpaperProbeTimer()
            cancelWallpaperFollowUpRefreshes()
            clearWallpaperLuminanceCache()
        }
    }

    private func startWallpaperProbeTimer() {
        guard wallpaperProbeTimer == nil else { return }
        let timer = Timer(timeInterval: wallpaperProbeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshWallpaperAppearanceIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        wallpaperProbeTimer = timer
    }

    private func stopWallpaperProbeTimer() {
        wallpaperProbeTimer?.invalidate()
        wallpaperProbeTimer = nil
    }

    private func refreshWallpaperAppearanceIfNeeded() {
        guard viewModel.statusBarAppearanceMode == .followWallpaper else { return }
        guard let button = statusItem.button else { return }
        let style = resolvedForegroundStyle(for: button.window?.screen)
        guard style != lastRenderedForegroundStyle else { return }
        refreshStatusDisplay()
    }

    private func handleWallpaperContextDidChange() {
        clearWallpaperLuminanceCache()
        refreshStatusDisplay()
        scheduleWallpaperFollowUpRefreshes()
    }

    private func scheduleWallpaperFollowUpRefreshes() {
        cancelWallpaperFollowUpRefreshes()
        guard viewModel.statusBarAppearanceMode == .followWallpaper else { return }
        let delays: [TimeInterval] = [0.12, 0.35, 0.8]
        for delay in delays {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.clearWallpaperLuminanceCache()
                self.refreshWallpaperAppearanceIfNeeded()
            }
            wallpaperFollowUpWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func cancelWallpaperFollowUpRefreshes() {
        wallpaperFollowUpWorkItems.forEach { $0.cancel() }
        wallpaperFollowUpWorkItems.removeAll(keepingCapacity: true)
    }

    private func statusItemHorizontalCenterRatio(on screen: NSScreen) -> Double {
        guard
            let button = statusItem.button,
            let window = button.window
        else {
            return 0.5
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        guard screen.frame.width > 0 else {
            return 0.5
        }
        let normalized = (rectOnScreen.midX - screen.frame.minX) / screen.frame.width
        return min(max(Double(normalized), 0), 1)
    }

    func showSettingsWindow() {
        SettingsWindowController.shared.show(viewModel: viewModel)
    }

    private func image(
        for provider: ProviderDescriptor?,
        foregroundStyle: StatusBarForegroundStyle
    ) -> NSImage? {
        guard let provider else {
            if let appStatusImage { return appStatusImage }
            let fallback = NSImage(systemSymbolName: "app.badge", accessibilityDescription: "AI Plan Monitor")
            fallback?.isTemplate = true
            return fallback
        }
        if let providerIcon = providerStatusImage(for: provider, foregroundStyle: foregroundStyle) {
            return providerIcon
        }
        switch provider.type {
        case .codex:
            let fallback = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
            fallback?.isTemplate = true
            return fallback
        case .kimi:
            let fallback = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Kimi")
            fallback?.isTemplate = true
            return fallback
        case .relay, .open, .dragon, .claude, .gemini, .copilot, .microsoftCopilot, .zai, .amp, .cursor, .jetbrains, .kiro, .windsurf, .trae, .openrouterCredits, .openrouterAPI, .ollamaCloud, .opencodeGo:
            let fallback = NSImage(systemSymbolName: "globe", accessibilityDescription: "Relay")
            fallback?.isTemplate = true
            return fallback
        }
    }

    private func providerStatusImage(
        for provider: ProviderDescriptor,
        foregroundStyle: StatusBarForegroundStyle
    ) -> NSImage? {
        let baseIconName = menuIconName(for: provider)
        let candidates = iconNameCandidates(baseIconName: baseIconName, foregroundStyle: foregroundStyle)
        for iconName in candidates {
            if let cached = providerStatusImageCache[iconName] {
                return cached
            }
            if let image = bundledImage(named: iconName, ext: "png") ?? bundledImage(named: iconName, ext: "svg") {
                image.size = NSSize(width: statusIconSize, height: statusIconSize)
                image.isTemplate = false
                providerStatusImageCache[iconName] = image
                return image
            }
        }
        return nil
    }

    private func iconNameCandidates(baseIconName: String, foregroundStyle: StatusBarForegroundStyle) -> [String] {
        switch foregroundStyle {
        case .light:
            return [baseIconName]
        case .dark:
            return ["\(baseIconName)_dark", baseIconName]
        }
    }

    private func menuIconName(for provider: ProviderDescriptor) -> String {
        switch provider.type {
        case .codex:
            return "menu_codex_icon"
        case .claude:
            return "menu_claude_icon"
        case .gemini:
            return "menu_gemini_icon"
        case .copilot:
            return "menu_github_copilot_icon"
        case .microsoftCopilot:
            return "menu_microsoft_copilot_icon"
        case .zai:
            return "menu_zai_icon"
        case .amp:
            return "menu_amp_icon"
        case .cursor:
            return "menu_cursor_icon"
        case .jetbrains:
            return "menu_jetbrains_icon"
        case .kiro:
            return "menu_kiro_icon"
        case .windsurf:
            return "menu_windsurf_icon"
        case .kimi:
            return "menu_kimi_icon"
        case .trae:
            return "menu_relay_icon"
        case .openrouterCredits, .openrouterAPI:
            return "menu_openrouter_icon"
        case .ollamaCloud:
            return "menu_ollama_icon"
        case .opencodeGo:
            return "menu_relay_icon"
        case .relay, .open, .dragon:
            if let override = relayModelIconOverrideName(for: provider) {
                return override
            }
            return "menu_relay_icon"
        }
    }

    private func relayModelIconOverrideName(for provider: ProviderDescriptor) -> String? {
        guard provider.type == .relay || provider.type == .open || provider.type == .dragon else {
            return nil
        }
        let relayID = (provider.relayConfig?.adapterID ?? provider.relayManifest?.id ?? "").lowercased()
        let relayBaseURL = provider.relayConfig?.baseURL ?? provider.baseURL ?? ""
        let host = URL(string: relayBaseURL)?.host?.lowercased() ?? ""
        let providerName = provider.name.lowercased()
        let relaySignals = "\(relayID)|\(host)|\(providerName)"
        if relaySignals.contains("moonshot") || relaySignals.contains("moonsho") || relaySignals.contains("kimi") {
            return "menu_kimi_icon"
        }
        if relaySignals.contains("deepseek") {
            return firstExistingRelayIconName(["menu_deepseek_icon", "menu_deep_seek_icon"])
        }
        if relaySignals.contains("xiaomimimo") || relaySignals.contains("mimo") {
            return firstExistingRelayIconName(["menu_mimo_icon", "menu_xiaomimimo_icon", "menu_xiaomi_mimo_icon"])
        }
        if relaySignals.contains("minimax") || relaySignals.contains("minimaxi") {
            return firstExistingRelayIconName(["menu_minimax_icon", "menu_minimaxi_icon"])
        }
        return nil
    }

    private func firstExistingRelayIconName(_ candidates: [String]) -> String? {
        for name in candidates {
            if Bundle.module.url(forResource: name, withExtension: "png") != nil ||
                Bundle.module.url(forResource: name, withExtension: "svg") != nil {
                return name
            }
        }
        return nil
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
        guard isMenuPanelShown else { return }
        guard !isPermissionPromptForegroundApp() else { return }
        let mouseLocation = NSEvent.mouseLocation
        if isInsidePopover(mouseLocation) || isInsideStatusItem(mouseLocation) {
            return
        }
        closeMenuPanel()
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
        guard let frame = menuPanel?.frame else { return false }
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
