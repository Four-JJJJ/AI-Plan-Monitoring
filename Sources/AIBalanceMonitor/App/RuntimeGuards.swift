import AppKit
import Foundation

@MainActor
final class SingleInstanceLock {
    static let shared = SingleInstanceLock()

    private var fd: Int32 = -1
    private let lockPath = "/tmp/com.fourj.aibalancemonitor.lock"

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app stays menu-bar only even if started from terminal context.
        NSApp.setActivationPolicy(.accessory)

        if !SingleInstanceLock.shared.acquire() {
            NSApp.terminate(nil)
        }
    }
}
