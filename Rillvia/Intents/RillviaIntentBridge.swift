import Foundation

struct AutomationBrowser: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}

struct AutomationRoutingProfile: Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
}

enum RillviaAutomationError: Error, Equatable, Sendable {
    case unsupportedURL
    case smartRoutingUnavailable
    case selfTarget
    case browserUnavailable
    case profileUnavailable
    case automationLeasePermissionDisabled
    case handlerTransitionInProgress
    case noUndoAvailable
    case duplicateDispatch
    case launchFailed
    case restoreFailed
    case persistenceFailed
}

extension RillviaAutomationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            "Rillvia can open only HTTP and HTTPS links."
        case .smartRoutingUnavailable:
            "Rillvia is not sending links."
        case .selfTarget:
            "Rillvia cannot open a link in itself."
        case .browserUnavailable:
            "The selected browser is not installed."
        case .profileUnavailable:
            "That rule set is no longer available."
        case .automationLeasePermissionDisabled:
            "Shortcuts are not allowed to switch browsers."
        case .handlerTransitionInProgress:
            "Rillvia is still changing how links open."
        case .noUndoAvailable:
            "There is no previous browser change to restore."
        case .duplicateDispatch:
            "Rillvia stopped a repeated link."
        case .launchFailed:
            "The selected browser could not open the link."
        case .restoreFailed:
            "Rillvia could not restore the previous browser."
        case .persistenceFailed:
            "Rillvia could not save this."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedURL:
            "Choose a link that starts with http:// or https://."
        case .smartRoutingUnavailable:
            "Open Rillvia and turn on rules."
        case .selfTarget:
            "Choose an installed browser."
        case .browserUnavailable:
            "Reinstall the browser or choose another installed browser."
        case .profileUnavailable:
            "Choose an enabled rule set that still exists."
        case .automationLeasePermissionDisabled:
            "Turn on “Allow temporary switches” in Rillvia Settings first."
        case .handlerTransitionInProgress:
            "Wait for the current change to finish, then try again."
        case .noUndoAvailable:
            "Switch browsers for a while, or change the usual browser, before running this shortcut."
        case .duplicateDispatch:
            "Wait a moment, then run the shortcut again if needed."
        case .launchFailed:
            "Reinstall the browser or choose another browser."
        case .restoreFailed:
            "Open Rillvia and check which browser opens links."
        case .persistenceFailed:
            "Reopen Rillvia and try again."
        }
    }
}

@MainActor
final class RillviaIntentBridge: @unchecked Sendable {
    private let browserCatalog: any BrowserCatalog
    private let systemHandler: any SystemBrowserHandling
    private let repository: StateRepository
    private let rillvia: BrowserReference
    private let transactionCoordinator: HandlerTransactionCoordinator
    private let smartRoutingCoordinator: SmartRoutingCoordinator
    private let browserLeaseCoordinator: BrowserLeaseCoordinator
    private let routingCoordinator: RoutingCoordinator
    private let configurationEditor: RoutingConfigurationEditor

    var onStateChanged: (@MainActor () -> Void)?

    init(
        browserCatalog: any BrowserCatalog,
        systemHandler: any SystemBrowserHandling,
        repository: StateRepository,
        rillvia: BrowserReference,
        transactionCoordinator: HandlerTransactionCoordinator,
        smartRoutingCoordinator: SmartRoutingCoordinator,
        browserLeaseCoordinator: BrowserLeaseCoordinator,
        routingCoordinator: RoutingCoordinator,
        configurationEditor: RoutingConfigurationEditor
    ) {
        self.browserCatalog = browserCatalog
        self.systemHandler = systemHandler
        self.repository = repository
        self.rillvia = rillvia
        self.transactionCoordinator = transactionCoordinator
        self.smartRoutingCoordinator = smartRoutingCoordinator
        self.browserLeaseCoordinator = browserLeaseCoordinator
        self.routingCoordinator = routingCoordinator
        self.configurationEditor = configurationEditor
    }

