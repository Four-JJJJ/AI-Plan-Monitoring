import AppKit
import SwiftUI

@MainActor
final class MenuPanelController {
    private var menuPanel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private weak var attachedButton: NSStatusBarButton?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var onDidClose: (() -> Void)?

    private let popoverWidth: CGFloat
    private let popoverMinHeight: CGFloat
    private let popoverMaxHeight: CGFloat
    private let popoverGapBelowStatusIcon: CGFloat
    private let protectedOutsideClickBundleIDs: Set<String>
    private let addGlobalMonitor: (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    private let addLocalMonitor: (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
    private let removeMonitor: (Any) -> Void
    private let mouseLocationProvider: () -> NSPoint
    private let frontmostBundleIDProvider: () -> String?

    init(
        popoverWidth: CGFloat = 340,
        popoverMinHeight: CGFloat = 60,
        popoverMaxHeight: CGFloat = 800,
        gapBelowStatusIcon: CGFloat = 1,
        protectedOutsideClickBundleIDs: Set<String> = [
            "com.apple.securityagent",
            "com.apple.systemsettings",
            "com.apple.systempreferences",
            "com.apple.preference.security.remoteservice"
        ],
        addGlobalMonitor: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any? = {
            NSEvent.addGlobalMonitorForEvents(matching: $0, handler: $1)
        },
        addLocalMonitor: @escaping (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any? = {
            NSEvent.addLocalMonitorForEvents(matching: $0, handler: $1)
        },
        removeMonitor: @escaping (Any) -> Void = { monitor in
            NSEvent.removeMonitor(monitor)
        },
        mouseLocationProvider: @escaping () -> NSPoint = { NSEvent.mouseLocation },
        frontmostBundleIDProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased()
        }
    ) {
        self.popoverWidth = popoverWidth
        self.popoverMinHeight = popoverMinHeight
        self.popoverMaxHeight = popoverMaxHeight
        self.popoverGapBelowStatusIcon = gapBelowStatusIcon
        self.protectedOutsideClickBundleIDs = protectedOutsideClickBundleIDs
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
        self.mouseLocationProvider = mouseLocationProvider
        self.frontmostBundleIDProvider = frontmostBundleIDProvider
    }

    var isShown: Bool {
        menuPanel?.isVisible == true
    }

    func configure<Content: View>(rootView: Content) {
        let controller = NSHostingController(rootView: AnyView(rootView))
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
        panel.minSize = NSSize(width: popoverWidth, height: popoverMinHeight)
        panel.maxSize = NSSize(width: popoverWidth, height: popoverMaxHeight)
        panel.contentViewController = controller
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }

        hostingController = controller
        menuPanel = panel
        updateContentSizeIfNeeded(attachedButton: nil)
    }

    func updateContentSizeIfNeeded(attachedButton: NSStatusBarButton?) {
        if let attachedButton {
            self.attachedButton = attachedButton
        }
        guard let controller = hostingController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let fitted = controller.sizeThatFits(in: NSSize(width: popoverWidth, height: .greatestFiniteMagnitude))
        let targetHeight = max(popoverMinHeight, min(popoverMaxHeight, ceil(fitted.height)))
        let targetSize = NSSize(width: popoverWidth, height: targetHeight)

        if let panel = menuPanel,
           abs(panel.frame.size.height - targetHeight) > 0.5 {
            var frame = panel.frame
            let anchoredTop = frame.maxY
            frame.size = targetSize
            frame.origin.y = anchoredTop - frame.size.height
            panel.setFrame(frame, display: true)
        }

        if isShown, let button = self.attachedButton {
            alignPanelWindow(to: button)
        }
    }

    func show(
        attachedTo button: NSStatusBarButton,
        onDidShow: (() -> Void)? = nil,
        onDidClose: @escaping () -> Void
    ) {
        attachedButton = button
        self.onDidClose = onDidClose
        updateContentSizeIfNeeded(attachedButton: button)
        alignPanelWindow(to: button)
        menuPanel?.orderFrontRegardless()
        startOutsideClickMonitoring()
        onDidShow?()
    }

    func close(onDidClose overrideDidClose: (() -> Void)? = nil) {
        guard isShown else { return }
        menuPanel?.orderOut(nil)
        stopOutsideClickMonitoring()
        let callback = overrideDidClose ?? onDidClose
        onDidClose = nil
        callback?()
    }

    private func alignPanelWindow(to button: NSStatusBarButton) {
        guard
            let panel = menuPanel,
            let statusItemWindow = button.window
        else {
            return
        }

        let iconRectInWindow = button.convert(statusIconRect(in: button), to: nil)
        let iconRectOnScreen = statusItemWindow.convertToScreen(iconRectInWindow)
        let visible = (statusItemWindow.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 4, dy: 4)
        let frame = MenuPanelGeometryResolver.alignedPanelFrame(
            panelFrame: panel.frame,
            iconRectOnScreen: iconRectOnScreen,
            visibleFrame: visible,
            gapBelowStatusIcon: popoverGapBelowStatusIcon
        )
        panel.setFrame(frame, display: true)
    }

    private func statusIconRect(in button: NSStatusBarButton) -> NSRect {
        if let cell = button.cell as? NSButtonCell {
            let rect = cell.imageRect(forBounds: button.bounds)
            if rect.width > 0, rect.height > 0 {
                return rect
            }
        }
        let fallbackRect = MenuPanelGeometryResolver.fallbackStatusIconRect(
            buttonBounds: button.bounds,
            statusIconSize: 16
        )
        return NSRect(origin: fallbackRect.origin, size: fallbackRect.size)
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        globalMouseMonitor = addGlobalMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverIfNeededForOutsideClick()
            }
        }
        localMouseMonitor = addLocalMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePopoverIfNeededForOutsideClick()
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let globalMouseMonitor {
            removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }

    private func closePopoverIfNeededForOutsideClick() {
        let statusItemFrame = statusItemFrameOnScreen(for: attachedButton)
        let shouldClose = Self.shouldCloseForOutsideClick(
            isShown: isShown,
            isProtectedForegroundApp: Self.isProtectedOutsideClickBundleID(
                frontmostBundleIDProvider(),
                protectedOutsideClickBundleIDs: protectedOutsideClickBundleIDs
            ),
            mouseLocation: mouseLocationProvider(),
            panelFrame: menuPanel?.frame,
            statusItemFrame: statusItemFrame
        )
        if shouldClose {
            close()
        }
    }

    private func statusItemFrameOnScreen(for button: NSStatusBarButton?) -> NSRect? {
        guard
            let button,
            let window = button.window
        else {
            return nil
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    static func shouldCloseForOutsideClick(
        isShown: Bool,
        isProtectedForegroundApp: Bool,
        mouseLocation: NSPoint,
        panelFrame: NSRect?,
        statusItemFrame: NSRect?
    ) -> Bool {
        guard isShown else { return false }
        guard !isProtectedForegroundApp else { return false }
        if let panelFrame, panelFrame.contains(mouseLocation) {
            return false
        }
        if let statusItemFrame, statusItemFrame.contains(mouseLocation) {
            return false
        }
        return true
    }

    static func isProtectedOutsideClickBundleID(
        _ bundleID: String?,
        protectedOutsideClickBundleIDs: Set<String>
    ) -> Bool {
        guard let bundleID = bundleID?.lowercased() else {
            return false
        }
        if protectedOutsideClickBundleIDs.contains(bundleID) {
            return true
        }
        return bundleID.contains("securityagent")
            || bundleID.contains("systemsettings")
            || bundleID.contains("systempreferences")
    }
}
