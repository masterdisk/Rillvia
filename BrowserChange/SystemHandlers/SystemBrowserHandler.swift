import AppKit
import Foundation

protocol SystemBrowserHandling {
    func currentHandlers() -> HTTPHandlerSnapshot
    func applicationURL(for browser: BrowserReference) -> URL?
    func setDefaultHandler(
        _ browser: BrowserReference,
        for scheme: WebScheme
    ) async throws
    func open(_ url: URL, with browser: BrowserReference) async throws
}

enum SystemBrowserHandlerError: Error, Equatable {
    case browserChangeIsNotExternalTarget
    case applicationNotFound(BrowserReference)
}

extension SystemBrowserHandlerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .browserChangeIsNotExternalTarget:
            "BrowserChange cannot dispatch an external link to itself."
        case .applicationNotFound(let browser):
            "No installed application was found for \(browser.bundleIdentifier)."
        }
    }
}

final class SystemBrowserHandler: SystemBrowserHandling {
    private let workspace: NSWorkspace
    private let browserChangeBundleIdentifier: String

    init(
        workspace: NSWorkspace = .shared,
        browserChangeBundleIdentifier: String =
            Bundle.main.bundleIdentifier ?? "com.browserchange.BrowserChange"
    ) {
        self.workspace = workspace
        self.browserChangeBundleIdentifier = browserChangeBundleIdentifier
    }

    func currentHandlers() -> HTTPHandlerSnapshot {
        HTTPHandlerSnapshot(
            http: currentHandler(for: .http),
            https: currentHandler(for: .https)
        )
    }

    func applicationURL(for browser: BrowserReference) -> URL? {
        workspace.urlForApplication(
            withBundleIdentifier: browser.bundleIdentifier
        )
    }

    func setDefaultHandler(
        _ browser: BrowserReference,
        for scheme: WebScheme
    ) async throws {
        try rejectBrowserChange(browser)
        guard let applicationURL = applicationURL(for: browser) else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
        try await workspace.setDefaultApplication(
            at: applicationURL,
            toOpenURLsWithScheme: scheme.rawValue
        )
    }

    func open(_ url: URL, with browser: BrowserReference) async throws {
        try rejectBrowserChange(browser)
        guard let applicationURL = applicationURL(for: browser) else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        _ = try await workspace.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }

    private func currentHandler(for scheme: WebScheme) -> HandlerApplication? {
        guard let applicationURL = workspace.urlForApplication(
            toOpen: scheme.probeURL
        ),
        let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier
        else {
            return nil
        }

        return HandlerApplication(
            browser: BrowserReference(bundleIdentifier: bundleIdentifier),
            applicationURL: applicationURL
        )
    }

    private func rejectBrowserChange(_ browser: BrowserReference) throws {
        guard browser.bundleIdentifier != browserChangeBundleIdentifier else {
            throw SystemBrowserHandlerError.browserChangeIsNotExternalTarget
        }
    }
}