    func availableBrowsers() throws -> [AutomationBrowser] {
        var seen = Set<String>()
        return browserCatalog.installedBrowsers()
            .filter { browser in
                browser.reference != rillvia
                    && !browser.isImaginary
                    && systemHandler.applicationURL(
                        for: browser.reference
                    ) != nil
                    && seen.insert(browser.id).inserted
            }
            .map {
                AutomationBrowser(id: $0.id, name: $0.name)
            }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                if order == .orderedSame {
                    return $0.id < $1.id
                }
                return order == .orderedAscending
            }
    }

    func availableProfiles() throws -> [AutomationRoutingProfile] {
        try repository.loadConfiguration().profiles
            .filter(\.isEnabled)
            .map {
                AutomationRoutingProfile(id: $0.id, name: $0.name)
            }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                if order == .orderedSame {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return order == .orderedAscending
            }
    }

    func openLink(
        _ url: URL,
        browserID: String?
    ) async throws -> String {
        let target: BrowserReference?
        if let browserID {
            guard !AppIdentity.isSelf(BrowserReference(bundleIdentifier: browserID), reference: rillvia) else {
                throw RillviaAutomationError.selfTarget
            }
            guard try availableBrowsers().contains(
                where: { $0.id == browserID }
            ) else {
                throw RillviaAutomationError.browserUnavailable
            }
            target = BrowserReference(bundleIdentifier: browserID)
        } else {
            let isVerified: Bool
            do {
                isVerified = try smartRoutingCoordinator
                    .isVerifiedSmartRoutingActive()
            } catch {
                throw RillviaAutomationError.persistenceFailed
            }
            guard isVerified else {
                throw RillviaAutomationError
                    .smartRoutingUnavailable
            }
            _ = browserLeaseCoordinator.reconcile(
                availableTargets: try availableBrowserReferences()
            )
            onStateChanged?()
            target = nil
        }

        let outcome = await routingCoordinator.route(
            url,
            configuration: try repository.loadConfiguration(),
            explicitTarget: target,
            availableTargets: try availableBrowserReferences()
        )
        switch outcome {
        case .opened(let browser):
            return "Opened the link in \(name(for: browser))."
        case .rejected(.unsupportedURL):
            throw RillviaAutomationError.unsupportedURL
        case .rejected(.selfTarget):
            throw RillviaAutomationError.selfTarget
        case .rejected(.explicitTargetUnavailable),
                .blocked(.explicitTargetUnavailable):
            throw RillviaAutomationError.browserUnavailable
        case .rejected(.duplicateDispatch):
            throw RillviaAutomationError.duplicateDispatch
        case .rejected(.smartRoutingUnavailable),
                .blocked(.smartRoutingUnavailable),
                .blocked(.missingFallback):
            throw RillviaAutomationError.smartRoutingUnavailable
        case .rejected(.missingFallback),
                .rejected(.launchFailed),
                .blocked(.launchFailed),
                .blocked(.unsupportedURL),
                .blocked(.selfTarget),
                .blocked(.duplicateDispatch):
            throw RillviaAutomationError.launchFailed
        }
    }

    func setRoutingProfile(_ profileID: UUID) throws -> String {
        var configuration: RoutingConfiguration
        do {
            configuration = try repository.loadConfiguration()
        } catch {
            throw RillviaAutomationError.persistenceFailed
        }
        guard let profile = configuration.profiles.first(
            where: { $0.id == profileID && $0.isEnabled }
        ) else {
            throw RillviaAutomationError.profileUnavailable
        }

        do {
            try configurationEditor.selectProfile(
                profileID,
                in: &configuration
            )
        } catch {
            throw RillviaAutomationError.profileUnavailable
        }
        switch smartRoutingCoordinator.applyConfiguration(configuration) {
        case .succeeded:
            onStateChanged?()
            return "Using the \(profile.name) rule set."
        case .failed(let issue), .degraded(let issue):
            throw automationError(for: issue)
        }
    }

    func setAutomationLeasesAllowed(
        _ isAllowed: Bool
    ) throws -> String {
        var configuration: RoutingConfiguration
        do {
            configuration = try repository.loadConfiguration()
        } catch {
            throw RillviaAutomationError.persistenceFailed
        }
        if let issue = smartRoutingCoordinator.configurationMutationIssue() {
            throw automationError(for: issue)
        }
        if configuration.allowAutomationLeases == isAllowed {
            return isAllowed
                ? "Shortcuts can switch browsers."
                : "Shortcuts cannot switch browsers."
        }

        configuration.allowAutomationLeases = isAllowed
        switch smartRoutingCoordinator.applyConfiguration(configuration) {
        case .succeeded:
            onStateChanged?()
            return isAllowed
                ? "Shortcuts can now switch browsers."
                : "Shortcuts can no longer switch browsers."
        case .failed(let issue), .degraded(let issue):
            throw automationError(for: issue)
        }
    }

    func startBrowserLease(
        browserID: String,
        preset: BrowserLeasePreset
    ) throws -> String {
        let configuration: RoutingConfiguration
        do {
            configuration = try repository.loadConfiguration()
        } catch {
            throw RillviaAutomationError.persistenceFailed
        }
        guard configuration.allowAutomationLeases else {
            throw RillviaAutomationError
                .automationLeasePermissionDisabled
        }
        guard !AppIdentity.isSelf(BrowserReference(bundleIdentifier: browserID), reference: rillvia) else {
            throw RillviaAutomationError.selfTarget
        }
        guard let browser = try availableBrowsers().first(
            where: { $0.id == browserID }
        ) else {
            throw RillviaAutomationError.browserUnavailable
        }

        defer { onStateChanged?() }
        switch browserLeaseCoordinator.startLease(
            to: BrowserReference(bundleIdentifier: browserID),
            preset: preset,
            availableTargets: try availableBrowserReferences()
        ) {
        case .succeeded:
            if preset == .untilEnded {
                return "Using \(browser.name) until you stop."
            }
            return "Using \(browser.name) for \(preset.title.lowercased())."
        case .failed(let issue):
            throw automationError(for: issue)
        }
    }

    func endBrowserLease() throws -> String {
        defer { onStateChanged?() }
        switch browserLeaseCoordinator.endLease() {
        case .succeeded:
            return "Stopped the temporary browser."
        case .failed(.noActiveLease):
            return "No temporary browser is on."
        case .failed(let issue):
            throw automationError(for: issue)
        }
    }

    func restorePreviousBrowser() async throws -> String {
        defer { onStateChanged?() }
        let reconciliation = browserLeaseCoordinator.reconcile(
            availableTargets: try availableBrowserReferences()
        )
        if let issue = reconciliation.issue,
           issue == .configurationPersistenceFailed {
            throw RillviaAutomationError.persistenceFailed
        }

        if browserLeaseCoordinator.canUndo {
            // Bringing a temporary browser back is a temporary switch, so it needs the same permission.
            if browserLeaseCoordinator.undoRestoresLease,
               (try? repository.loadConfiguration().allowAutomationLeases) != true {
                throw RillviaAutomationError.automationLeasePermissionDisabled
            }
            switch browserLeaseCoordinator.undo() {
            case .succeeded:
                let restored = try repository.loadConfiguration()
                    .browserLease
                if let restored {
                    return "Using \(name(for: restored.browser)) again."
                }
                return "Restored the previous temporary browser."
            case .failed(let issue):
                throw automationError(for: issue)
            }
        }

        let handlers = systemHandler.currentHandlers()
        guard transactionCoordinator.canUndo(
            currentHandlers: handlers
        ) else {
            throw RillviaAutomationError.noUndoAvailable
        }

        switch await transactionCoordinator.undo() {
        case .succeeded:
            return "Restored the previous web-link handlers."
        case .refused(.noUndoReceipt),
                .refused(.undoPreconditionFailed):
            throw RillviaAutomationError.noUndoAvailable
        case .failed(.statePersistenceFailed),
                .degraded(.statePersistenceFailed):
            throw RillviaAutomationError.persistenceFailed
        case .cancelled, .failed, .degraded, .refused:
            throw RillviaAutomationError.restoreFailed
        }
    }

    private func automationError(
        for issue: BrowserLeaseIssue
    ) -> RillviaAutomationError {
        switch issue {
        case .smartRoutingUnavailable:
            .smartRoutingUnavailable
        case .selfTarget:
            .selfTarget
        case .targetUnavailable:
            .browserUnavailable
        case .noActiveLease, .noUndoReceipt, .undoPreconditionFailed:
            .noUndoAvailable
        case .configurationPersistenceFailed:
            .persistenceFailed
        case .handlerTransitionInProgress:
            .handlerTransitionInProgress
        }
    }

    private func automationError(
        for issue: SmartRoutingIssue
    ) -> RillviaAutomationError {
        switch issue {
        case .handlerTransitionInProgress:
            .handlerTransitionInProgress
        case .configurationPersistenceFailed:
            .persistenceFailed
        case .missingFallback, .selfFallback, .fallbackUnavailable,
                .smartRoutingNotEnabled, .smartRoutingAlreadyEnabled,
                .transitionCancelled, .handlerTransaction:
            .persistenceFailed
        }
    }

    private func availableBrowserReferences() throws
        -> Set<BrowserReference> {
        Set(
            try availableBrowsers().map {
                BrowserReference(bundleIdentifier: $0.id)
            }
        )
    }

    private func name(for reference: BrowserReference) -> String {
        browserCatalog.installedBrowsers().first {
            $0.reference == reference
        }?.name ?? reference.bundleIdentifier
    }
}
