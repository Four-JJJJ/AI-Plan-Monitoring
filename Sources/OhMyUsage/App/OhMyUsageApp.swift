import AppKit
import SwiftUI

@main
struct OhMyUsageApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
