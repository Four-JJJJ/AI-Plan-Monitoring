import OhMyUsageDomain
import Foundation

struct OfficialAccountSwitchVerificationResult {
    var descriptor: ProviderDescriptor?
    var snapshot: UsageSnapshot?

    static let none = OfficialAccountSwitchVerificationResult()
}

@MainActor
final class AppOfficialAccountSwitchCoordinator {
    func switchCodexProfile(
        slotID: CodexSlotID,
        transactionCoordinator: AccountSwitchTransactionCoordinator<CodexSlotID>,
        prepare: @escaping () throws -> CodexAccountProfile,
        apply: @escaping (CodexAccountProfile) async throws -> Void,
        restart: @escaping (CodexAccountProfile) async throws -> CodexDesktopAppRestartResult,
        verify: @escaping @MainActor (CodexAccountProfile) async throws -> OfficialAccountSwitchVerificationResult,
        commitVerifiedState: @escaping @MainActor (ProviderDescriptor, UsageSnapshot) -> Void,
        successMessage: @escaping (CodexDesktopAppRestartResult) -> String,
        setFeedback: @escaping @MainActor (CodexSwitchFeedback?, CodexSlotID) -> Void,
        recordVerifyError: @escaping @MainActor (ProviderDescriptor, String) -> Void,
        notify: @escaping @MainActor (String) -> Void,
        applyFailureMessage: @escaping (Error) -> String,
        verifyFailureMessage: @escaping (Error) -> String
    ) async {
        setFeedback(nil, slotID)
        var verification = OfficialAccountSwitchVerificationResult.none

        await transactionCoordinator.run(
            slotID: slotID,
            prepare: prepare,
            apply: apply,
            restart: restart,
            verify: { profile, _ in
                verification = try await verify(profile)
            },
            finalize: { _, restartResult in
                if let descriptor = verification.descriptor,
                   let snapshot = verification.snapshot {
                    commitVerifiedState(descriptor, snapshot)
                }
                let message = successMessage(restartResult)
                setFeedback(
                    CodexSwitchFeedback(message: message, isError: false),
                    slotID
                )
                if verification.descriptor != nil {
                    notify(message)
                }
            },
            fail: { failure in
                switch failure {
                case .prepare(let error):
                    setFeedback(
                        CodexSwitchFeedback(
                            message: error.localizedDescription,
                            isError: true
                        ),
                        slotID
                    )
                case .apply(let error), .restart(let error):
                    setFeedback(
                        CodexSwitchFeedback(
                            message: applyFailureMessage(error),
                            isError: true
                        ),
                        slotID
                    )
                case .verify(let error):
                    if let descriptor = verification.descriptor {
                        recordVerifyError(descriptor, error.localizedDescription)
                    }
                    setFeedback(
                        CodexSwitchFeedback(
                            message: verifyFailureMessage(error),
                            isError: true
                        ),
                        slotID
                    )
                    notify(verifyFailureMessage(error))
                }
            }
        )
    }

    func switchClaudeProfile(
        slotID: CodexSlotID,
        transactionCoordinator: AccountSwitchTransactionCoordinator<CodexSlotID>,
        prepare: @escaping () throws -> ClaudeAccountProfile,
        apply: @escaping (ClaudeAccountProfile) async throws -> Void,
        restart: @escaping (ClaudeAccountProfile) async throws -> Void,
        verify: @escaping @MainActor (ClaudeAccountProfile) async throws -> OfficialAccountSwitchVerificationResult,
        commitVerifiedState: @escaping @MainActor (ProviderDescriptor, UsageSnapshot) -> Void,
        verifiedSuccessMessage: String,
        localSuccessMessage: String,
        setFeedback: @escaping @MainActor (ClaudeSwitchFeedback?, CodexSlotID) -> Void,
        recordVerifyError: @escaping @MainActor (ProviderDescriptor, String) -> Void,
        notify: @escaping @MainActor (String) -> Void,
        applyFailureMessage: @escaping (Error) -> String,
        verifyFailureMessage: @escaping (Error) -> String
    ) async {
        setFeedback(nil, slotID)
        var verification = OfficialAccountSwitchVerificationResult.none

        await transactionCoordinator.run(
            slotID: slotID,
            prepare: prepare,
            apply: apply,
            restart: restart,
            verify: { profile, _ in
                verification = try await verify(profile)
            },
            finalize: { _, _ in
                guard let descriptor = verification.descriptor,
                      let snapshot = verification.snapshot else {
                    setFeedback(
                        ClaudeSwitchFeedback(
                            message: localSuccessMessage,
                            isError: false
                        ),
                        slotID
                    )
                    return
                }
                commitVerifiedState(descriptor, snapshot)
                setFeedback(
                    ClaudeSwitchFeedback(
                        message: verifiedSuccessMessage,
                        isError: false
                    ),
                    slotID
                )
                notify(verifiedSuccessMessage)
            },
            fail: { failure in
                switch failure {
                case .prepare(let error):
                    setFeedback(
                        ClaudeSwitchFeedback(
                            message: error.localizedDescription,
                            isError: true
                        ),
                        slotID
                    )
                case .apply(let error), .restart(let error):
                    setFeedback(
                        ClaudeSwitchFeedback(
                            message: applyFailureMessage(error),
                            isError: true
                        ),
                        slotID
                    )
                case .verify(let error):
                    if let descriptor = verification.descriptor {
                        recordVerifyError(descriptor, error.localizedDescription)
                    }
                    let message = verifyFailureMessage(error)
                    setFeedback(
                        ClaudeSwitchFeedback(message: message, isError: true),
                        slotID
                    )
                    notify(message)
                }
            }
        )
    }
}
