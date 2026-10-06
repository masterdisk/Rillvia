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

enum WorkspaceDestination: String, CaseIterable, Sendable {
    case direct
    case airlock
    case rules
    case profiles
}

@MainActor
@Observable
final class BrowserStore {
    var selectedID: String?
    var workspaceDestination: WorkspaceDestination = .direct
    var showHall = false
    var showDiagnostics = false
    var showTimeMachine = false

    private(set) var browsers: [InstalledBrowser] = []
    private(set) var switchable: [InstalledBrowser] = []
    private(set) var defaultBundleID: String?
    private(set) var message: String?
    private(set) var canUndo = false
    private(set) var transactionStatus: HandlerTransactionStatus = .idle
    private(set) var handlerHealth: HTTPHandlerHealth
    private(set) var routingState: BrowserRoutingState = .direct
    private(set) var activeBrowserLease: BrowserLease?
    private(set) var canUndoLease = false
    private(set) var allowsAutomationLeases = false
    private(set) var airlockResult = AirlockParseResult(
        items: [],
        rejectedCandidateCount: 0,
        wasTextTruncated: false,
        wasURLLimitReached: false
    )
    private(set) var revision = 0
    private(set) var installedCount = 0
    private(set) var timeMachineModel = PreviewTimeMachineModel(
        snapshots: []
    )
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
    private let browserLeaseCoordinator: BrowserLeaseCoordinator
    private let routingCoordinator: RoutingCoordinator
    private let configurationEditor: RoutingConfigurationEditor
    private let intentBridge: BrowserChangeIntentBridge

    private let quips: [(String) -> String] = [
        { "\($0) is already the default. The others can wait." },
        { _ in "Still this one. Consistency is a feature." },
        { _ in "macOS agrees with you." },
        { _ in "No change. A peaceful outcome." },
    ]

    convenience init() {
        self.init(environment: .live())
    }

    convenience init(environment: AppEnvironment) {
        self.init(services: BrowserChangeServices(environment: environment))
    }

    init(services: BrowserChangeServices) {
        self.environment = services.environment
        self.browserChange = services.browserChange
        self.transactionCoordinator = services.transactionCoordinator
        self.smartRoutingCoordinator = services.smartRoutingCoordinator
        let browserLeaseCoordinator = services.browserLeaseCoordinator
        self.browserLeaseCoordinator = browserLeaseCoordinator
        self.routingCoordinator = services.routingCoordinator
        self.configurationEditor = services.configurationEditor
        self.intentBridge = services.intentBridge
        self.handlerHealth = HTTPHandlerSnapshot.missing.health(
            browserChange: services.browserChange
        )
        browserLeaseCoordinator.onAutomaticExpiry = { [weak self] in
            guard let self else { return }
            self.reload()
            self.message = self.leaseEndedMessage
        }
        intentBridge.onStateChanged = { [weak self] in
            self?.reload()
        }
        reload()
    }

    var isSwitching: Bool {
        transactionStatus.isBusy
    }

    var isSmartRoutingConfigured: Bool {
        smartRoutingCoordinator.configuration.mode == .smart
    }

    var routingConfiguration: RoutingConfiguration {
        smartRoutingCoordinator.configuration
    }

    var externalBrowsers: [InstalledBrowser] {
        switchable.filter {
            !$0.isImaginary && $0.reference != browserChange
        }
    }

    var isSmartRoutingActive: Bool {
        if case .smartActive = routingState {
            return true
        }
        return false
    }

    var borrowableBrowsers: [InstalledBrowser] {
        isSmartRoutingActive ? externalBrowsers : []
    }

    var activeLeaseBrowser: InstalledBrowser? {
        guard let target = activeBrowserLease?.browser else {
            return nil
        }
        return installed.first { $0.reference == target }
    }

    var activeLeaseRemainingText: String? {
        guard let lease = activeBrowserLease else { return nil }
        return BrowserLeaseFormatting.remainingText(
            for: lease,
            at: environment.now()
        )
    }

