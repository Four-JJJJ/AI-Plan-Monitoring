import AppKit
import SwiftUI

@main
struct AIBalanceMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(viewModel: viewModel)
                .onAppear {
                    viewModel.start()
                }
        } label: {
            Label("AI", systemImage: viewModel.aggregateStatus.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}
