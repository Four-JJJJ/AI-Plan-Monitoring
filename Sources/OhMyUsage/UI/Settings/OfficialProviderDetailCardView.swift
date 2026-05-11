import SwiftUI

struct OfficialProviderDetailCardView<Header: View, MainSettings: View, Supplemental: View>: View {
    var itemSpacing: CGFloat
    var header: Header
    var mainSettings: MainSettings
    var supplemental: Supplemental

    init(
        itemSpacing: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder mainSettings: () -> MainSettings,
        @ViewBuilder supplemental: () -> Supplemental
    ) {
        self.itemSpacing = itemSpacing
        self.header = header()
        self.mainSettings = mainSettings()
        self.supplemental = supplemental()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: itemSpacing) {
                mainSettings
            }
            .padding(.top, itemSpacing)

            supplemental
        }
    }
}
