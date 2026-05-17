import Foundation

struct IdentityLogScanResult {
    var events: [ParsedTokenEvent]
    var diagnostics: CodexLocalUsageDiagnostics
}

struct ParsedTokenEvent {
    var signature: String
    var eventAt: Date
    var modelID: String
    var totalTokens: Int
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheWriteTokens: Int = 0
    var accountID: String?
    var email: String?

    var hasIdentity: Bool {
        accountID != nil || email != nil
    }

    func mergedIdentity(with other: ParsedTokenEvent) -> ParsedTokenEvent {
        ParsedTokenEvent(
            signature: signature,
            eventAt: eventAt,
            modelID: modelID,
            totalTokens: totalTokens,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            accountID: accountID ?? other.accountID,
            email: email ?? other.email
        )
    }
}

struct TokenComponents: Equatable, Sendable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    var totalTokens = 0

    func delta(from previous: TokenComponents, fallbackTotal: Int) -> TokenComponents {
        let input = max(0, inputTokens - previous.inputTokens)
        let output = max(0, outputTokens - previous.outputTokens)
        let cacheRead = max(0, cacheReadTokens - previous.cacheReadTokens)
        let cacheWrite = max(0, cacheWriteTokens - previous.cacheWriteTokens)
        let total = max(0, totalTokens - previous.totalTokens)
        let componentTotal = input + output + cacheRead + cacheWrite
        if componentTotal == 0, fallbackTotal > 0 {
            return TokenComponents(outputTokens: fallbackTotal, totalTokens: fallbackTotal)
        }
        return TokenComponents(
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite,
            totalTokens: total > 0 ? total : componentTotal
        )
    }

    func adding(_ other: TokenComponents) -> TokenComponents {
        TokenComponents(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
            totalTokens: totalTokens + other.totalTokens
        )
    }
}

struct ParsedCodexSSEMetadata {
    var kind: String?
    var conversationID: String?
    var accountID: String?
    var email: String?

    var hasIdentity: Bool {
        accountID != nil || email != nil
    }
}