    var diagnosticsSnapshot: DiagnosticsSnapshot {
        let info = Bundle.main.infoDictionary
        let appName = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "Linkpick"
        let appVersion = info?["CFBundleShortVersionString"] as? String
            ?? "Unknown"
        let buildVersion = info?["CFBundleVersion"] as? String
            ?? "Unknown"
        let versions = environment.stateRepository
            .inspectSchemaVersions()
        var configuration = routingConfiguration
        configuration.schemaVersion = versions.configuration
            ?? configuration.schemaVersion
        var journal = (try? environment.stateRepository
            .inspectHandlerJournal()) ?? .fresh
        journal.schemaVersion = versions.handlerJournal
            ?? journal.schemaVersion
        let historySchemaVersion = versions.configurationHistory
            ?? ConfigurationHistory.currentSchemaVersion
        return DiagnosticsSnapshot.make(
            appName: appName,
            appVersion: appVersion,
            buildVersion: buildVersion,
            browserChange: browserChange,
            handlers: environment.systemBrowserHandler.currentHandlers(),
            routingState: routingState,
            configuration: configuration,
            journal: journal,
            historySchemaVersion: historySchemaVersion,
            canUndo: canUndo || canUndoLease,
            installedBrowsers: installed,
            now: environment.now()
        )
    }

    var livingHallModel: LivingBrowserHallModel {
        LivingBrowserHallModel.make(
            installedBrowsers: installed,
            configuration: routingConfiguration,
            defaultBundleID: defaultBundleID,
            now: environment.now()
        )
    }

    var routingModeTitle: String {
        switch routingState {
        case .direct:
            "Usual browser"
        case .enabling:
            "Turning on link sending"
        case .smartActive:
            "Sending links"
        case .smartSuspended:
            "Link sending paused"
        case .disabling:
            "Turning off link sending"
        case .degraded:
            "Links need attention"
        }
    }

    var routingModeDetail: String {
        switch routingState {
        case .direct:
            "Links open in the usual browser."
        case .enabling(let fallback):
            "Waiting for macOS to let Linkpick open web links. \(name(for: fallback)) stays the browser used when no rule matches."
        case .smartActive(let fallback):
            "Links open in \(name(for: fallback)), unless a rule says otherwise."
        case .smartSuspended(let fallback):
            "macOS changed the web-link handler. Linkpick will not take it back. \(name(for: fallback)) is still the browser used when no rule matches."
        case .disabling(let fallback):
            "Waiting for macOS to make \(name(for: fallback)) the usual browser."
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
            return "HTTP and HTTPS differ"
        }
        return switchable.first { $0.id == defaultBundleID }?.name
            ?? "Linkpick"
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
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "Linkpick")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    func browserProfiles(for bundleIdentifier: String) -> [BrowserProfileChoice] {
        environment.browserProfiles.profiles(for: bundleIdentifier)
    }

    func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool {
        environment.browserProfiles.supportsPrivateWindow(bundleIdentifier)
    }

    func browserChoiceLabel(
        _ browser: BrowserReference,
        profile: BrowserProfileChoice? = nil
    ) -> String {
        let name = displayName(for: browser)
        guard let profile else { return name }
        return "\(name) · \(profile.name)"
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
        reload(reconcilingLease: true)
    }

    func selectBrowser(_ id: String) {
        selectedID = id
        workspaceDestination = .direct
    }

    func showWorkspace(_ destination: WorkspaceDestination) {
        workspaceDestination = destination
    }

    func openDiagnostics() {
        showDiagnostics = true
    }

    func openTimeMachine() {
        do {
            let history = try environment.stateRepository
                .inspectConfigurationHistory()
            timeMachineModel = PreviewTimeMachineModel.make(
                history: history,
                installedBrowsers: installed
            )
        } catch {
            timeMachineModel = PreviewTimeMachineModel(snapshots: [])
            message = "Linkpick could not read its history. Reopen the app and try again."
        }
        showTimeMachine = true
    }

    func returnToNow() {
        showTimeMachine = false
    }

