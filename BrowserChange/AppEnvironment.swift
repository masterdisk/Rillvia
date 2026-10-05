import Foundation

struct AppEnvironment {
    var browserCatalog: any BrowserCatalog
    var systemBrowserHandler: any SystemBrowserHandling
    var stateRepository: StateRepository
    var urlLauncher: any ExternalURLLaunching

    init(
        browserCatalog: any BrowserCatalog,
        systemBrowserHandler: any SystemBrowserHandling,
        stateRepository: StateRepository,
        urlLauncher: (any ExternalURLLaunching)? = nil
    ) {
        self.browserCatalog = browserCatalog
        self.systemBrowserHandler = systemBrowserHandler
        self.stateRepository = stateRepository
        self.urlLauncher = urlLauncher ?? systemBrowserHandler
    }

    static func live() -> AppEnvironment {
        let systemHandler = SystemBrowserHandler()
        return AppEnvironment(
            browserCatalog: WorkspaceBrowserCatalog(),
            systemBrowserHandler: systemHandler,
            stateRepository: StateRepository(),
            urlLauncher: systemHandler
        )
    }

    static func bootstrap(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppEnvironment {
        #if DEBUG
        if arguments.contains("--ui-testing") {
            return uiTesting(arguments: arguments)
        }
        #endif
        return live()
    }

    #if DEBUG
    private static func uiTesting(arguments: [String]) -> AppEnvironment {
        let safari = InstalledBrowser(
            id: "com.apple.Safari",
            name: "Safari",
            version: "26.0",
            appURL: URL(fileURLWithPath: "/Applications/Safari.app")
        )
        let chrome = InstalledBrowser(
            id: "com.google.Chrome",
            name: "Google Chrome",
            version: "140",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let chromeHandler = HandlerApplication(
            browser: chrome.reference,
            applicationURL: chrome.appURL
        )
        let safariHandler = HandlerApplication(
            browser: safari.reference,
            applicationURL: safari.appURL
        )
        let browserChange = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? "com.browserchange.BrowserChange"
        )
        let browserChangeURL = Bundle.main.bundleURL
        let handlers: HTTPHandlerSnapshot
        if arguments.contains("--ui-testing-split-handlers") {
            handlers = HTTPHandlerSnapshot(
                http: safariHandler,
                https: chromeHandler
            )
        } else {
            handlers = .same(chromeHandler)
        }
        let handler = UITestSystemBrowserHandler(
            handlers: handlers,
            applications: [
                safari.reference: safari.appURL,
                chrome.reference: chrome.appURL,
                browserChange: browserChangeURL,
            ]
        )
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "BrowserChange-UITests-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        let repository = StateRepository(baseDirectory: stateDirectory)
        if arguments.contains("--ui-testing-smart-suspended") {
            try? repository.saveConfiguration(
                RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: chrome.reference
                )
            )
        }

        return AppEnvironment(
            browserCatalog: UITestBrowserCatalog(browsers: [safari, chrome]),
            systemBrowserHandler: handler,
            stateRepository: repository,
            urlLauncher: handler
        )
    }
    #endif
}

#if DEBUG
private struct UITestBrowserCatalog: BrowserCatalog {
    var browsers: [InstalledBrowser]

    func installedBrowsers() -> [InstalledBrowser] {
        browsers
    }
}

private final class UITestSystemBrowserHandler: SystemBrowserHandling {
    private var handlers: HTTPHandlerSnapshot
    private let applications: [BrowserReference: URL]

    init(
        handlers: HTTPHandlerSnapshot,
        applications: [BrowserReference: URL]
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
        guard let applicationURL = applications[browser] else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
        handlers[scheme] = HandlerApplication(
            browser: browser,
            applicationURL: applicationURL
        )
    }

    func open(_ url: URL, with browser: BrowserReference) async throws {
        guard applications[browser] != nil else {
            throw SystemBrowserHandlerError.applicationNotFound(browser)
        }
    }
}
#endif
