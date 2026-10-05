import AppKit
import Foundation
import Observation

enum BrowserRoutingState: Equatable, Sendable {
    case direct
    case enabling(BrowserReference)
    case smartActive(BrowserReference)
    case smartSuspended(BrowserReference)
    case disabling(BrowserReference)
    case degraded(SmartRoutingIssue)
}

@MainActor
@Observable
final class BrowserStore {
    var selectedID: String?
    var selectedRouteID: String?
    var selectedProfileID: String?
    var showHall = false

    private(set) var browsers: [InstalledBrowser] = []
    private(set) var switchable: [InstalledBrowser] = []
    private(set) var defaultBundleID: String?
    private(set) var message: String?
    private(set) var canUndo = false
    private(set) var transactionStatus: HandlerTransactionStatus = .idle
    private(set) var handlerHealth: HTTPHandlerHealth
    private(set) var routingState: BrowserRoutingState = .direct
    private(set) var revision = 0
    private(set) var installedCount = 0
    private(set) var board = PreviewBoard.empty
    @ObservationIgnored
    var onRoutingAvailabilityChanged: (@MainActor () -> Void)?

    private var installed: [InstalledBrowser] = []
    private var icons: [String: NSImage] = [:]
    private var lynxVisible = false
    private var quipIndex = 0
    private var titleGate = TapGate(threshold: 5, interval: 1.5)
    private var moonGate = TapGate(threshold: 4, interval: 2)
    private var lynxKeys = CharacterSequence(target: "lynx", gap: 1.2)
    private let environment: AppEnvironment
    private let browserChange: BrowserReference
    private let transactionCoordinator: HandlerTransactionCoordinator
    private let smartRoutingCoordinator: SmartRoutingCoordinator
    private let routingCoordinator: RoutingCoordinator

