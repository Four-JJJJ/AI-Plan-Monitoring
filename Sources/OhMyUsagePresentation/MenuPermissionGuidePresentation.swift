public struct MenuPermissionGuideStrings: Equatable, Sendable {
    public struct PermissionItem: Equatable, Sendable {
        public var title: String
        public var hint: String
        public var actionTitle: String

        public init(title: String, hint: String, actionTitle: String) {
            self.title = title
            self.hint = hint
            self.actionTitle = actionTitle
        }
    }

    public var title: String
    public var privacyPromise: String
    public var notifications: PermissionItem
    public var keychain: PermissionItem
    public var fullDisk: PermissionItem
    public var localDiscovery: PermissionItem
    public var grantedStatusText: String
    public var pendingStatusText: String
    public var waitingStatusText: String
    public var localDiscoveryReadyStatusText: String
    public var localDiscoveryDoneStatusText: String

    public init(
        title: String,
        privacyPromise: String,
        notifications: PermissionItem,
        keychain: PermissionItem,
        fullDisk: PermissionItem,
        localDiscovery: PermissionItem,
        grantedStatusText: String,
        pendingStatusText: String,
        waitingStatusText: String,
        localDiscoveryReadyStatusText: String,
        localDiscoveryDoneStatusText: String
    ) {
        self.title = title
        self.privacyPromise = privacyPromise
        self.notifications = notifications
        self.keychain = keychain
        self.fullDisk = fullDisk
        self.localDiscovery = localDiscovery
        self.grantedStatusText = grantedStatusText
        self.pendingStatusText = pendingStatusText
        self.waitingStatusText = waitingStatusText
        self.localDiscoveryReadyStatusText = localDiscoveryReadyStatusText
        self.localDiscoveryDoneStatusText = localDiscoveryDoneStatusText
    }
}

public enum MenuPermissionGuideLocalDiscoveryState: Equatable, Sendable {
    case idle
    case inFlight
    case completed
}

public struct MenuPermissionGuidePresentation: Equatable, Sendable {
    public var title: String
    public var privacyPromise: String
    public var rows: [MenuPermissionGuideRowPresentation]

    public init(
        title: String,
        privacyPromise: String,
        rows: [MenuPermissionGuideRowPresentation]
    ) {
        self.title = title
        self.privacyPromise = privacyPromise
        self.rows = rows
    }

    public static func build(
        strings: MenuPermissionGuideStrings,
        hasNotificationPermission: Bool,
        secureStorageReady: Bool,
        fullDiskAccessRelevant: Bool,
        fullDiskAccessRequested: Bool,
        fullDiskAccessGranted: Bool,
        canRunLocalDiscovery: Bool,
        localDiscoveryState: MenuPermissionGuideLocalDiscoveryState
    ) -> MenuPermissionGuidePresentation {
        var rows: [MenuPermissionGuideRowPresentation] = [
            permissionRow(
                kind: .notifications,
                strings: strings.notifications,
                isGranted: hasNotificationPermission,
                actionKind: .requestNotifications,
                guideStrings: strings
            ),
            permissionRow(
                kind: .keychain,
                strings: strings.keychain,
                isGranted: secureStorageReady,
                actionKind: .prepareKeychain,
                guideStrings: strings
            )
        ]

        if fullDiskAccessRelevant || fullDiskAccessRequested {
            rows.append(
                fullDiskRow(
                    strings: strings.fullDisk,
                    isGranted: fullDiskAccessGranted,
                    isRequested: fullDiskAccessRequested,
                    guideStrings: strings
                )
            )
        }

        if canRunLocalDiscovery {
            rows.append(localDiscoveryRow(strings: strings.localDiscovery, state: localDiscoveryState, guideStrings: strings))
        }

        return MenuPermissionGuidePresentation(
            title: strings.title,
            privacyPromise: strings.privacyPromise,
            rows: rows
        )
    }

    private static func permissionRow(
        kind: MenuPermissionGuideRowPresentation.Kind,
        strings: MenuPermissionGuideStrings.PermissionItem,
        isGranted: Bool,
        actionKind: MenuPermissionGuideRowPresentation.ActionKind,
        guideStrings: MenuPermissionGuideStrings
    ) -> MenuPermissionGuideRowPresentation {
        MenuPermissionGuideRowPresentation(
            kind: kind,
            title: strings.title,
            hint: strings.hint,
            statusText: isGranted ? guideStrings.grantedStatusText : guideStrings.pendingStatusText,
            tone: isGranted ? .success : .warning,
            actionTitle: isGranted ? nil : strings.actionTitle,
            actionKind: isGranted ? nil : actionKind
        )
    }

    private static func fullDiskRow(
        strings: MenuPermissionGuideStrings.PermissionItem,
        isGranted: Bool,
        isRequested: Bool,
        guideStrings: MenuPermissionGuideStrings
    ) -> MenuPermissionGuideRowPresentation {
        MenuPermissionGuideRowPresentation(
            kind: .fullDisk,
            title: strings.title,
            hint: strings.hint,
            statusText: isGranted
                ? guideStrings.grantedStatusText
                : (isRequested ? guideStrings.waitingStatusText : guideStrings.pendingStatusText),
            tone: isGranted ? .success : .warning,
            actionTitle: isGranted ? nil : strings.actionTitle,
            actionKind: isGranted ? nil : .openFullDiskSettings
        )
    }

    private static func localDiscoveryRow(
        strings: MenuPermissionGuideStrings.PermissionItem,
        state: MenuPermissionGuideLocalDiscoveryState,
        guideStrings: MenuPermissionGuideStrings
    ) -> MenuPermissionGuideRowPresentation {
        let isInFlight = state == .inFlight
        return MenuPermissionGuideRowPresentation(
            kind: .localDiscovery,
            title: strings.title,
            hint: strings.hint,
            statusText: localDiscoveryStatusText(state: state, guideStrings: guideStrings),
            tone: isInFlight ? .warning : .success,
            actionTitle: isInFlight ? nil : strings.actionTitle,
            actionKind: isInFlight ? nil : .runLocalDiscovery
        )
    }

    private static func localDiscoveryStatusText(
        state: MenuPermissionGuideLocalDiscoveryState,
        guideStrings: MenuPermissionGuideStrings
    ) -> String {
        switch state {
        case .idle:
            return guideStrings.localDiscoveryReadyStatusText
        case .inFlight:
            return guideStrings.waitingStatusText
        case .completed:
            return guideStrings.localDiscoveryDoneStatusText
        }
    }
}

public struct MenuPermissionGuideRowPresentation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case notifications
        case keychain
        case fullDisk
        case localDiscovery
    }

    public enum Tone: Equatable, Sendable {
        case success
        case warning
    }

    public enum ActionKind: Equatable, Sendable {
        case requestNotifications
        case prepareKeychain
        case openFullDiskSettings
        case runLocalDiscovery
    }

    public var kind: Kind
    public var title: String
    public var hint: String
    public var statusText: String
    public var tone: Tone
    public var actionTitle: String?
    public var actionKind: ActionKind?

    public init(
        kind: Kind,
        title: String,
        hint: String,
        statusText: String,
        tone: Tone,
        actionTitle: String?,
        actionKind: ActionKind?
    ) {
        self.kind = kind
        self.title = title
        self.hint = hint
        self.statusText = statusText
        self.tone = tone
        self.actionTitle = actionTitle
        self.actionKind = actionKind
    }
}
