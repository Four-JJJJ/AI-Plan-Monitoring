import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    private override init() {
        super.init()
    }

    func show(viewModel: AppViewModel) {
        let targetContentSize = NSSize(width: 960, height: 671)
        if window == nil {
            // 窗口基础尺寸：对应设置页整体画布宽高（与 Figma 画板尺寸对齐）。
            let panel = NSWindow(
                contentRect: NSRect(origin: .zero, size: targetContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            // 标题文案仅用于系统信息，页面视觉里隐藏。
            panel.title = "AI Plan Monitor Settings"
            // 隐藏默认标题文字，保留 macOS 原生三色按钮区域。
            panel.titleVisibility = .hidden
            // 让标题栏区域与内容区视觉融合，三色按钮看起来“贴”在页面背景上。
            panel.titlebarAppearsTransparent = true
            panel.toolbar = nil
            // 关闭标题栏和内容区之间的系统分割线。
            panel.titlebarSeparatorStyle = .none
            // 明确清零内容边界，避免顶部出现额外横线。
            panel.setContentBorderThickness(0, for: .minY)
            // 整个窗口使用纯不透明背景。
            panel.isOpaque = true
            // 窗口背景色（标题栏和内容区外层底色）。
            panel.backgroundColor = NSColor(
                red: 35.0 / 255.0,
                green: 35.0 / 255.0,
                blue: 35.0 / 255.0,
                alpha: 1
            )
            // 强制深色外观，避免跟随系统浅色导致样式偏差。
            panel.appearance = NSAppearance(named: .darkAqua)
            // 允许拖动背景区域移动窗口，避免顶部透明区域无法拖动。
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            // 固定“内容区”为 960x671（min/max 需使用 frameRect 尺寸）。
            let fixedFrameSize = panel.frameRect(
                forContentRect: NSRect(origin: .zero, size: targetContentSize)
            ).size
            panel.minSize = fixedFrameSize
            panel.maxSize = fixedFrameSize
            panel.setContentSize(targetContentSize)
            panel.center()
            window = panel
        }

        let rootView = AnyView(
            SettingsView(viewModel: viewModel, onDone: { [weak self] in
                self?.window?.orderOut(nil)
            })
            // SwiftUI 内容区尺寸：与目标 contentRect 保持一致。
            .frame(width: targetContentSize.width, height: targetContentSize.height)
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            hostingController = controller
            window?.contentViewController = controller
        }
        window?.setContentSize(targetContentSize)
        ensureSingleBorderContentAppearance()

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let panel = window {
            layoutTrafficLights(in: panel)
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.layoutTrafficLights(in: panel)
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow else { return }
        layoutTrafficLights(in: panel)
    }

    private func ensureSingleBorderContentAppearance() {
        guard let panel = window, let contentView = panel.contentView else { return }
        // 只保留 NSWindow 外层边界；内容视图不再额外绘制轮廓。
        contentView.wantsLayer = true
        contentView.layer?.borderWidth = 0
        contentView.layer?.cornerRadius = 0
        contentView.layer?.masksToBounds = false
    }

    private func layoutTrafficLights(in panel: NSWindow) {
        guard
            let close = panel.standardWindowButton(.closeButton),
            let mini = panel.standardWindowButton(.miniaturizeButton),
            let zoom = panel.standardWindowButton(.zoomButton),
            let container = close.superview
        else {
            return
        }

        let buttonSize = close.frame.size
        let spacing: CGFloat = 6
        let leftInset: CGFloat = 14
        let topInset: CGFloat = 12
        let y = max(0, container.bounds.height - topInset - buttonSize.height)

        // 固定尺寸窗口下，系统可能把 zoom 按钮置灰；强制维持视觉可用态。
        zoom.isEnabled = true
        zoom.alphaValue = 1.0

        close.setFrameOrigin(NSPoint(x: leftInset, y: y))
        mini.setFrameOrigin(NSPoint(x: leftInset + buttonSize.width + spacing, y: y))
        zoom.setFrameOrigin(NSPoint(x: leftInset + (buttonSize.width + spacing) * 2, y: y))
    }
}
