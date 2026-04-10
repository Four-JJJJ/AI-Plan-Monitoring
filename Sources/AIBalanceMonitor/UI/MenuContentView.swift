import AppKit
import SwiftUI

struct MenuContentView: View {
    @Bindable var viewModel: AppViewModel
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            separator
            cards
            separator
            footer
        }
        .frame(width: 360)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .environment(\.colorScheme, .dark)
        .onReceive(clock) { value in
            now = value
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(viewModel.text(.appTitle))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 4)

            if let date = viewModel.lastUpdatedAt {
                Text("\(viewModel.text(.updatedAgo)) \(elapsedText(from: date))")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.30))
            }
        }
    }

    private var cards: some View {
        VStack(spacing: 8) {
            ForEach(displayProviders) { provider in
                providerCard(provider)
            }
        }
    }

    @ViewBuilder
    private func providerCard(_ provider: ProviderDescriptor) -> some View {
        let snapshot = viewModel.snapshots[provider.id]
        let error = viewModel.errors[provider.id]

        if provider.type == .codex || provider.type == .kimi {
            quotaCard(provider: provider, snapshot: snapshot, error: error)
        } else {
            balanceCard(snapshot: snapshot, error: error, threshold: provider.threshold.lowRemaining)
        }
    }

    private func quotaCard(provider: ProviderDescriptor, snapshot: UsageSnapshot?, error: String?) -> some View {
        let metrics = quotaMetrics(provider: provider, snapshot: snapshot)
        let minPercent = metrics.map(\.percent).min() ?? 100
        let warning = minPercent <= provider.threshold.lowRemaining
        let disconnected = error != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                cardTitle(provider: provider)
                Spacer()
                Text(disconnected ? viewModel.text(.statusDisconnected) : (warning ? viewModel.text(.statusTight) : viewModel.text(.statusSufficient)))
                    .font(.system(size: 10))
                    .foregroundStyle(disconnected ? Color(hex: 0xD83E3E) : (warning ? Color(hex: 0xD87E3E) : Color(hex: 0x51DB42)))
            }

            HStack(spacing: 20) {
                ForEach(metrics) { metric in
                    quotaMetric(metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xD83E3E))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.black)
        )
    }

    private func balanceCard(snapshot: UsageSnapshot?, error: String?, threshold: Double) -> some View {
        let remaining = snapshot?.remaining ?? 0
        let level = balanceLevel(remaining: remaining, threshold: threshold, hasError: error != nil)
        let statusText: String
        let statusColor: Color
        switch level {
        case .sufficient:
            statusText = viewModel.text(.statusSufficient)
            statusColor = Color(hex: 0x51DB42)
        case .tight:
            statusText = viewModel.text(.statusTight)
            statusColor = Color(hex: 0xD87E3E)
        case .exhausted, .error:
            statusText = level == .error ? viewModel.text(.statusDisconnected) : viewModel.text(.statusExhausted)
            statusColor = Color(hex: 0xD83E3E)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                cardTitle(provider: nil)
                Spacer()
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.text(.balanceLabel))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.50))
                HStack(spacing: 2) {
                    Text("💰")
                        .font(.system(size: 14, weight: .semibold))
                    Text(formattedBalanceNumber(remaining))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
            }

            if let error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xD83E3E))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.black)
        )
    }

    private func cardTitle(provider: ProviderDescriptor?) -> some View {
        HStack(spacing: 4) {
            localIcon(name: iconName(for: provider), fallback: fallbackIcon(for: provider))
            Text(displayName(for: provider))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func quotaMetric(_ metric: QuotaMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(metric.title)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                if let resetAt = metric.resetAt {
                    Text(resetText(to: resetAt))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Text("\(Int(metric.percent.rounded()))%")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, alignment: .leading)
                    .lineLimit(1)
                    .layoutPriority(2)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.30))
                        Capsule(style: .continuous)
                            .fill(barColor(for: metric.percent))
                            .frame(width: max(8, geo.size.width * metric.percent / 100))
                    }
                }
                .frame(height: 4)
                .layoutPriority(0)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(title: viewModel.text(.refreshNow), iconName: "refresh_icon", fallback: "arrow.clockwise") {
                viewModel.refreshNow()
            }
            footerButton(title: viewModel.text(.settings).replacingOccurrences(of: "...", with: ""), iconName: "settings_icon", fallback: "gearshape") {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }
            footerButton(title: viewModel.text(.quit), iconName: "quit_icon", fallback: "xmark", textColor: Color.white.opacity(0.80)) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func footerButton(title: String, iconName: String, fallback: String, textColor: Color = Color.white.opacity(0.80), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                localIcon(name: iconName, fallback: fallback, size: 13, tint: textColor)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(textColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    private var displayProviders: [ProviderDescriptor] {
        viewModel.config.providers
            .filter(\.enabled)
            .sorted { lhs, rhs in
                let l = providerRank(lhs.type)
                let r = providerRank(rhs.type)
                if l != r { return l < r }
                return lhs.id < rhs.id
            }
    }

    private func providerRank(_ type: ProviderType) -> Int {
        switch type {
        case .codex: return 0
        case .kimi: return 1
        case .open, .dragon: return 2
        }
    }

    private func displayName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return viewModel.text(.thirdPartyRelay) }
        switch provider.type {
        case .codex:
            return "Codex"
        case .kimi:
            return "KIMI"
        case .open, .dragon:
            return viewModel.text(.thirdPartyRelay)
        }
    }

    private func iconName(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "relay_icon" }
        switch provider.type {
        case .codex:
            return "codex_icon"
        case .kimi:
            return "kimi_icon"
        case .open, .dragon:
            return "relay_icon"
        }
    }

    private func fallbackIcon(for provider: ProviderDescriptor?) -> String {
        guard let provider else { return "link" }
        switch provider.type {
        case .codex:
            return "terminal.fill"
        case .kimi:
            return "moon.stars.fill"
        case .open, .dragon:
            return "link"
        }
    }

    private func localIcon(name: String, fallback: String, size: CGFloat = 12, tint: Color? = nil) -> some View {
        Group {
            if let image = bundledImage(named: name) {
                if let tint {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tint)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Image(systemName: fallback)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint ?? Color.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
    }

    private func bundledImage(named name: String) -> NSImage? {
        if let pngURL = Bundle.module.url(forResource: name, withExtension: "png"),
           let pngImage = NSImage(contentsOf: pngURL) {
            return pngImage
        }
        if let svgURL = Bundle.module.url(forResource: name, withExtension: "svg"),
           let svgImage = NSImage(contentsOf: svgURL) {
            return svgImage
        }
        return nil
    }

    private func quotaMetrics(provider: ProviderDescriptor, snapshot: UsageSnapshot?) -> [QuotaMetric] {
        guard let snapshot else { return [] }

        switch provider.type {
        case .codex:
            return [
                QuotaMetric(
                    id: "\(provider.id)-primary",
                    title: viewModel.text(.quotaFiveHour),
                    percent: clamp(metaDouble("primaryRemainingPercent", in: snapshot) ?? snapshot.remaining ?? 0),
                    resetAt: metaDate("primaryResetAt", in: snapshot)
                ),
                QuotaMetric(
                    id: "\(provider.id)-secondary",
                    title: viewModel.text(.quotaWeekly),
                    percent: clamp(metaDouble("secondaryRemainingPercent", in: snapshot) ?? 0),
                    resetAt: metaDate("secondaryResetAt", in: snapshot)
                )
            ]
        case .kimi:
            return [
                QuotaMetric(
                    id: "\(provider.id)-5h",
                    title: viewModel.text(.quotaFiveHour),
                    percent: clamp(metaDouble("kimi.window5h.remainingPercent", in: snapshot) ?? 0),
                    resetAt: metaDate("kimi.window5h.resetAt", in: snapshot)
                ),
                QuotaMetric(
                    id: "\(provider.id)-weekly",
                    title: viewModel.text(.quotaWeekly),
                    percent: clamp(metaDouble("kimi.weekly.remainingPercent", in: snapshot) ?? 0),
                    resetAt: metaDate("kimi.weekly.resetAt", in: snapshot)
                )
            ]
        case .open, .dragon:
            return []
        }
    }

    private func barColor(for percent: Double) -> Color {
        if percent <= 20 { return Color(hex: 0xE64545) }
        if percent <= 40 { return Color(hex: 0xD87E3E) }
        return Color(hex: 0x51DB42)
    }

    private func balanceLevel(remaining: Double, threshold: Double, hasError: Bool) -> BalanceLevel {
        if hasError { return .error }
        if remaining <= 0.0001 { return .exhausted }
        if remaining <= threshold { return .tight }
        return .sufficient
    }

    private func formattedBalanceNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func elapsedText(from date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch viewModel.language {
        case .zhHans:
            if seconds < 60 { return "\(seconds) 秒前" }
            if seconds < 3600 { return "\(seconds / 60) 分钟前" }
            if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
            return "\(seconds / 86_400) 天前"
        case .en:
            if seconds < 60 { return "\(seconds)s ago" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86_400 { return "\(seconds / 3600)h ago" }
            return "\(seconds / 86_400)d ago"
        }
    }

    private func resetText(to target: Date) -> String {
        let interval = max(0, Int(target.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        let seconds = interval % 60

        switch viewModel.language {
        case .zhHans:
            if days > 0 {
                return "\(days)天\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))后重置"
            }
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))后重置"
        case .en:
            if days > 0 {
                return "resets in \(days)d \(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
            }
            return "resets in \(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
    }

    private func metaDouble(_ key: String, in snapshot: UsageSnapshot) -> Double? {
        snapshot.rawMeta[key].flatMap(Double.init)
    }

    private func metaDate(_ key: String, in snapshot: UsageSnapshot) -> Date? {
        guard let raw = snapshot.rawMeta[key], let epoch = TimeInterval(raw), epoch > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

private struct QuotaMetric: Identifiable {
    let id: String
    let title: String
    let percent: Double
    let resetAt: Date?
}

private enum BalanceLevel {
    case sufficient
    case tight
    case exhausted
    case error
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
