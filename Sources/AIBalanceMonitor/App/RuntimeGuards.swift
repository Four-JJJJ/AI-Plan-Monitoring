import AppKit
import Foundation

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fd: Int32 = -1
    private let lockPath = "/tmp/com.aibalancemonitor.app.lock"

    private init() {}

    func acquire() -> Bool {
        if fd != -1 {
            return true
        }

        fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd != -1 else {
            return false
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            return true
        }

        close(fd)
        fd = -1
        return false
    }

    deinit {
        if fd != -1 {
            flock(fd, LOCK_UN)
            close(fd)
        }
    }
}

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app stays menu-bar only even if started from terminal context.
        applyBundledAppIcon()
        NSApp.setActivationPolicy(.accessory)

        if !SingleInstanceLock.shared.acquire() {
            NSApp.terminate(nil)
            return
        }

        statusBarController = StatusBarController(viewModel: AppViewModel())
    }

    @MainActor
    private func applyBundledAppIcon() {
        let bundlePath = Bundle.main.bundleURL.path
        let workspaceIcon = NSWorkspace.shared.icon(forFile: bundlePath)
        if workspaceIcon.isValid {
            workspaceIcon.size = NSSize(width: 256, height: 256)
            NSApp.applicationIconImage = workspaceIcon
            return
        }

        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        icon.size = NSSize(width: 256, height: 256)
        NSApp.applicationIconImage = icon
    }
}