    func evaluateHistoricalURL(
        _ rawURL: String,
        snapshotID: UUID
    ) -> HistoricalRoutingEvaluation {
        timeMachineModel.evaluate(
            rawURL,
            snapshotID: snapshotID,
            browserChange: browserChange,
            installedBrowsers: environment.browserCatalog
                .installedBrowsers()
        )
    }

    func displayName(for browser: BrowserReference) -> String {
        name(for: browser)
    }

    var hasClipboardWebURL: Bool {
        clipboardAirlockItem != nil
    }

    @discardableResult
    func stageClipboardURL() -> Bool {
        guard let item = clipboardAirlockItem else {
            message = "The clipboard does not contain a valid web link."
            return false
        }
        stageAirlock(urls: [item.normalized.originalURL])
        workspaceDestination = .airlock
        return true
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
            message = "Linkpick is already sending links."
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
        message = "Waiting for macOS to let Linkpick open web links."
        let outcome = await smartRoutingCoordinator.enable(
            fallback: fallback
        )
        reload()

        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = "Links open in \(name(for: fallback)), unless a rule says otherwise."
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
        message = "Stopping. \(name(for: fallback)) will be the usual browser."
        let outcome = await smartRoutingCoordinator.disable()
        reload()

        switch outcome {
        case .succeeded:
            transactionStatus = .idle
            message = "Stopped. \(name(for: fallback)) is the usual browser."
        case .failed(let issue):
            transactionStatus = .idle
            message = smartRoutingMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
        }
    }

    @discardableResult
    func borrowBrowser(
        _ browser: InstalledBrowser,
        for preset: BrowserLeasePreset
    ) -> Bool {
        guard isSmartRoutingActive else {
            message = "You can use another browser for a while only while Linkpick is sending links."
            return false
        }
        guard externalBrowsers.contains(where: { $0.id == browser.id }) else {
            message = "Choose an installed external browser to borrow."
            return false
        }

        let outcome = browserLeaseCoordinator.startLease(
            to: browser.reference,
            preset: preset,
            availableTargets: availableBrowserReferences
        )
        reload()
        switch outcome {
        case .succeeded:
            message = "\(preset.activeDescription(browserName: browser.name)). Rules stay as they are."
            return true
        case .failed(let issue):
            message = browserLeaseMessage(for: issue)
            return false
        }
    }

    @discardableResult
    func endBrowserLease() -> Bool {
        let outcome = browserLeaseCoordinator.endLease()
        reload()
        switch outcome {
        case .succeeded:
            message = leaseEndedMessage
            return true
        case .failed(let issue):
            message = browserLeaseMessage(for: issue)
            return false
        }
    }

    @discardableResult
    func undoBrowserLeaseChange() -> Bool {
        let outcome = browserLeaseCoordinator.undo()
        reload()
        switch outcome {
        case .succeeded:
            if let lease = activeBrowserLease {
                message = "Using \(name(for: lease.browser)) again."
            } else {
                message = leaseEndedMessage
            }
            return true
        case .failed(let issue):
            message = browserLeaseMessage(for: issue)
            return false
        }
    }

    #if DEBUG
    func expireUITestLease() {
        (environment.leaseScheduler as? UITestBrowserLeaseScheduler)?
            .fireAtDeadline()
    }
    #endif

    @discardableResult
    func setAutomationLeasesAllowed(_ isAllowed: Bool) -> Bool {
        do {
            let result = try intentBridge
                .setAutomationLeasesAllowed(isAllowed)
            reload()
            message = result
            return true
        } catch let error as BrowserChangeAutomationError {
            reload()
            message = error.errorDescription
            return false
        } catch {
            reload()
            message = "Linkpick could not save the Shortcuts setting."
            return false
        }
    }

