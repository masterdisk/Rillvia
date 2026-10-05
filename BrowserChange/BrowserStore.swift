import AppKit
import Foundation
import Observation

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
    private(set) var revision = 0
    private(set) var installedCount = 0
    private(set) var board = PreviewBoard.empty

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
        self.transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
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

    var hasSplitHandlers: Bool {
        handlerHealth.hasSplitHandlers
    }

    var defaultBrowserName: String {
        if hasSplitHandlers {
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

    func repairSelectedHandlers() async {
        guard !isSwitching else { return }
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
        let outcome = await transactionCoordinator.recoverPendingOperation()
        reload()

        switch outcome {
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
        defaultBundleID = handlerHealth.agreedExternalBrowser?.bundleIdentifier
        canUndo = transactionCoordinator.canUndo(currentHandlers: handlers)
        publish()
    }

    private func name(for application: HandlerApplication) -> String {
        installed.first {
            $0.id == application.browser.bundleIdentifier
        }?.name ?? application.browser.bundleIdentifier
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
