import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    private init() {}

    func show(viewModel: AppViewModel) {
        if window == nil {
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "AI Balance Monitor Settings"
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 860, height: 620)
            panel.center()
            window = panel
        }

        let rootView = AnyView(
            SettingsView(viewModel: viewModel, onDone: { [weak self] in
                self?.window?.orderOut(nil)
            })
            .frame(minWidth: 860, minHeight: 620)
        )

        if let hostingController {
            hostingController.rootView = rootView
        } else {
            let controller = NSHostingController(rootView: rootView)
            hostingController = controller
            window?.contentViewController = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
