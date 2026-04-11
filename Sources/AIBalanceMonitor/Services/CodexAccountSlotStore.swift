import Foundation

enum CodexSlotID: String, Codable, CaseIterable {
    case a = "A"
    case b = "B"
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
    private let staleInterval: TimeInterval
    private var slots: [CodexAccountSlot]

    init(
        fileManager: FileManager = .default,
        staleInterval: TimeInterval = 7 * 24 * 60 * 60,
        fileURL: URL? = nil
    ) {
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

    func visibleSlots(now: Date = Date()) -> [CodexAccountSlot] {
        removeStaleSlots(now: now)
        return slots.sorted(by: sortRule)
    }

    func upsertActive(snapshot: UsageSnapshot, now: Date = Date()) -> [CodexAccountSlot] {
        let accountKey = Self.accountKey(from: snapshot)
        let displayName = Self.accountLabel(from: snapshot)

        removeStaleSlots(now: now)

        for index in slots.indices {
            slots[index].isActive = false
        }

        if let existing = slots.firstIndex(where: { $0.accountKey == accountKey }) {
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

        let slotID: CodexSlotID
        if slots.count < 2 {
            let occupied = Set(slots.map(\.slotID))
            slotID = occupied.contains(.a) ? .b : .a
        } else {
            let replaceIndex = slots.indices.min { lhs, rhs in
                slots[lhs].lastSeenAt < slots[rhs].lastSeenAt
            } ?? 0
            slotID = slots[replaceIndex].slotID
            slots.remove(at: replaceIndex)
        }

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
        if let accountID = snapshot.rawMeta["codex.accountId"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountID.isEmpty {
            return "account:\(accountID.lowercased())"
        }

        let label = accountLabel(from: snapshot)
        if !label.isEmpty, label != "Unknown" {
            return "email:\(label.lowercased())"
        }

        if let subject = snapshot.rawMeta["codex.subject"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subject.isEmpty {
            return "subject:\(subject.lowercased())"
        }

        return "unknown"
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
        return lhs.slotID.rawValue < rhs.slotID.rawValue
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
