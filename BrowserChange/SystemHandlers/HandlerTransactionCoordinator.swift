import Foundation

enum HandlerTransactionIssue: Equatable, Sendable {
    case targetUnavailable
    case missingBaseline(WebScheme)
    case handlerChangeFailed
    case verificationFailed
    case handlersChangedExternally
    case rollbackFailed
    case statePersistenceFailed
    case noUndoReceipt
    case undoPreconditionFailed
}

enum HandlerTransactionOutcome: Equatable, Sendable {
    case succeeded
    case cancelled
    case failed(HandlerTransactionIssue)
    case degraded(HandlerTransactionIssue)
    case refused(HandlerTransactionIssue)
}

enum HandlerRecoveryOutcome: Equatable, Sendable {
    case nothingPending
    case completedSwitch
    case completedUndo
    case rolledBack
    case degraded(HandlerTransactionIssue)
}

enum HandlerTransactionStatus: Equatable, Sendable {
    case idle
    case switching
    case undoing
    case recovering
    case degraded

    var isBusy: Bool {
        switch self {
        case .switching, .undoing, .recovering:
            true
        case .idle, .degraded:
            false
        }
    }
}

@MainActor
final class HandlerTransactionCoordinator {
    private enum ReconciliationResult {
        case restored
        case externalChange
        case failed
    }

    private static let schemeOrder: [WebScheme] = [.https, .http]

    private let systemHandler: any SystemBrowserHandling
    private let repository: StateRepository
    private let browserChange: BrowserReference
    private let now: () -> Date
    private let makeOperationID: () -> UUID