    func routeIncomingURL(_ url: URL) async -> IncomingURLDisposition {
        reload(reconcilingLease: true)
        guard case .smartActive = routingState else {
            message = routingUnavailableMessage
            return .retryLater
        }

        let outcome = await routingCoordinator.route(
            url,
            configuration: smartRoutingCoordinator.configuration,
            availableTargets: availableBrowserReferences
        )
        switch outcome {
        case .opened(let browser):
            if message == nil {
                message = "Opened the incoming link in \(name(for: browser))."
            }
            return .consumed
        case .rejected(.unsupportedURL):
            message = "Linkpick only opens HTTP and HTTPS links."
            return .consumed
        case .rejected(.duplicateDispatch):
            message = "Linkpick stopped a repeated link."
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
            message = "\(fallbackName) could not open the link. Reinstall it or choose another browser."
            return .retryLater
        case .blocked(.missingFallback):
            message = smartRoutingMessage(for: .missingFallback)
            return .retryLater
        case .blocked:
            message = routingUnavailableMessage
            return .retryLater
        }
    }

    func stageAirlock(text: String) {
        airlockResult = AirlockParser().parse(text: text)
        message = airlockResult.items.isEmpty
            ? "No valid HTTP or HTTPS links were found."
            : "\(airlockResult.items.count) link\(airlockResult.items.count == 1 ? "" : "s") ready to review."
    }

    func stageAirlock(urls: [URL]) {
        airlockResult = AirlockParser().parse(urls: urls)
        message = airlockResult.items.isEmpty
            ? "No valid HTTP or HTTPS links were found."
            : "\(airlockResult.items.count) link\(airlockResult.items.count == 1 ? "" : "s") ready to review."
    }

    func clearAirlock() {
        airlockResult = AirlockParseResult(
            items: [],
            rejectedCandidateCount: 0,
            wasTextTruncated: false,
            wasURLLimitReached: false
        )
    }

    func prediction(for item: AirlockItem) -> RoutingDecision? {
        try? routingCoordinator.decision(
            for: item.normalized.originalURL,
            configuration: smartRoutingCoordinator.configuration,
            availableTargets: availableBrowserReferences
        )
    }

    func openAirlockNow(_ item: AirlockItem) async -> RoutingOutcome {
        reload(reconcilingLease: true)
        let outcome = await routingCoordinator.route(
            item.normalized.originalURL,
            configuration: smartRoutingCoordinator.configuration,
            availableTargets: availableBrowserReferences
        )
        updateMessage(for: outcome)
        return outcome
    }

    func openAirlock(
        _ item: AirlockItem,
        in browser: BrowserReference,
        always scope: DomainRuleScope? = nil,
        profileID: UUID? = nil,
        launch: BrowserLaunchMode = .standard
    ) async -> RoutingOutcome {
        await openAirlockFromChooser(
            item,
            in: browser,
            always: scope,
            profileID: profileID,
            launch: launch
        ).routingOutcome
    }

    func openAirlockFromChooser(
        _ item: AirlockItem,
        in browser: BrowserReference,
        always scope: DomainRuleScope? = nil,
        profileID: UUID? = nil,
        launch: BrowserLaunchMode = .standard
    ) async -> AirlockChooserResult {
        reload(reconcilingLease: true)
        let outcome = await routingCoordinator.route(
            item.normalized.originalURL,
            configuration: smartRoutingCoordinator.configuration,
            explicitTarget: browser,
            availableTargets: availableBrowserReferences,
            explicitLaunch: launch
        )
        guard case .opened(let openedBrowser) = outcome,
              openedBrowser == browser else {
            updateMessage(for: outcome)
            return AirlockChooserResult(
                routingOutcome: outcome,
                teachingRequested: scope != nil,
                teachingSucceeded: false,
                errorMessage: message
            )
        }

        guard let scope else {
            updateMessage(for: outcome)
            return AirlockChooserResult(
                routingOutcome: outcome,
                teachingRequested: false,
                teachingSucceeded: false,
                errorMessage: nil
            )
        }

        guard createRule(
                domain: item.normalized.host,
                scope: scope,
                browser: browser,
                profileID: profileID,
                browserProfile: savedBrowserProfile(from: launch),
                source: .airlock
        ) != nil else {
            let errorMessage = airlockTeachingFailureMessage(
                browser: browser
            )
            message = errorMessage
            return AirlockChooserResult(
                routingOutcome: outcome,
                teachingRequested: true,
                teachingSucceeded: false,
                errorMessage: errorMessage
            )
        }

        message = "Opened the link in \(name(for: browser)) and saved the “Always open” rule."
        return AirlockChooserResult(
            routingOutcome: outcome,
            teachingRequested: true,
            teachingSucceeded: true,
            errorMessage: nil
        )
    }

