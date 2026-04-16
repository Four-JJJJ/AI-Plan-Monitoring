import Foundation

final class KiroProvider: UsageProvider, @unchecked Sendable {
    let descriptor: ProviderDescriptor

    init(descriptor: ProviderDescriptor) {
        self.descriptor = descriptor
    }

    func fetch() async throws -> UsageSnapshot {
        let official = descriptor.officialConfig ?? ProviderDescriptor.defaultOfficialConfig(type: .kiro)
        guard official.sourceMode == .auto || official.sourceMode == .cli else {
            throw ProviderError.unavailable("Kiro 官方来源当前仅支持 CLI 检测")
        }

        guard ShellCommand.run(executable: "/usr/bin/env", arguments: ["which", "kiro-cli"], timeout: 5)?.status == 0 else {
            throw ProviderError.unavailable("未检测到 kiro-cli")
        }
        guard let result = ShellCommand.run(
            executable: "/usr/bin/env",
            arguments: ["kiro-cli"],
            input: "/usage\n/quit\n",
            timeout: 20
        ), result.status == 0 || !result.stdout.isEmpty else {
            throw ProviderError.commandFailed("kiro-cli /usage 执行失败")
        }
        return try Self.parseSnapshot(text: result.stdout, descriptor: descriptor)
    }

    internal static func parseSnapshot(text: String, descriptor: ProviderDescriptor) throws -> UsageSnapshot {
        let clean = text.replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#, with: "", options: .regularExpression)
        var windows: [UsageQuotaWindow] = []

        let bonus = clean.regexCaptures(pattern: #"Bonus credits:\s*([\d.]+)/([\d.]+)"#)
        if bonus.count >= 3,
           let used = Double(bonus[1]), let total = Double(bonus[2]), total > 0 {
            let remainingPercent = max(0, (total - used) / total * 100)
            let days = clean.regexCaptures(pattern: #"expires in (\d+) days"#)
            let resetAt = days.count >= 2 ? Date().addingTimeInterval((Double(days[1]) ?? 0) * 24 * 3600) : nil
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-bonus",
                    title: "Bonus",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }

        let credits = clean.regexCaptures(pattern: #"Credits \(([\d.]+) of ([\d.]+)"#)
        if credits.count >= 3,
           let used = Double(credits[1]), let total = Double(credits[2]), total > 0 {
            let remainingPercent = max(0, (total - used) / total * 100)
            var resetAt: Date?
            let reset = clean.regexCaptures(pattern: #"resets on (\d{2}/\d{2})"#)
            if reset.count >= 2 {
                let comps = reset[1].split(separator: "/").compactMap { Int($0) }
                if comps.count == 2 {
                    var parts = Calendar.current.dateComponents([.year], from: Date())
                    parts.month = comps[0]
                    parts.day = comps[1]
                    resetAt = Calendar.current.date(from: parts)
                }
            }
            windows.append(
                UsageQuotaWindow(
                    id: "\(descriptor.id)-credits",
                    title: "Credits",
                    remainingPercent: remainingPercent,
                    usedPercent: max(0, 100 - remainingPercent),
                    resetAt: resetAt,
                    kind: .custom
                )
            )
        }

        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("No quota data found in Kiro CLI output")
        }
        let remaining = windows.map(\.remainingPercent).min() ?? 0
        return UsageSnapshot(
            source: descriptor.id,
            status: remaining <= descriptor.threshold.lowRemaining ? .warning : .ok,
            remaining: remaining,
            used: 100 - remaining,
            limit: 100,
            unit: "%",
            updatedAt: Date(),
            note: windows.map { "\($0.title) \(Int($0.remainingPercent.rounded()))%" }.joined(separator: " | "),
            quotaWindows: windows,
            sourceLabel: "CLI",
            accountLabel: nil,
            extras: [:],
            rawMeta: [:]
        )
    }
}

private extension String {
    func regexCaptures(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return [] }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}
