import Foundation
@testable import BrowserChange

final class FakeBrowserCatalog: BrowserCatalog {
    var browsers: [InstalledBrowser]

    init(browsers: [InstalledBrowser] = []) {
        self.browsers = browsers
    }

    func installedBrowsers() -> [InstalledBrowser] {
        browsers
    }
}

final class FakeSystemBrowserHandler: SystemBrowserHandling {
    struct SetCall: Equatable {
        var browser: BrowserReference
        var scheme: WebScheme
    }

    var handlers: HTTPHandlerSnapshot
    var applications: [BrowserReference: URL]
    var setError: Error?
    var setErrorsByCall: [Int: Error] = [:]
    var setErrorsAfterMutationByCall: [Int: Error] = [:]
    var openError: Error?
    var ignoredSetCallIndices: Set<Int> = []
    var beforeSet: ((SetCall, Int) -> Void)?
    var afterSet: ((SetCall, Int) -> Void)?
    private(set) var setCalls: [SetCall] = []
    private(set) var openCalls: [(url: URL, browser: BrowserReference)] = []

    init(
        handlers: HTTPHandlerSnapshot = .missing,
        applications: [BrowserReference: URL] = [:]
    ) {
        self.handlers = handlers
        self.applications = applications
    }

    func currentHandlers() -> HTTPHandlerSnapshot {
        handlers
    }

    func applicationURL(for browser: BrowserReference) -> URL? {
        applications[browser]
    }

    func setDefaultHandler(
        _ browser: BrowserReference,
        for scheme: WebScheme
    ) async throws {
        let call = SetCall(browser: browser, scheme: scheme)
        let callIndex = setCalls.count
        setCalls.append(call)
        beforeSet?(call, callIndex)
        if let error = setErrorsByCall[callIndex] {
            throw error
        }
        if let setError {
            throw setError
        }
        guard let applicationURL = applications[browser] else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
        if !ignoredSetCallIndices.contains(callIndex) {
            handlers[scheme] = HandlerApplication(
                browser: browser,
                applicationURL: applicationURL
            )
        }
        afterSet?(call, callIndex)
        if let error = setErrorsAfterMutationByCall[callIndex] {
            throw error
        }
    }

    func open(_ url: URL, with browser: BrowserReference) async throws {
        if let openError {
            throw openError
        }
        openCalls.append((url, browser))
    }
}
