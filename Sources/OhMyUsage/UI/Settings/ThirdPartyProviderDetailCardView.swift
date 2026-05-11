import SwiftUI

struct ThirdPartyProviderDetailCardView<Header: View, MainSettings: View>: View {
    var itemSpacing: CGFloat
    var header: Header
    var mainSettings: MainSettings

    init(
        itemSpacing: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder mainSettings: () -> MainSettings
    ) {
        self.itemSpacing = itemSpacing
        self.header = header()
        self.mainSettings = mainSettings()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: itemSpacing) {
                mainSettings
            }
            .padding(.top, itemSpacing)
        }
    }
}