    init(
        systemHandler: any SystemBrowserHandling,
        repository: StateRepository,
        browserChange: BrowserReference = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? "com.browserchange.BrowserChange"
        ),
        now: @escaping () -> Date = Date.init,
        makeOperationID: @escaping () -> UUID = UUID.init
    ) {
        self.systemHandler = systemHandler
        self.repository = repository
        self.browserChange = browserChange
        self.now = now
        self.makeOperationID = makeOperationID
    }

    func switchDirect(
        to browser: BrowserReference
    ) async -> HandlerTransactionOutcome {
        await switchHandlers(
            to: browser,
            kind: .direct,
            permitsBrowserChange: false
        )
    }

    func activateSmartRouting(
        configuration: RoutingConfiguration
    ) async -> HandlerTransactionOutcome {
        await switchHandlers(
            to: browserChange,
            kind: .smartActivation,
            permitsBrowserChange: true,
            configurationOnSuccess: configuration
        )
    }

    func deactivateSmartRouting(
        to browser: BrowserReference,
        configuration: RoutingConfiguration
    ) async -> HandlerTransactionOutcome {
        await switchHandlers(
            to: browser,
            kind: .smartDeactivation,
            permitsBrowserChange: false,
            configurationOnSuccess: configuration
        )
    }

    private func switchHandlers(
        to browser: BrowserReference,
        kind: HandlerOperationKind,
        permitsBrowserChange: Bool,
        configurationOnSuccess: RoutingConfiguration? = nil
    ) async -> HandlerTransactionOutcome {
        let recovery = await recoverPendingOperation()
        if case .degraded(let issue) = recovery {
            return .degraded(issue)
        }

        let baseline = systemHandler.currentHandlers()
        guard (permitsBrowserChange || browser != browserChange),
              let applicationURL = systemHandler.applicationURL(for: browser)
        else {
            return .failed(.targetUnavailable)
        }

        let desiredApplication = HandlerApplication(
            browser: browser,
            applicationURL: applicationURL
        )
        let desired = HTTPHandlerSnapshot.same(desiredApplication)
        if let scheme = missingRestoreScheme(
            current: baseline,
            desired: desired
        ) {
            return .failed(.missingBaseline(scheme))
        }
        let operationID = makeOperationID()
        let receipt = HandlerUndoReceipt(
            operationID: operationID,
            issuedAt: now(),
            precondition: desired,
            restore: baseline
        )
        var operation = PendingHandlerOperation(
            id: operationID,
            startedAt: now(),
            kind: kind,
            desiredHandlers: desired,
            undoReceipt: receipt,
            configurationBefore: configurationOnSuccess == nil
                ? nil
                : (try? repository.loadConfiguration()),
            configurationOnSuccess: configurationOnSuccess
        )

        do {
            if configurationOnSuccess != nil,
               operation.configurationBefore == nil {
                return .failed(.statePersistenceFailed)
            }
            var journal = try loadJournal()
            journal.pendingOperation = operation
            try repository.saveHandlerJournal(journal)
            return await execute(operation: &operation, journal: &journal)
        } catch {
            return .failed(.statePersistenceFailed)
        }
    }

    func undo() async -> HandlerTransactionOutcome {
        let recovery = await recoverPendingOperation()
        if case .degraded(let issue) = recovery {
            return .degraded(issue)
        }

        do {
            var journal = try loadJournal()
            guard let receipt = journal.undoReceipt else {
                return .refused(.noUndoReceipt)
            }

            let live = systemHandler.currentHandlers()
            guard snapshotsMatch(live, receipt.precondition) else {
                journal.undoReceipt = nil
                try repository.saveHandlerJournal(journal)
                return .refused(.undoPreconditionFailed)
            }

            for scheme in Self.schemeOrder
            where !applicationsMatch(live[scheme], receipt.restore[scheme]) {
                guard let restore = receipt.restore[scheme] else {
                    return .failed(.missingBaseline(scheme))
                }
                guard systemHandler.applicationURL(for: restore.browser) != nil else {
                    return .failed(.targetUnavailable)
                }
            }

            let operationID = makeOperationID()
            let rollbackReceipt = HandlerUndoReceipt(
                operationID: operationID,
                issuedAt: now(),
                precondition: receipt.restore,
                restore: live
            )
            var operation = PendingHandlerOperation(
                id: operationID,
                startedAt: now(),
                kind: .undo,
                desiredHandlers: receipt.restore,
                undoReceipt: rollbackReceipt
            )
            journal.pendingOperation = operation
            try repository.saveHandlerJournal(journal)
            return await execute(operation: &operation, journal: &journal)
        } catch {
            return .degraded(.statePersistenceFailed)
        }
    }

    func recoverPendingOperation() async -> HandlerRecoveryOutcome {
        do {
            var journal = try loadJournal()
            guard let operation = journal.pendingOperation else {
                return .nothingPending
            }

            if snapshotsMatch(
                systemHandler.currentHandlers(),
                operation.desiredHandlers
            ) {
                try complete(operation: operation, journal: &journal)
                return operation.kind == .undo
                    ? .completedUndo
                    : .completedSwitch
            }

            switch await reconcile(operation: operation, journal: &journal) {
            case .restored:
                return .rolledBack
            case .externalChange:
                return .degraded(.handlersChangedExternally)
            case .failed:
                return .degraded(.rollbackFailed)
            }
        } catch {
            return .degraded(.statePersistenceFailed)
        }
    }

    func canUndo(currentHandlers: HTTPHandlerSnapshot) -> Bool {
        guard let journal = try? loadJournal(),
              journal.pendingOperation == nil,
              let receipt = journal.undoReceipt
        else {
            return false
        }
        return snapshotsMatch(currentHandlers, receipt.precondition)
    }

    private func execute(
        operation: inout PendingHandlerOperation,
        journal: inout HandlerOperationJournal
    ) async -> HandlerTransactionOutcome {
        for scheme in Self.schemeOrder {
            let liveApplication = systemHandler.currentHandlers()[scheme]
            let desiredApplication = operation.desiredHandlers[scheme]
            if applicationsMatch(liveApplication, desiredApplication) {
                continue
            }

            guard applicationsMatch(
                liveApplication,
                operation.undoReceipt.restore[scheme]
            ) else {
                return await fail(
                    .handlersChangedExternally,
                    operation: operation,
                    journal: &journal
                )
            }
            guard let desiredApplication else {
                return await fail(
                    .handlerChangeFailed,
                    operation: operation,
                    journal: &journal
                )
            }

            operation.inFlightScheme = scheme
            journal.pendingOperation = operation
            do {
                try repository.saveHandlerJournal(journal)
            } catch {
                return await fail(
                    .statePersistenceFailed,
                    operation: operation,
                    journal: &journal
                )
            }

            do {
                try await systemHandler.setDefaultHandler(
                    desiredApplication.browser,
                    for: scheme
                )
            } catch {
                if applicationsMatch(
                    systemHandler.currentHandlers()[scheme],
                    desiredApplication
                ) {
                    if !operation.completedSchemes.contains(scheme) {
                        operation.completedSchemes.append(scheme)
                    }
                    operation.inFlightScheme = nil
                    journal.pendingOperation = operation
                    do {
                        try repository.saveHandlerJournal(journal)
                    } catch {
                        return await fail(
                            .statePersistenceFailed,
                            operation: operation,
                            journal: &journal
                        )
                    }
                }
                return await fail(
                    .handlerChangeFailed,
                    cancellation: isCancellation(error),
                    operation: operation,
                    journal: &journal
                )
            }

            if !operation.completedSchemes.contains(scheme) {
                operation.completedSchemes.append(scheme)
            }
            operation.inFlightScheme = nil
            journal.pendingOperation = operation
            do {
                try repository.saveHandlerJournal(journal)
            } catch {
                return await fail(
                    .statePersistenceFailed,
                    operation: operation,
                    journal: &journal
                )
            }
        }

        guard snapshotsMatch(
            systemHandler.currentHandlers(),
            operation.desiredHandlers
        ) else {
            return await fail(
                .verificationFailed,
                operation: operation,
                journal: &journal
            )
        }

        do {
            try complete(operation: operation, journal: &journal)
            return .succeeded
        } catch {
            return .degraded(.statePersistenceFailed)
        }
    }

    private func fail(
        _ issue: HandlerTransactionIssue,
        cancellation: Bool = false,
        operation: PendingHandlerOperation,
        journal: inout HandlerOperationJournal
    ) async -> HandlerTransactionOutcome {
        switch await reconcile(operation: operation, journal: &journal) {
        case .restored:
            return cancellation ? .cancelled : .failed(issue)
        case .externalChange:
            return .degraded(.handlersChangedExternally)
        case .failed:
            return .degraded(.rollbackFailed)
        }
    }

    private func reconcile(
        operation: PendingHandlerOperation,
        journal: inout HandlerOperationJournal
    ) async -> ReconciliationResult {
        var sawExternalChange = false
        var restoreFailed = false
        var ownedSchemes = operation.completedSchemes
        if let inFlightScheme = operation.inFlightScheme,
           !ownedSchemes.contains(inFlightScheme) {
            ownedSchemes.append(inFlightScheme)
        }

        for scheme in ownedSchemes.reversed() {
            let liveApplication = systemHandler.currentHandlers()[scheme]
            let desiredApplication = operation.desiredHandlers[scheme]
            let restoreApplication = operation.undoReceipt.restore[scheme]

            if applicationsMatch(liveApplication, restoreApplication) {
                continue
            }
            guard applicationsMatch(liveApplication, desiredApplication) else {
                sawExternalChange = true
                continue
            }
            guard let restoreApplication else {
                restoreFailed = true
                continue
            }

            do {
                try await systemHandler.setDefaultHandler(
                    restoreApplication.browser,
                    for: scheme
                )
            } catch {
                restoreFailed = true
                continue
            }

            if !applicationsMatch(
                systemHandler.currentHandlers()[scheme],
                restoreApplication
            ) {
                restoreFailed = true
            }
        }

        guard !restoreFailed else {
            return .failed
        }

        do {
            if let configuration = operation.configurationBefore {
                try repository.saveConfiguration(configuration)
            }
            journal.pendingOperation = nil
            try repository.saveHandlerJournal(journal)
        } catch {
            return .failed
        }
        return sawExternalChange ? .externalChange : .restored
    }

    private func complete(
        operation: PendingHandlerOperation,
        journal: inout HandlerOperationJournal
    ) throws {
        if let configuration = operation.configurationOnSuccess {
            try repository.saveConfigurationSnapshot(
                configuration,
                snapshotID: operation.id,
                recordedAt: operation.startedAt
            )
        }
        journal.pendingOperation = nil
        switch operation.kind {
        case .direct:
            journal.undoReceipt = operation.undoReceipt
        case .undo, .smartActivation, .smartDeactivation:
            journal.undoReceipt = nil
        }
        try repository.saveHandlerJournal(journal)
    }

    private func loadJournal() throws -> HandlerOperationJournal {
        var journal = try repository.loadHandlerJournal()
        journal.schemaVersion = HandlerOperationJournal.currentSchemaVersion
        return journal
    }

    private func snapshotsMatch(
        _ lhs: HTTPHandlerSnapshot,
        _ rhs: HTTPHandlerSnapshot
    ) -> Bool {
        WebScheme.allCases.allSatisfy {
            applicationsMatch(lhs[$0], rhs[$0])
        }
    }

    private func applicationsMatch(
        _ lhs: HandlerApplication?,
        _ rhs: HandlerApplication?
    ) -> Bool {
        lhs?.browser == rhs?.browser
    }

    private func missingRestoreScheme(
        current: HTTPHandlerSnapshot,
        desired: HTTPHandlerSnapshot
    ) -> WebScheme? {
        Self.schemeOrder.first { scheme in
            !applicationsMatch(current[scheme], desired[scheme])
                && current[scheme] == nil
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSUserCancelledError
    }
}
