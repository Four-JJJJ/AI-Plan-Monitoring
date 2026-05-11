import Foundation

enum OfficialProfileNaming {
    static let noteLimit = 8
    static let codexModelName = "Codex"
    static let claudeModelName = "Claude"

    static func limitedNote(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(trimmed.prefix(noteLimit))
    }

    static func normalizedNote(_ raw: String?) -> String? {
        let note = limitedNote(raw)
        return note.isEmpty ? nil : note
    }

    static func displayName(modelName: String, slotID: CodexSlotID, note: String?) -> String {
        let baseName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseName = baseName.isEmpty ? slotID.rawValue : baseName
        guard let note = normalizedNote(note) else {
            return "\(resolvedBaseName) \(slotID.rawValue)"
        }
        return "\(resolvedBaseName) \(note)"
    }
}
