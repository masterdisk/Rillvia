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
    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        arguments: [String]
    ) async throws
}

extension WorkspaceApplicationAccess {
    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        arguments: [String]
    ) async throws {
        try await open(url, withApplicationAt: applicationURL)
    }
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
        try await open(
            url,
            withApplicationAt: applicationURL,
            arguments: []
        )
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        arguments: [String]
    ) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.promptsUserIfNeeded = false
        let urls: [URL]
        if arguments.isEmpty {
            urls = [url]
        } else {
            configuration.arguments = arguments
            urls = []
        }
        _ = try await workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        )
    }
}

enum SystemBrowserHandlerError: Error, Equatable {
    case rillviaIsNotExternalTarget
    case applicationNotFound(BrowserReference)
}

extension SystemBrowserHandlerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rillviaIsNotExternalTarget:
            "Rillvia cannot dispatch an external link to itself."
        case .applicationNotFound(let browser):
            "No installed application was found for \(browser.bundleIdentifier)."
        }
    }
}

final class SystemBrowserHandler: SystemBrowserHandling {
    private let workspace: any WorkspaceApplicationAccess
    private let rillviaBundleIdentifier: String

    init(
        workspace: any WorkspaceApplicationAccess =
            NSWorkspaceApplicationAccess(),
        rillviaBundleIdentifier: String =
            Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
    ) {
        self.workspace = workspace
        self.rillviaBundleIdentifier = rillviaBundleIdentifier
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
        try await open(url, with: browser, launch: .standard)
    }

    func open(
        _ url: URL,
        with browser: BrowserReference,
        launch: BrowserLaunchMode
    ) async throws {
        try rejectRillvia(browser)
        guard let applicationURL = applicationURL(for: browser) else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }

        let arguments = BrowserProfileCatalog.launchArguments(
            bundleIdentifier: browser.bundleIdentifier,
            launch: launch,
            url: url
        )
        if arguments.isEmpty {
            try await workspace.open(url, withApplicationAt: applicationURL)
        } else {
            try await workspace.open(
                url,
                withApplicationAt: applicationURL,
                arguments: arguments
            )
        }
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

    private func rejectRillvia(_ browser: BrowserReference) throws {
        guard !AppIdentity.isSelf(browser, reference: BrowserReference(bundleIdentifier: rillviaBundleIdentifier)) else {
            throw SystemBrowserHandlerError.rillviaIsNotExternalTarget
        }
    }
}
