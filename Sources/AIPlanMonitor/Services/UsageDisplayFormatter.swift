import Foundation

enum LocalTrendDisplayMetric: String, CaseIterable, Sendable {
    case tokens
    case responses
}

enum PlanTypeDisplayFormatter {
    private static let supportedProviderTypes: Set<ProviderType> = [
        .codex, .claude, .gemini, .kimi
    ]

    private static let hiddenValues: Set<String> = [
        "-", "unknown", "n/a", "na", "none", "null"
    ]

    static func supportsPlanType(providerType: ProviderType) -> Bool {
        supportedProviderTypes.contains(providerType)
    }

    static func normalizedPlanType(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        if hiddenValues.contains(raw.lowercased()) {
            return nil
        }
        return raw
    }

    static func resolvedPlanType(
        providerType: ProviderType,
        extrasPlanType: String?,
        rawPlanType: String?
    ) -> String? {
        guard supportsPlanType(providerType: providerType) else {
            return nil
        }
        guard let resolved = normalizedPlanType(extrasPlanType) ?? normalizedPlanType(rawPlanType) else {
            return nil
        }
        return normalizedDisplayPlanType(resolved, providerType: providerType)
    }

    private static func normalizedDisplayPlanType(_ value: String, providerType: ProviderType) -> String {
        switch providerType {
        case .codex, .claude:
            return titleCaseASCIIWords(value)
        case .kimi:
            return normalizedKimiPlanType(value)
        default:
            return value
        }
    }

    private static func normalizedKimiPlanType(_ value: String) -> String {
        let normalizedKey = normalizeKimiPlanKey(value)
        let mapping: [String: String] = [
            "FREE": "Adagio",
            "10": "Adagio",
            "ADAGIO": "Adagio",
            "TRIAL": "Andante",
            "15": "Andante",
            "ANDANTE": "Andante",
            "BASIC": "Moderato",
            "20": "Moderato",
            "MODERATO": "Moderato",
            "INTERMEDIATE": "Allegretto",
            "25": "Allegretto",
            "ALLEGRETTO": "Allegretto",
            "ADVANCED": "Allegro",
            "27": "Allegro",
            "ALLEGRO": "Allegro"
        ]
        return mapping[normalizedKey] ?? value
    }

    private static func normalizeKimiPlanKey(_ value: String) -> String {
        let uppercase = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if uppercase.hasPrefix("LEVEL_") {
            return normalizeKimiPlanKey(String(uppercase.dropFirst("LEVEL_".count)))
        }
        if uppercase.hasPrefix("MEMBERSHIP_LEVEL_") {
            return normalizeKimiPlanKey(String(uppercase.dropFirst("MEMBERSHIP_LEVEL_".count)))
        }
        let separators = CharacterSet(charactersIn: " _-")
        let pieces = uppercase.components(separatedBy: separators).filter { !$0.isEmpty }
        return pieces.joined()
    }

    private static func titleCaseASCIIWords(_ value: String) -> String {
        guard value.unicodeScalars.allSatisfy(\.isASCII) else {
            return value
        }

        var output = ""
        var shouldUppercase = true
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if shouldUppercase {
                    output += String(scalar).uppercased()
                    shouldUppercase = false
                } else {
                    output.append(Character(scalar))
                }
            } else {
                output.append(Character(scalar))
                shouldUppercase = scalar == " " || scalar == "-" || scalar == "_" || scalar == "/"
            }
        }
        return output
    }
}

enum LocalTrendValueFormatter {
    static func compactNumber(_ value: Int, language: AppLanguage) -> String {
        switch language {
        case .zhHans:
            return compactZh(value)
        case .en:
            return compactEn(value)
        }
    }

    static func metricValueText(
        value: Int,
        metric: LocalTrendDisplayMetric,
        language: AppLanguage
    ) -> String {
        let compactValue = compactNumber(max(0, value), language: language)
        switch (metric, language) {
        case (.tokens, .zhHans), (.tokens, .en):
            return "\(compactValue) tokens"
        case (.responses, .zhHans):
            return "\(compactValue)次"
        case (.responses, .en):
            return "\(compactValue) req"
        }
    }

    private static func compactZh(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 100_000_000 {
            return "\(compactDecimal(Double(safeValue) / 100_000_000))亿"
        }
        if safeValue >= 10_000 {
            return "\(compactDecimal(Double(safeValue) / 10_000))万"
        }
        return "\(safeValue)"
    }

    private static func compactEn(_ value: Int) -> String {
        let safeValue = max(0, value)
        if safeValue >= 1_000_000_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000_000_000))B"
        }
        if safeValue >= 1_000_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000_000))M"
        }
        if safeValue >= 1_000 {
            return "\(compactDecimal(Double(safeValue) / 1_000))K"
        }
        return groupedInteger(safeValue, localeID: "en_US_POSIX")
    }

    private static func compactDecimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.000_1 {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private static func groupedInteger(_ value: Int, localeID: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeID)
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