    private func savedBrowserProfile(
        from launch: BrowserLaunchMode
    ) -> BrowserProfileChoice? {
        if case .profile(let profile) = launch {
            return profile
        }
        return nil
    }

    @discardableResult
    func createRule(
        domain: String,
        scope: DomainRuleScope = .exactHost,
        browser: BrowserReference,
        profileID: UUID? = nil,
        browserProfile: BrowserProfileChoice? = nil,
        source: ConfigurationSource = .manual
    ) -> DomainRule? {
        var configuration = routingConfiguration
        do {
            let rule = try configurationEditor.createRule(
                domain: domain,
                scope: scope,
                browser: browser,
                profileID: profileID,
                browserProfile: browserProfile,
                source: source,
                in: &configuration
            )
            guard persist(configuration) else { return nil }
            message = "Saved a rule for \(rule.domain)."
            return rule
        } catch {
            message = configurationMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func updateRule(
        _ ruleID: UUID,
        domain: String,
        scope: DomainRuleScope,
        browser: BrowserReference,
        profileID: UUID?,
        browserProfile: BrowserProfileChoice? = nil,
        isEnabled: Bool
    ) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.updateRule(
                ruleID,
                domain: domain,
                scope: scope,
                browser: browser,
                profileID: profileID,
                browserProfile: browserProfile,
                isEnabled: isEnabled,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = "Updated the domain rule."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    @discardableResult
    func setRuleEnabled(_ ruleID: UUID, isEnabled: Bool) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.setRuleEnabled(
                ruleID,
                isEnabled: isEnabled,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = isEnabled ? "Enabled the domain rule." : "Disabled the domain rule."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    @discardableResult
    func deleteRule(_ ruleID: UUID) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.deleteRule(
                ruleID,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = "Deleted the domain rule."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    @discardableResult
    func createProfile(named name: String) -> RoutingProfile? {
        var configuration = routingConfiguration
        do {
            let profile = try configurationEditor.createProfile(
                named: name,
                in: &configuration
            )
            guard persist(configuration) else { return nil }
            message = "Created the \(profile.name) rule set."
            return profile
        } catch {
            message = configurationMessage(for: error)
            return nil
        }
    }

    @discardableResult
    func renameProfile(_ profileID: UUID, to name: String) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.renameProfile(
                profileID,
                to: name,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = "Renamed the rule set."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    @discardableResult
    func selectProfile(_ profileID: UUID?) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.selectProfile(
                profileID,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = profileID == nil
                ? "Using rules that apply everywhere."
                : "Selected the rule set."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    @discardableResult
    func deleteProfile(_ profileID: UUID) -> Bool {
        var configuration = routingConfiguration
        do {
            try configurationEditor.deleteProfile(
                profileID,
                in: &configuration
            )
            guard persist(configuration) else { return false }
            message = "Deleted the rule set and its rules."
            return true
        } catch {
            message = configurationMessage(for: error)
            return false
        }
    }

    func repairSelectedHandlers() async {
        guard !isSwitching else { return }
        guard !isSmartRoutingConfigured else {
            message = "Stop sending links before fixing HTTP and HTTPS."
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
        reload(reconcilingLease: true)

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
            message = "\(browser.name) is now the browser used when no rule matches."
            onRoutingAvailabilityChanged?()
        case .failed(let issue):
            message = smartRoutingMessage(for: issue)
        case .degraded(let issue):
            transactionStatus = .degraded
            routingState = .degraded(issue)
            message = smartRoutingMessage(for: issue)
        }
    }

    private var availableBrowserReferences: Set<BrowserReference> {
        Set(
            installed
                .filter {
                    !$0.isImaginary && $0.reference != browserChange
                        && environment.systemBrowserHandler
                            .applicationURL(for: $0.reference) != nil
                }
                .map(\.reference)
        )
    }

    private var clipboardAirlockItem: AirlockItem? {
        let pasteboard = NSPasteboard.general
        if let value = pasteboard.string(forType: .URL),
           let url = URL(string: value) {
            return AirlockParser().parse(urls: [url]).items.first
        }
        if let value = pasteboard.string(forType: .string) {
            return AirlockParser().parse(text: value).items.first
        }
        return nil
    }

    private func persist(_ configuration: RoutingConfiguration) -> Bool {
        let outcome = smartRoutingCoordinator.applyConfiguration(
            configuration
        )
        reload()
        switch outcome {
        case .succeeded:
            return true
        case .failed(let issue), .degraded(let issue):
            message = smartRoutingMessage(for: issue)
            return false
        }
    }

    private func updateMessage(for outcome: RoutingOutcome) {
        switch outcome {
        case .opened(let browser):
            message = "Opened the link in \(name(for: browser))."
        case .rejected(.duplicateDispatch):
            message = "Linkpick stopped a repeated link."
        case .rejected(.unsupportedURL):
            message = "Linkpick only opens HTTP and HTTPS links."
        case .rejected(.selfTarget):
            message = "Linkpick cannot open a link in itself."
        case .rejected(.explicitTargetUnavailable):
            message = "The selected browser is no longer available. Reinstall it or choose another browser."
        case .rejected:
            message = "The link could not be opened."
        case .blocked(.missingFallback):
            message = smartRoutingMessage(for: .missingFallback)
        case .blocked(.smartRoutingUnavailable):
            message = routingUnavailableMessage
        case .blocked:
            message = "The selected browser could not open the link."
        }
    }

    private func configurationMessage(for error: Error) -> String {
        switch error as? RoutingConfigurationIssue {
        case .selfTarget:
            "Linkpick cannot be the browser a rule opens."
        case .invalidDomain:
            "Enter a valid domain."
        case .invalidName:
            "Enter a rule set name."
        case .missingProfile:
            "That rule set is no longer available."
        case .missingRule:
            "That rule is no longer available."
        case nil:
            "Linkpick could not save that change."
        }
    }

    private func airlockTeachingFailureMessage(
        browser: BrowserReference
    ) -> String {
        let prefix = "The link opened in \(name(for: browser)), but the “Always open” rule was not saved."
        if message == "That rule set is no longer available." {
            return "\(prefix) Choose Everywhere or another rule set, then try again."
        }
        if message == "Enter a valid domain." {
            return "\(prefix) Check the domain, then try again."
        }
        return "\(prefix) Reopen Linkpick, then try again."
    }

    private var routingUnavailableMessage: String {
        switch routingState {
        case .smartSuspended:
            "macOS changed the web-link handler. Linkpick will not take it back."
        case .degraded(let issue):
            smartRoutingMessage(for: issue)
        case .direct:
            "Linkpick is not sending links. Turn that on before rules can open links."
        case .enabling, .disabling:
            "Linkpick is still changing how links open."
        case .smartActive:
            "Linkpick cannot send links right now."
        }
    }

    private func smartRoutingMessage(
        for issue: SmartRoutingIssue
    ) -> String {
        switch issue {
        case .missingFallback:
            "Choose an installed browser for sites with no rule."
        case .selfFallback:
            "Linkpick cannot be the browser used when no rule matches."
        case .fallbackUnavailable:
            "That browser is not installed. Reinstall it or choose another."
        case .smartRoutingNotEnabled:
            "Linkpick is not sending links."
        case .smartRoutingAlreadyEnabled:
            "Linkpick is already sending links."
        case .transitionCancelled:
            "That change was cancelled."
        case .handlerTransitionInProgress:
            "Linkpick is still changing how links open."
        case .configurationPersistenceFailed:
            "Linkpick could not save this. Reopen the app and try again."
        case .handlerTransaction(let issue):
            transactionMessage(for: issue)
        }
    }

    private var leaseEndedMessage: String {
        "The temporary browser ended. Rules and \(defaultBrowserName) are in use again."
    }

    private func browserLeaseMessage(
        for issue: BrowserLeaseIssue
    ) -> String {
        switch issue {
        case .smartRoutingUnavailable:
            "You can use another browser for a while only while Linkpick is sending links."
        case .selfTarget:
            "Linkpick cannot be the temporary browser."
        case .targetUnavailable:
            "That browser is not installed, so nothing changed."
        case .noActiveLease:
            "No temporary browser is on."
        case .noUndoReceipt:
            "There is no temporary browser change to undo."
        case .undoPreconditionFailed:
            "Undo is no longer available because the rules changed."
        case .configurationPersistenceFailed:
            "Linkpick could not save the temporary browser."
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
            return "The previous browser is not available, so Linkpick could not restore it."
        case .missingBaseline(let scheme):
            let schemeName = scheme.rawValue.uppercased()
            return "Linkpick cannot safely change the \(schemeName) handler because there is no current handler to restore. Set a default browser in System Settings, then try again."
        case .handlerChangeFailed:
            return "macOS did not change both web-link handlers. The previous handlers were restored."
        case .verificationFailed:
            return "macOS did not confirm both web-link handlers. The previous handlers were restored."
        case .handlersChangedExternally:
            return "The web-link handlers changed elsewhere. Linkpick kept those changes. Choose a browser and make HTTP and HTTPS match."
        case .rollbackFailed:
            return "Linkpick could not restore both web-link handlers. Make HTTP and HTTPS match before trying again."
        case .statePersistenceFailed:
            return "Linkpick could not save that browser change. Reopen the app and try again."
        case .noUndoReceipt:
            return "There is no browser change to undo."
        case .undoPreconditionFailed:
            return "Undo is no longer available because the web-link handlers changed elsewhere."
        }
    }

    private func reload(reconcilingLease: Bool = false) {
        installed = environment.browserCatalog.installedBrowsers()
        let handlers = environment.systemBrowserHandler.currentHandlers()
        handlerHealth = handlers.health(browserChange: browserChange)
        let leaseReconciliation: BrowserLeaseReconciliation
        if reconcilingLease {
            leaseReconciliation = browserLeaseCoordinator.reconcile(
                availableTargets: availableBrowserReferences
            )
        } else {
            browserLeaseCoordinator.refreshConfiguration()
            leaseReconciliation = BrowserLeaseReconciliation(
                didExpire: false,
                issue: nil
            )
        }
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
        activeBrowserLease = smartRoutingCoordinator
            .configuration.browserLease
        canUndoLease = browserLeaseCoordinator.canUndo
        allowsAutomationLeases = smartRoutingCoordinator
            .configuration.allowAutomationLeases
        publish()

        if leaseReconciliation.didExpire {
            message = leaseEndedMessage
        } else {
            switch leaseReconciliation.issue {
            case .targetUnavailable:
                message = "That browser is unavailable, so the temporary switch is paused. Rules and \(defaultBrowserName) still apply."
            case .selfTarget:
                message = "Linkpick cannot be the temporary browser. Rules and \(defaultBrowserName) still apply."
            case .configurationPersistenceFailed:
                message = "Linkpick could not check the temporary browser. Expired ones will not be used."
            case nil, .smartRoutingUnavailable, .noActiveLease,
                    .noUndoReceipt, .undoPreconditionFailed:
                break
            }
        }
    }

    private func name(for browser: BrowserReference) -> String {
        installed.first {
            $0.id == browser.bundleIdentifier
        }?.name ?? browser.bundleIdentifier
    }

    private func name(for application: HandlerApplication) -> String {
        name(for: application.browser)
    }

    private func publish() {
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

        icons = Dictionary(uniqueKeysWithValues: installed.map { browser in
            let icon = NSWorkspace.shared.icon(forFile: browser.iconURL.path)
            icon.size = NSSize(width: 64, height: 64)
            return (browser.id, icon)
        })
        revision += 1
    }
}
