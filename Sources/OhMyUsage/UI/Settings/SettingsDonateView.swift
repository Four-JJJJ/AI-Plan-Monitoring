import AppKit
import SwiftUI

struct SettingsDonateView: View {
    var message: String
    var alipayAccessibilityLabel: String
    var wechatAccessibilityLabel: String

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 24) {
                HStack(alignment: .top, spacing: 40) {
                    donationImage(
                        named: "donate_alipay_qr",
                        width: 220,
                        height: 240,
                        verticalOffset: -15,
                        accessibilityLabel: alipayAccessibilityLabel
                    )

                    donationImage(
                        named: "donate_wechat_qr",
                        width: 220,
                        height: 220,
                        accessibilityLabel: wechatAccessibilityLabel
                    )
                }
                .padding(40)
                .frame(width: 560, height: 320, alignment: .top)
                .overlay(
                    SettingsSmoothedRoundedRectangle(cornerRadius: 12, smoothing: 0.6)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: min(560, max(0, proxy.size.width - 48)))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 144)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func donationImage(
        named name: String,
        width: CGFloat,
        height: CGFloat,
        verticalOffset: CGFloat = 0,
        accessibilityLabel: String
    ) -> some View {
        if let image = bundledImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .offset(y: verticalOffset)
                .frame(width: width, height: height)
                .clipShape(SettingsSmoothedRoundedRectangle(cornerRadius: 8, smoothing: 0.6))
                .accessibilityLabel(accessibilityLabel)
        } else {
            SettingsSmoothedRoundedRectangle(cornerRadius: 8, smoothing: 0.6)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: height)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private func bundledImage(named name: String) -> NSImage? {
        for fileExtension in ["png", "jpg", "jpeg"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
                  let image = NSImage(contentsOf: url),
                  image.isValid else {
                continue
            }
            image.isTemplate = false
            return image
        }
        return nil
    }
}
