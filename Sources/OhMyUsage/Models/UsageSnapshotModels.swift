import OhMyUsageDomain

struct RelayDiagnosticSnapshotPreview: Equatable {
    var remaining: Double?
    var used: Double?
    var limit: Double?
    var unit: String
}

struct RelayDiagnosticResult: Equatable {
    var success: Bool
    var fetchHealth: FetchHealth
    var resolvedAdapterID: String
    var resolvedAuthSource: String?
    var message: String
    var snapshotPreview: RelayDiagnosticSnapshotPreview?
}
