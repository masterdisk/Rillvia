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
    var openError: Error?
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
        if let setError {
            throw setError
        }
        setCalls.append(.init(browser: browser, scheme: scheme))
        guard let applicationURL = applications[browser] else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
        handlers[scheme] = HandlerApplication(
            browser: browser,
            applicationURL: applicationURL
        )
    }

    func open(_ url: URL, with browser: BrowserReference) async throws {
        if let openError {
            throw openError
        }
        openCalls.append((url, browser))
    }
}
