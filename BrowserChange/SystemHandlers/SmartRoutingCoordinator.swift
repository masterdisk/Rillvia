import Foundation

enum SmartRoutingIssue: Equatable, Sendable {
    case missingFallback
    case selfFallback
    case fallbackUnavailable
    case smartRoutingNotEnabled
    case smartRoutingAlreadyEnabled
    case transitionCancelled
    case configurationPersistenceFailed
    case handlerTransaction(HandlerTransactionIssue)
}

enum SmartRoutingStatus: Equatable, Sendable {
    case direct
    case active(BrowserReference)
    case suspended(BrowserReference)
    case degraded(SmartRoutingIssue)
}

enum SmartRoutingTransitionOutcome: Equatable, Sendable {
    case succeeded
    case failed(SmartRoutingIssue)
    case degraded(SmartRoutingIssue)
}

@MainActor
final class SmartRoutingCoordinator {
    private let systemHandler: any SystemBrowserHandling
    private let repository: StateRepository
    private let transactionCoordinator: HandlerTransactionCoordinator
    private let browserChange: BrowserReference

    private(set) var configuration: RoutingConfiguration = .fresh
    private(set) var status: SmartRoutingStatus = .direct
    private(set) var lastRecoveryOutcome: HandlerRecoveryOutcome =
        .nothingPending

    init(
        systemHandler: any SystemBrowserHandling,
        repository: StateRepository,
        transactionCoordinator: HandlerTransactionCoordinator,
        browserChange: BrowserReference
    ) {
        self.systemHandler = systemHandler
        self.repository = repository
        self.transactionCoordinator = transactionCoordinator
        self.browserChange = browserChange
    }

    @discardableResult
    func reconcile() async -> SmartRoutingStatus {
        let recovery = await transactionCoordinator.recoverPendingOperation()
        lastRecoveryOutcome = recovery
        do {
            configuration = try repository.loadConfiguration()
        } catch {
            status = .degraded(.configurationPersistenceFailed)
            return status
        }

        if case .degraded(let issue) = recovery {
            status = .degraded(.handlerTransaction(issue))
            return status
        }

        status = reconciledStatus()
        return status
    }

    func enable(
        fallback explicitFallback: BrowserReference? = nil
    ) async -> SmartRoutingTransitionOutcome {
        let currentStatus = await reconcile()
        if case .degraded(let issue) = currentStatus {
            return .degraded(issue)
        }
        guard configuration.mode == .direct else {
            return .failed(.smartRoutingAlreadyEnabled)
        }

        let agreedExternal = systemHandler.currentHandlers()
            .health(browserChange: browserChange)
            .agreedExternalBrowser
        guard let fallback = explicitFallback
            ?? agreedExternal
            ?? configuration.fallbackBrowser else {
            return .failed(.missingFallback)
        }
        guard fallback != browserChange else {
            return .failed(.selfFallback)
        }
        guard systemHandler.applicationURL(for: fallback) != nil else {
            return .failed(.fallbackUnavailable)
        }

        var desiredConfiguration = configuration
        desiredConfiguration.schemaVersion =
            RoutingConfiguration.currentSchemaVersion
        desiredConfiguration.mode = .smart
        desiredConfiguration.fallbackBrowser = fallback

        let outcome = await transactionCoordinator.activateSmartRouting(
            configuration: desiredConfiguration
        )
        return finish(outcome)
    }

    func disable() async -> SmartRoutingTransitionOutcome {
        let currentStatus = await reconcile()
        if case .degraded(let issue) = currentStatus {
            return .degraded(issue)
        }
        guard configuration.mode == .smart else {
            return .failed(.smartRoutingNotEnabled)
        }
        guard let fallback = configuration.fallbackBrowser else {
            return .failed(.missingFallback)
        }
        guard fallback != browserChange else {
            return .failed(.selfFallback)
        }
        guard systemHandler.applicationURL(for: fallback) != nil else {
            return .failed(.fallbackUnavailable)
        }

        var desiredConfiguration = configuration
        desiredConfiguration.schemaVersion =
            RoutingConfiguration.currentSchemaVersion
        desiredConfiguration.mode = .direct

        let outcome = await transactionCoordinator.deactivateSmartRouting(
            to: fallback,
            configuration: desiredConfiguration
        )
        return finish(outcome)
    }

    func changeFallback(
        to fallback: BrowserReference
    ) -> SmartRoutingTransitionOutcome {
        guard configuration.mode == .smart else {
            return .failed(.smartRoutingNotEnabled)
        }
        guard fallback != browserChange else {
            return .failed(.selfFallback)
        }
        guard systemHandler.applicationURL(for: fallback) != nil else {
            return .failed(.fallbackUnavailable)
        }

        var desiredConfiguration = configuration
        desiredConfiguration.schemaVersion =
            RoutingConfiguration.currentSchemaVersion
        desiredConfiguration.fallbackBrowser = fallback
        do {
            try repository.saveConfigurationSnapshot(desiredConfiguration)
            configuration = desiredConfiguration
            status = reconciledStatus()
            return .succeeded
        } catch {
            status = .degraded(.configurationPersistenceFailed)
            return .degraded(.configurationPersistenceFailed)
        }
    }

    func applyConfiguration(
        _ desiredConfiguration: RoutingConfiguration,
        recordingSnapshot: Bool = true
    ) -> SmartRoutingTransitionOutcome {
        var desiredConfiguration = desiredConfiguration
        desiredConfiguration.schemaVersion =
            RoutingConfiguration.currentSchemaVersion
        do {
            if recordingSnapshot {
                try repository.saveConfigurationSnapshot(
                    desiredConfiguration
                )
            } else {
                try repository.saveConfiguration(desiredConfiguration)
            }
            configuration = desiredConfiguration
            status = reconciledStatus()
            return .succeeded
        } catch {
            status = .degraded(.configurationPersistenceFailed)
            return .degraded(.configurationPersistenceFailed)
        }
    }

    @discardableResult
    func refreshOwnership() -> SmartRoutingStatus {
        status = reconciledStatus()
        return status
    }

    private func finish(
        _ outcome: HandlerTransactionOutcome
    ) -> SmartRoutingTransitionOutcome {
        switch outcome {
        case .succeeded:
            reloadConfigurationAndStatus()
            return .succeeded
        case .cancelled:
            reloadConfigurationAndStatus()
            return .failed(.transitionCancelled)
        case .failed(let issue), .refused(let issue):
            reloadConfigurationAndStatus()
            return .failed(.handlerTransaction(issue))
        case .degraded(let issue):
            reloadConfigurationAndStatus()
            let smartIssue = SmartRoutingIssue.handlerTransaction(issue)
            status = .degraded(smartIssue)
            return .degraded(smartIssue)
        }
    }

    private func reloadConfigurationAndStatus() {
        do {
            configuration = try repository.loadConfiguration()
            status = reconciledStatus()
        } catch {
            status = .degraded(.configurationPersistenceFailed)
        }
    }

    private func reconciledStatus() -> SmartRoutingStatus {
        guard configuration.mode == .smart else {
            return .direct
        }
        guard let fallback = configuration.fallbackBrowser else {
            return .degraded(.missingFallback)
        }
        guard fallback != browserChange else {
            return .degraded(.selfFallback)
        }
        guard systemHandler.applicationURL(for: fallback) != nil else {
            return .degraded(.fallbackUnavailable)
        }

        let ownership = systemHandler.currentHandlers()
            .ownership(browserChange: browserChange)
        if ownership == .browserChange {
            return .active(fallback)
        }
        return .suspended(fallback)
    }
}
