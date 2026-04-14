import Foundation

struct CodexSlotID: RawRepresentable, Codable, Hashable, Comparable, Identifiable {
    var rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = trimmed.isEmpty ? "A" : trimmed.uppercased()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let a = CodexSlotID(rawValue: "A")
    static let b = CodexSlotID(rawValue: "B")

    static func generated(index: Int) -> CodexSlotID {
        CodexSlotID(rawValue: excelColumnName(for: index))
    }

    static func nextAvailable(excluding existing: Set<CodexSlotID>) -> CodexSlotID {
        var index = 0
        while true {
            let candidate = CodexSlotID.generated(index: index)
            if !existing.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    static func < (lhs: CodexSlotID, rhs: CodexSlotID) -> Bool {
        let left = sortComponents(for: lhs.rawValue)
        let right = sortComponents(for: rhs.rawValue)
        if left.numeric != right.numeric {
            return left.numeric < right.numeric
        }
        return left.raw < right.raw
    }

    private static func sortComponents(for rawValue: String) -> (numeric: Int, raw: String) {
        let normalized = rawValue.uppercased()
        if let excelIndex = excelColumnIndex(for: normalized) {
            return (excelIndex, normalized)
        }
        if let numeric = Int(normalized) {
            return (numeric, normalized)
        }
        return (Int.max, normalized)
    }

    private static func excelColumnName(for index: Int) -> String {
        var value = max(0, index)
        var result = ""
        repeat {
            let remainder = value % 26
            let scalar = UnicodeScalar(65 + remainder)!
            result = String(Character(scalar)) + result
            value = (value / 26) - 1
        } while value >= 0
        return result
    }

    private static func excelColumnIndex(for rawValue: String) -> Int? {
        guard rawValue.allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return nil }
        var result = 0
        for character in rawValue {
            guard let scalar = character.unicodeScalars.first else { return nil }
            result = result * 26 + Int(scalar.value) - 64
        }
        return result - 1
    }
}

struct CodexAccountSlot: Codable, Equatable, Identifiable {
    var id: String { slotID.rawValue }
    var slotID: CodexSlotID
    var accountKey: String
    var displayName: String
    var lastSnapshot: UsageSnapshot
    var lastSeenAt: Date
    var isActive: Bool
}

final class CodexAccountSlotStore {
    private struct SlotFile: Codable {
        var slots: [CodexAccountSlot]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let staleInterval: TimeInterval
    private var slots: [CodexAccountSlot]

    init(
        fileManager: FileManager = .default,
        staleInterval: TimeInterval = 7 * 24 * 60 * 60,
        fileURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("AIBalanceMonitor", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("codex_slots.json")
        }
        self.staleInterval = staleInterval
        self.slots = []
        self.slots = load()
    }

    func reset() {
        slots = []
        try? fileManager.removeItem(at: fileURL)
    }

    func visibleSlots(now: Date = Date()) -> [CodexAccountSlot] {
        removeStaleSlots(now: now)
        return slots.sorted(by: sortRule)
    }

    func upsertActive(snapshot: UsageSnapshot, now: Date = Date()) -> [CodexAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)
        let preferredSlotID = Self.explicitSlotID(from: snapshot)

        removeStaleSlots(now: now)

        for index in slots.indices {
            slots[index].isActive = false
        }

        if let preferredSlotID,
           let conflicting = slots.firstIndex(where: { $0.slotID == preferredSlotID && $0.accountKey != accountKey }) {
            slots.remove(at: conflicting)
        }

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
            if let preferredSlotID {
                slots[existing].slotID = preferredSlotID
            }
            slots[existing].displayName = displayName
            slots[existing].lastSnapshot = snapshot
            slots[existing].lastSeenAt = now
            slots[existing].isActive = true
            save()
            return slots.sorted(by: sortRule)
        }

        // Unknown identity should stay single-slot to avoid fake account splits.
        if accountKey == "unknown", let unknownIndex = slots.firstIndex(where: { $0.accountKey == "unknown" }) {
            slots[unknownIndex].displayName = displayName
            slots[unknownIndex].lastSnapshot = snapshot
            slots[unknownIndex].lastSeenAt = now
            slots[unknownIndex].isActive = true
            save()
            return slots.sorted(by: sortRule)
        }

        let occupied = Set(slots.map(\.slotID))
        let slotID = preferredSlotID ?? CodexSlotID.nextAvailable(excluding: occupied)

        let slot = CodexAccountSlot(
            slotID: slotID,
            accountKey: accountKey,
            displayName: displayName,
            lastSnapshot: snapshot,
            lastSeenAt: now,
            isActive: true
        )
        slots.append(slot)
        save()
        return slots.sorted(by: sortRule)
    }

    static func accountKey(from snapshot: UsageSnapshot) -> String {
        if let explicitKey = snapshot.rawMeta["codex.accountKey"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicitKey.isEmpty {
            return explicitKey.lowercased()
        }

        if let accountID = snapshot.rawMeta["codex.accountId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountID.isEmpty {
            return "account:\(accountID.lowercased())"
        }

        if let fingerprint = snapshot.rawMeta["codex.credentialFingerprint"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fingerprint.isEmpty {
            return "fingerprint:\(fingerprint.lowercased())"
        }

        if let subject = snapshot.rawMeta["codex.subject"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            return "subject:\(subject.lowercased())"
        }

        let label = accountLabel(from: snapshot)
        if !label.isEmpty, label != "Unknown" {
            return "email:\(label.lowercased())"
        }

        return "unknown"
    }

    static func explicitSlotID(from snapshot: UsageSnapshot) -> CodexSlotID? {
        guard let rawValue = snapshot.rawMeta["codex.slotID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return CodexSlotID(rawValue: rawValue)
    }

    static func accountLabel(from snapshot: UsageSnapshot) -> String {
        if let label = snapshot.accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        if let label = snapshot.rawMeta["codex.accountLabel"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !label.isEmpty {
            return label
        }
        return "Unknown"
    }

    private func sortRule(lhs: CodexAccountSlot, rhs: CodexAccountSlot) -> Bool {
        if lhs.isActive != rhs.isActive {
            return lhs.isActive && !rhs.isActive
        }
        if lhs.lastSeenAt != rhs.lastSeenAt {
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
        return lhs.slotID < rhs.slotID
    }

    private func removeStaleSlots(now: Date) {
        let before = slots.count
        slots.removeAll { now.timeIntervalSince($0.lastSeenAt) > staleInterval }
        if slots.count != before {
            save()
        }
    }

    private func load() -> [CodexAccountSlot] {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(SlotFile.self, from: data) {
            return decoded.slots
        }
        return []
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(SlotFile(slots: slots)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
