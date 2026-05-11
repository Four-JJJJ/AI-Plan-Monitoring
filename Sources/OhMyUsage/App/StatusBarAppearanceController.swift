import AppKit
import Foundation

@MainActor
final class StatusBarAppearanceController {
    private let wallpaperAppearanceService: WallpaperAppearanceService
    private var wallpaperFollowUpWorkItems: [DispatchWorkItem] = []
    private var workspaceNotificationObservers: [NSObjectProtocol] = []
    private var defaultNotificationObservers: [NSObjectProtocol] = []
    private var distributedNotificationObservers: [NSObjectProtocol] = []
    private var lastRenderedForegroundStyle: StatusBarForegroundStyle?

    init(
        wallpaperAppearanceService: WallpaperAppearanceService = WallpaperAppearanceService()
    ) {
        self.wallpaperAppearanceService = wallpaperAppearanceService
    }

    func updateRenderedForegroundStyle(_ style: StatusBarForegroundStyle) {
        lastRenderedForegroundStyle = style
    }

    func resolvedForegroundStyle(
        mode: StatusBarAppearanceMode,
        probe: WallpaperAppearanceProbe?,
        fallbackStyle: StatusBarForegroundStyle?
    ) -> StatusBarForegroundStyle {
        wallpaperAppearanceService.resolvedForegroundStyle(
            mode: mode,
            probe: probe,
            fallbackStyle: fallbackStyle
        )
    }

    func startObservation(
        onWallpaperContextDidChange: @escaping @MainActor () -> Void,
        onScreenParametersChanged: @escaping @MainActor () -> Void,
        onDisplayConfigChanged: @escaping @MainActor () -> Void
    ) {
        stopObservation()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification
        ]
        for name in workspaceNames {
            let observer = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    onWallpaperContextDidChange()
                }
            }
            workspaceNotificationObservers.append(observer)
        }

        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.wallpaperAppearanceService.clearCache()
                onScreenParametersChanged()
            }
        }
        defaultNotificationObservers.append(screenObserver)

        let displayConfigObserver = NotificationCenter.default.addObserver(
            forName: AppViewModel.statusBarDisplayConfigDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onDisplayConfigChanged()
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
            ) { _ in
                Task { @MainActor in
                    onWallpaperContextDidChange()
                }
            }
            distributedNotificationObservers.append(observer)
        }
    }

    func stopObservation() {
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
        cancelFollowUpRefreshes()
    }

    func refreshWallpaperProbeState(
        mode: StatusBarAppearanceMode,
        resolveCurrentStyle: () -> StatusBarForegroundStyle,
        onRefreshNeeded: () -> Void
    ) {
        if mode == .followWallpaper {
            let style = resolveCurrentStyle()
            guard Self.shouldRefreshAppearance(
                mode: mode,
                newStyle: style,
                lastRenderedStyle: lastRenderedForegroundStyle
            ) else {
                return
            }
            onRefreshNeeded()
        } else {
            cancelFollowUpRefreshes()
            wallpaperAppearanceService.clearCache()
        }
    }

    func handleWallpaperContextDidChange(
        mode: StatusBarAppearanceMode,
        onRefreshDisplay: @escaping @MainActor () -> Void
    ) {
        wallpaperAppearanceService.clearCache()
        onRefreshDisplay()
        scheduleFollowUpRefreshes(
            mode: mode,
            onRefreshDisplay: onRefreshDisplay
        )
    }

    func scheduleFollowUpRefreshes(
        mode: StatusBarAppearanceMode,
        onRefreshDisplay: @escaping @MainActor () -> Void
    ) {
        cancelFollowUpRefreshes()
        guard mode == .followWallpaper else { return }
        for delay in Self.followUpRefreshDelays {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.wallpaperAppearanceService.clearCache()
                onRefreshDisplay()
            }
            wallpaperFollowUpWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func cancelFollowUpRefreshes() {
        wallpaperFollowUpWorkItems.forEach { $0.cancel() }
        wallpaperFollowUpWorkItems.removeAll(keepingCapacity: true)
    }

    static let followUpRefreshDelays: [TimeInterval] = [0.12, 0.35, 0.8]

    static func shouldRefreshAppearance(
        mode: StatusBarAppearanceMode,
        newStyle: StatusBarForegroundStyle,
        lastRenderedStyle: StatusBarForegroundStyle?
    ) -> Bool {
        mode == .followWallpaper && newStyle != lastRenderedStyle
    }
}
