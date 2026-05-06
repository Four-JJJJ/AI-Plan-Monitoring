import SwiftUI

struct SettingsRootView: View {
    @Bindable var viewModel: AppViewModel
    var onDone: (() -> Void)?

    var body: some View {
        SettingsView(viewModel: viewModel, onDone: onDone)
    }
}