    private let quips: [(String) -> String] = [
        { "\($0) is already the default. The others can wait." },
        { _ in "Still this one. Consistency is a feature." },
        { _ in "macOS agrees with you." },
        { _ in "No change. A peaceful outcome." },
    ]

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        let browserChange = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? "com.browserchange.BrowserChange"
        )
        self.browserChange = browserChange
        let transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            browserChange: browserChange
        )
        self.transactionCoordinator = transactionCoordinator
        self.smartRoutingCoordinator = SmartRoutingCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            transactionCoordinator: transactionCoordinator,
            browserChange: browserChange
        )
        self.routingCoordinator = RoutingCoordinator(
            launcher: environment.urlLauncher,
            browserChange: browserChange
        )
        self.handlerHealth = HTTPHandlerSnapshot.missing.health(
            browserChange: browserChange
        )
        reload()
    }

    var isSwitching: Bool {
        transactionStatus.isBusy
    }

    var isSmartRoutingConfigured: Bool {
        smartRoutingCoordinator.configuration.mode == .smart
    }

    var routingModeTitle: String {
        switch routingState {
        case .direct:
            "Direct"
        case .enabling:
            "Turning on Smart Routing"
        case .smartActive:
            "Smart Routing"
        case .smartSuspended:
            "Smart Routing suspended"
        case .disabling:
            "Turning off Smart Routing"
        case .degraded:
            "Routing needs attention"
        }
    }

    var routingModeDetail: String {
        switch routingState {
        case .direct:
            "Links open directly in the current system default browser."
        case .enabling(let fallback):
            "Waiting for macOS to make BrowserChange the web-link handler. \(name(for: fallback)) will remain the external fallback."
        case .smartActive(let fallback):
            "BrowserChange forwards web links immediately to \(name(for: fallback))."
        case .smartSuspended(let fallback):
            "The web-link handlers changed outside BrowserChange. Smart Routing will not reclaim them; \(name(for: fallback)) remains configured as the fallback."
        case .disabling(let fallback):
            "Waiting for macOS to make \(name(for: fallback)) the Direct default."
        case .degraded(let issue):
            smartRoutingMessage(for: issue)
        }
    }

    var smartFallbackBrowser: InstalledBrowser? {
        guard let fallback = smartRoutingCoordinator
            .configuration.fallbackBrowser else {
            return nil
        }
        return installed.first { $0.reference == fallback }
    }

    var hasSplitHandlers: Bool {
        handlerHealth.hasSplitHandlers
    }

    var defaultBrowserName: String {
        if hasSplitHandlers && !isSmartRoutingConfigured {
            return "Split web handlers"
        }
        return switchable.first { $0.id == defaultBundleID }?.name
            ?? "BrowserChange"
    }

    var selectedBrowserForRepair: InstalledBrowser? {
        guard let selectedID else { return nil }
        return installed.first { $0.id == selectedID && !$0.isImaginary }
    }

    var splitHandlerMessage: String? {
        guard case .split(let http, let https) = handlerHealth.ownership else {
            return nil
        }
        return "HTTPS links open in \(name(for: https)), while HTTP links open in \(name(for: http))."
    }

    var menuBarSource: NSImage {
        if let id = defaultBundleID, let icon = icons[id] {
            return icon
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "BrowserChange")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    func icon(for browser: InstalledBrowser) -> NSImage {
        if browser.isImaginary {
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: browser.name)
                ?? NSImage()
        }
        return icons[browser.id] ?? NSWorkspace.shared.icon(forFile: browser.iconURL.path)
    }

    func refresh() {
        guard !isSwitching else { return }
        reload()
    }

    func selectBrowser(_ id: String) {
        selectedID = id
    }

    func tapTitle(at date: Date = .now) {
        if titleGate.tap(at: date) {
            showHall = true
        }
    }

    func tapMoon(at date: Date = .now) {
        if moonGate.tap(at: date) {
            message = "The browsers logged off. You do not have to."
        }
    }

    func noteTyping(_ raw: String, at date: Date = .now) {
        guard lynxKeys.consume(raw, at: date) else { return }
        lynxVisible.toggle()
        message = lynxVisible
            ? "Lynx sat down at the end of the shelf."
            : "Lynx went back to the terminal."
        if !lynxVisible, selectedID == ImaginaryBrowser.lynx.id {
            selectedID = defaultBundleID ?? installed.first?.id
        }
        publish()
    }

    func copyIdentity(of browser: InstalledBrowser) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(browser.id, forType: .string)
        message = "Copied \(browser.id)"
    }

    func makeDefault(_ browser: InstalledBrowser) async {
        guard !isSwitching else { return }
        if browser.isImaginary {
            message = "Lynx lives in a terminal. This Mac wants a window."
            return
        }
        if isSmartRoutingConfigured {
            changeSmartFallback(to: browser)
            return
        }
        if !hasSplitHandlers, browser.id == defaultBundleID {
            message = quips[quipIndex % quips.count](browser.name)
            quipIndex += 1
            return
        }

        await performDirectSwitch(
            to: browser,
            successMessage: "\(browser.name) is now the default."
        )
    }

    func enableSmartRouting() async {
        guard !isSwitching else { return }
        guard !isSmartRoutingConfigured else {
            message = "Smart Routing is already configured."
            return
        }

        let fallback = handlerHealth.agreedExternalBrowser
            ?? smartRoutingCoordinator.configuration.fallbackBrowser
            ?? selectedBrowserForRepair?.reference
        guard let fallback else {
            message = smartRoutingMessage(for: .missingFallback)
            return
        }

        routingState = .enabling(fallback)
        transactionStatus = .switching
        message = "Waiting for macOS to confirm Smart Routing ownership."
        let outcome = await smartRoutingCoordinator.enable(
            fallback: fallback
        )
        reload()

        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = "Smart Routing is on with \(name(for: fallback)) as its fallback."
            onRoutingAvailabilityChanged?()
        case .failed(let issue):
            transactionStatus = .idle
            message = smartRoutingMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
        }
    }

    func disableSmartRouting() async {
        guard !isSwitching else { return }
        guard let fallback = smartRoutingCoordinator
            .configuration.fallbackBrowser else {
            message = smartRoutingMessage(for: .missingFallback)
            return
        }

        routingState = .disabling(fallback)
        transactionStatus = .switching
        message = "Turning Smart Routing off and restoring the Direct default."
        let outcome = await smartRoutingCoordinator.disable()
        reload()

        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = "Smart Routing is off. \(name(for: fallback)) is now the Direct default."
        case .failed(let issue):
            transactionStatus = .idle
            message = smartRoutingMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
        }
    }

    func routeIncomingURL(_ url: URL) async -> IncomingURLDisposition {
        reload()
        guard case .smartActive = routingState else {
            message = routingUnavailableMessage
            return .retryLater
        }

        let outcome = await routingCoordinator.route(
            url,
            configuration: smartRoutingCoordinator.configuration
        )
        switch outcome {
        case .opened:
            return .consumed
        case .rejected(.unsupportedURL):
            message = "BrowserChange only routes HTTP and HTTPS links."
            return .consumed
        case .rejected(.duplicateDispatch):
            message = "BrowserChange stopped a repeated link dispatch."
            return .consumed
        case .rejected(.selfTarget):
            message = smartRoutingMessage(for: .selfFallback)
            return .retryLater
        case .rejected:
            message = routingUnavailableMessage
            return .retryLater
        case .blocked(.launchFailed):
            let fallbackName = smartFallbackBrowser?.name
                ?? defaultBrowserName
            message = "\(fallbackName) could not open the link. Reinstall it or choose another Smart Routing fallback."
            return .retryLater
        case .blocked(.missingFallback):
            message = smartRoutingMessage(for: .missingFallback)
            return .retryLater
        case .blocked:
            message = routingUnavailableMessage
            return .retryLater
        }
    }

    func repairSelectedHandlers() async {
        guard !isSwitching else { return }
        guard !isSmartRoutingConfigured else {
            message = "Turn Smart Routing off before repairing Direct handlers."
            return
        }
        guard let browser = selectedBrowserForRepair else {
            message = "Choose an installed browser to repair both web-link handlers."
            return
        }
        await performDirectSwitch(
            to: browser,
            successMessage: "\(browser.name) now handles both HTTP and HTTPS links."
        )
    }

    func undoLastBrowserChange() async {
        guard !isSwitching else { return }
        transactionStatus = .undoing
        message = "Restoring the previous web-link handlers."

        let outcome = await transactionCoordinator.undo()
        reload()
        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = "Restored the previous web-link handlers."
        case .cancelled:
            transactionStatus = .idle
            message = "Left the default where it was."
        case .failed(let issue):
            transactionStatus = .idle
            message = transactionMessage(for: issue)
        case .refused(let issue):
            transactionStatus = .idle
            message = transactionMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            message = transactionMessage(for: issue)
        }
    }

    func activate() async {
        guard !isSwitching else { return }
        transactionStatus = .recovering
        let routingStatus = await smartRoutingCoordinator.reconcile()
        reload()

        if case .degraded(let issue) = routingStatus {
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
            return
        }

        switch smartRoutingCoordinator.lastRecoveryOutcome {
        case .nothingPending:
            transactionStatus = .idle
        case .completedSwitch:
            transactionStatus = .idle
            message = "Finished an interrupted browser change."
        case .completedUndo:
            transactionStatus = .idle
            message = "Finished restoring the previous web-link handlers."
        case .rolledBack:
            transactionStatus = .idle
            message = "Restored the previous web-link handlers after an interrupted change."
        case .degraded(let issue):
            transactionStatus = .degraded
            message = transactionMessage(for: issue)
        }
    }

    private func performDirectSwitch(
        to browser: InstalledBrowser,
        successMessage: String
    ) async {
        transactionStatus = .switching
        message = "Waiting for macOS to confirm both web-link handlers."

        let outcome = await transactionCoordinator.switchDirect(
            to: browser.reference
        )
        reload()
        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = successMessage
        case .cancelled:
            transactionStatus = .idle
            message = "Left the default where it was."
        case .failed(let issue), .refused(let issue):
            transactionStatus = .idle
            message = transactionMessage(for: issue, browserName: browser.name)
        case .degraded(let issue):
            transactionStatus = .degraded
            message = transactionMessage(for: issue, browserName: browser.name)
        }
    }

    private func changeSmartFallback(to browser: InstalledBrowser) {
        let outcome = smartRoutingCoordinator.changeFallback(
            to: browser.reference
        )
        reload()
        switch outcome {
        case .succeeded:
            message = "\(browser.name) is now the Smart Routing fallback."
            onRoutingAvailabilityChanged?()
        case .failed(let issue):
            message = smartRoutingMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
        }
    }

    private var routingUnavailableMessage: String {
        switch routingState {
        case .smartSuspended:
            "Smart Routing is suspended because the web-link handlers changed outside BrowserChange."
        case .degraded(let issue):
            smartRoutingMessage(for: issue)
        case .direct:
            "Smart Routing is off. Turn it on before routing links through BrowserChange."
        case .enabling, .disabling:
            "BrowserChange is still completing the routing mode change."
        case .smartActive:
            "Smart Routing is temporarily unavailable."
        }
    }

    private func smartRoutingMessage(
        for issue: SmartRoutingIssue
    ) -> String {
        switch issue {
        case .missingFallback:
            "Smart Routing needs an installed external fallback browser."
        case .selfFallback:
            "BrowserChange cannot be its own external fallback."
        case .fallbackUnavailable:
            "The Smart Routing fallback is not installed. Reinstall it or choose another browser."
        case .smartRoutingNotEnabled:
            "Smart Routing is not enabled."
        case .smartRoutingAlreadyEnabled:
            "Smart Routing is already configured."
        case .transitionCancelled:
            "The routing mode change was cancelled."
        case .configurationPersistenceFailed:
            "BrowserChange could not save its routing configuration. Reopen the app to recover safely."
        case .handlerTransaction(let issue):
            transactionMessage(for: issue)
        }
    }

    private func transactionMessage(
        for issue: HandlerTransactionIssue,
        browserName: String? = nil
    ) -> String {
        switch issue {
        case .targetUnavailable:
            if let browserName {
                return "\(browserName) is not available. Reinstall it or choose another browser."
            }
            return "The previous browser is not available, so BrowserChange could not restore it."
        case .missingBaseline(let scheme):
            let schemeName = scheme.rawValue.uppercased()
            return "BrowserChange cannot safely change the \(schemeName) handler because there is no current handler to restore. Set a default browser in System Settings, then try again."
        case .handlerChangeFailed:
            return "macOS did not change both web-link handlers. The previous handlers were restored."
        case .verificationFailed:
            return "macOS did not confirm both web-link handlers. The previous handlers were restored."
        case .handlersChangedExternally:
            return "The web-link handlers changed elsewhere. BrowserChange kept those changes; choose a browser and repair the handlers."
        case .rollbackFailed:
            return "BrowserChange could not safely restore both web-link handlers. Repair them before trying again."
        case .statePersistenceFailed:
            return "BrowserChange could not save the handler transaction. Reopen the app to recover it safely."
        case .noUndoReceipt:
            return "There is no browser change to undo."
        case .undoPreconditionFailed:
            return "Undo is no longer available because the web-link handlers changed elsewhere."
        }
    }

    private func reload() {
        installed = environment.browserCatalog.installedBrowsers()
        let handlers = environment.systemBrowserHandler.currentHandlers()
        handlerHealth = handlers.health(browserChange: browserChange)
        let smartStatus = smartRoutingCoordinator.refreshOwnership()
        switch smartStatus {
        case .direct:
            routingState = .direct
            defaultBundleID = handlerHealth
                .agreedExternalBrowser?.bundleIdentifier
        case .active(let fallback):
            routingState = .smartActive(fallback)
            defaultBundleID = fallback.bundleIdentifier
        case .suspended(let fallback):
            routingState = .smartSuspended(fallback)
            defaultBundleID = fallback.bundleIdentifier
        case .degraded(let issue):
            routingState = .degraded(issue)
            defaultBundleID = smartRoutingCoordinator
                .configuration.fallbackBrowser?.bundleIdentifier
                ?? handlerHealth.agreedExternalBrowser?.bundleIdentifier
        }
        canUndo = transactionCoordinator.canUndo(currentHandlers: handlers)
        publish()
    }

    private func name(for browser: BrowserReference) -> String {
        installed.first {
            $0.id == browser.bundleIdentifier
        }?.name ?? browser.bundleIdentifier
    }

    private func name(for application: HandlerApplication) -> String {
        name(for: application.browser)
    }

    private func publish(now: Date = .now) {
        installedCount = installed.count
        switchable = BrowserOrder.shelf(installed, defaultID: defaultBundleID)
        var display = installed
        if lynxVisible {
            display.append(ImaginaryBrowser.lynx)
        }
        let ordered = BrowserOrder.shelf(display, defaultID: defaultBundleID)
        browsers = ordered
        if let selectedID, ordered.contains(where: { $0.id == selectedID }) {
            self.selectedID = selectedID
        } else {
            selectedID = defaultBundleID ?? ordered.first?.id
        }

        let nextBoard = PreviewBoard.make(browsers: installed, defaultID: defaultBundleID, now: now)
        board = nextBoard
        if !nextBoard.routes.contains(where: { $0.id == selectedRouteID }) {
            selectedRouteID = nextBoard.routes.first?.id
        }
        if !nextBoard.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = nextBoard.profiles.first { $0.suggestedNow }?.id ?? nextBoard.profiles.first?.id
        }

        icons = Dictionary(uniqueKeysWithValues: installed.map { browser in
            (browser.id, NSWorkspace.shared.icon(forFile: browser.iconURL.path))
        })
        revision += 1
    }
}
