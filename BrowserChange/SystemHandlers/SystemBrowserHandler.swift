import AppKit
import Foundation

protocol SystemBrowserHandling: ExternalURLLaunching {
    func currentHandlers() -> HTTPHandlerSnapshot
    func applicationURL(for browser: BrowserReference) -> URL?
    func setDefaultHandler(
        _ browser: BrowserReference,
        for scheme: WebScheme
    ) async throws
}

protocol WorkspaceApplicationAccess {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    func defaultApplicationURL(for url: URL) -> URL?
    func setDefaultApplication(
        at applicationURL: URL,
        forScheme scheme: String
    ) async throws
    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL
    ) async throws
}

final class NSWorkspaceApplicationAccess: WorkspaceApplicationAccess {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    }

    func defaultApplicationURL(for url: URL) -> URL? {
        workspace.urlForApplication(toOpen: url)
    }

    func setDefaultApplication(
        at applicationURL: URL,
        forScheme scheme: String
    ) async throws {
        try await workspace.setDefaultApplication(
            at: applicationURL,
            toOpenURLsWithScheme: scheme
        )
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        _ = try await workspace.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }
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
    private let workspace: any WorkspaceApplicationAccess
    private let browserChangeBundleIdentifier: String

    init(
        workspace: any WorkspaceApplicationAccess =
            NSWorkspaceApplicationAccess(),
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
        workspace.applicationURL(
            forBundleIdentifier: browser.bundleIdentifier
        )
    }

    func setDefaultHandler(
        _ browser: BrowserReference,
        for scheme: WebScheme
    ) async throws {
        guard let applicationURL = applicationURL(for: browser) else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
        try await workspace.setDefaultApplication(
            at: applicationURL,
            forScheme: scheme.rawValue
        )
    }

    func open(_ url: URL, with browser: BrowserReference) async throws {
        try rejectBrowserChange(browser)
        guard let applicationURL = applicationURL(for: browser) else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }

        try await workspace.open(url, withApplicationAt: applicationURL)
    }

    private func currentHandler(for scheme: WebScheme) -> HandlerApplication? {
        guard let applicationURL = workspace.defaultApplicationURL(
            for: scheme.probeURL
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
