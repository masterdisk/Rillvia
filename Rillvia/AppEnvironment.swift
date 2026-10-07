import Foundation

struct AppEnvironment {
    var browserCatalog: any BrowserCatalog
    var systemBrowserHandler: any SystemBrowserHandling
    var stateRepository: StateRepository
    var urlLauncher: any ExternalURLLaunching
    var now: () -> Date
    var leaseScheduler: any BrowserLeaseScheduling
    var browserProfiles: any BrowserProfileReading

    @MainActor
    init(
        browserCatalog: any BrowserCatalog,
        systemBrowserHandler: any SystemBrowserHandling,
        stateRepository: StateRepository,
        urlLauncher: (any ExternalURLLaunching)? = nil,
        now: @escaping () -> Date = Date.init,
        leaseScheduler: (any BrowserLeaseScheduling)? = nil,
        browserProfiles: (any BrowserProfileReading)? = nil
    ) {
        self.browserCatalog = browserCatalog
        self.systemBrowserHandler = systemBrowserHandler
        self.stateRepository = stateRepository
        self.urlLauncher = urlLauncher ?? systemBrowserHandler
        self.now = now
        self.leaseScheduler = leaseScheduler
            ?? LeaseScheduler(now: now)
        self.browserProfiles = browserProfiles
            ?? EmptyBrowserProfileReader()
    }

    @MainActor
    static func live() -> AppEnvironment {
        let systemHandler = SystemBrowserHandler()
        return AppEnvironment(
            browserCatalog: WorkspaceBrowserCatalog(),
            systemBrowserHandler: systemHandler,
            stateRepository: StateRepository(),
            urlLauncher: systemHandler,
            browserProfiles: SystemBrowserProfileReader()
        )
    }

    @MainActor
    static func bootstrap(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppEnvironment {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            return uiTesting(arguments: arguments)
        }
        if arguments.contains("--ui-testing") {
            return uiTesting(arguments: arguments)
        }
        #endif
        return live()
    }

    #if DEBUG
    @MainActor
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
        let dia = InstalledBrowser(id: "company.thebrowser.dia", name: "Dia", version: "1.0", appURL: URL(fileURLWithPath: "/Applications/Dia.app"))
        let isDesignFixture = arguments.contains("--ui-testing-design-fixture")
        let chromeHandler = HandlerApplication(
            browser: chrome.reference,
            applicationURL: chrome.appURL
        )
        let safariHandler = HandlerApplication(
            browser: safari.reference,
            applicationURL: safari.appURL
        )
        let rillvia = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? AppIdentity.bundleIdentifier
        )
        let rillviaURL = Bundle.main.bundleURL
        let rillviaHandler = HandlerApplication(
            browser: rillvia,
            applicationURL: rillviaURL
        )
        let handlers: HTTPHandlerSnapshot
        if arguments.contains("--ui-testing-split-handlers") {
            handlers = HTTPHandlerSnapshot(
                http: safariHandler,
                https: chromeHandler
            )
        } else if arguments.contains(
            "--ui-testing-task7-fixture"
        ) || arguments.contains(
            "--ui-testing-routing-fixture"
        ) || isDesignFixture {
            handlers = .same(rillviaHandler)
        } else {
            handlers = .same(chromeHandler)
        }
        var applications = [
            safari.reference: safari.appURL,
            chrome.reference: chrome.appURL,
            rillvia: rillviaURL,
        ]
        if isDesignFixture { applications[dia.reference] = dia.appURL }
        if arguments.contains(
            "--ui-testing-explicit-target-unavailable"
        ) {
            applications[safari.reference] = nil
        }
        let handler = UITestSystemBrowserHandler(
            handlers: handlers,
            applications: applications
        )
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Rillvia-UITests-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        let repository = StateRepository(baseDirectory: stateDirectory)
        let testNow = Date(timeIntervalSince1970: 1_900_000_000)
        let testClock = UITestClock(now: testNow)
        let leaseScheduler = UITestBrowserLeaseScheduler(
            clock: testClock
        )
        if isDesignFixture {
            let work = RoutingProfile(name: "Work")
            let personal = RoutingProfile(name: "Personal")
            try? repository.saveConfiguration(RoutingConfiguration(
                mode: .smart, fallbackBrowser: safari.reference,
                domainRules: [
                    DomainRule(domain: "github.com", browser: chrome.reference, profileID: work.id),
                    DomainRule(domain: "meet.google.com", browser: chrome.reference, profileID: work.id),
                    DomainRule(domain: "youtube.com", browser: safari.reference, profileID: personal.id)
                ], profiles: [work, personal], activeProfileID: work.id
            ))
        } else if arguments.contains("--ui-testing-task7-fixture") {
            let work = RoutingProfile(
                id: UUID(
                    uuidString: "00000000-0000-0000-0000-000000000071"
                )!,
                name: "Work"
            )
            let smart = RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference
            )
            let rules = RoutingConfiguration(
                mode: .smart,
                fallbackBrowser: chrome.reference,
                domainRules: [
                    DomainRule(
                        id: UUID(
                            uuidString: "00000000-0000-0000-0000-000000000072"
                        )!,
                        domain: "example.com",
                        browser: safari.reference,
                        profileID: work.id
                    ),
                ],
                profiles: [work],
                activeProfileID: work.id
            )
            var leased = rules
            leased.browserLease = BrowserLease(
                id: UUID(
                    uuidString: "00000000-0000-0000-0000-000000000073"
                )!,
                browser: safari.reference,
                startedAt: testNow,
                expiresAt: testNow.addingTimeInterval(15 * 60)
            )
            try? repository.saveConfiguration(leased)
            try? repository.saveConfigurationHistory(
                ConfigurationHistory(
                    entries: [
                        ConfigurationHistoryEntry(
                            id: UUID(
                                uuidString: "00000000-0000-0000-0000-000000000074"
                            )!,
                            recordedAt: testNow.addingTimeInterval(-120),
                            configuration: smart
                        ),
                        ConfigurationHistoryEntry(
                            id: UUID(
                                uuidString: "00000000-0000-0000-0000-000000000075"
                            )!,
                            recordedAt: testNow.addingTimeInterval(-60),
                            configuration: rules
                        ),
                        ConfigurationHistoryEntry(
                            id: UUID(
                                uuidString: "00000000-0000-0000-0000-000000000076"
                            )!,
                            recordedAt: testNow,
                            configuration: leased
                        ),
                    ]
                )
            )
            if arguments.contains(
                "--ui-testing-history-failure"
            ) {
                try? Data(
                    #"{"schemaVersion":999,"entries":[]}"#.utf8
                ).write(
                    to: stateDirectory.appendingPathComponent(
                        "configuration-history.json"
                    )
                )
            }
        } else if arguments.contains(
            "--ui-testing-routing-fixture"
        ) {
            try? repository.saveConfiguration(
                RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: chrome.reference
                )
            )
        } else if arguments.contains("--ui-testing-smart-suspended") {
            try? repository.saveConfiguration(
                RoutingConfiguration(
                    mode: .smart,
                    fallbackBrowser: chrome.reference
                )
            )
        }

        return AppEnvironment(
            browserCatalog: UITestBrowserCatalog(browsers: isDesignFixture ? [safari, chrome, dia] : [safari, chrome]),
            systemBrowserHandler: handler,
            stateRepository: repository,
            urlLauncher: handler,
            now: { testClock.now },
            leaseScheduler: leaseScheduler,
            browserProfiles: isDesignFixture ? UITestDesignProfileReader() : EmptyBrowserProfileReader()
        )
    }
    #endif
}

#if DEBUG
final class UITestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
final class UITestBrowserLeaseScheduler: BrowserLeaseScheduling {
    private let clock: UITestClock
    private var deadline: Date?
    private var action: (() -> Void)?

    init(clock: UITestClock) {
        self.clock = clock
    }

    func schedule(at deadline: Date, action: @escaping () -> Void) {
        self.deadline = deadline
        self.action = action
    }

    func cancel() {
        deadline = nil
        action = nil
    }

    func fireAtDeadline() {
        guard let deadline else { return }
        let action = action
        self.deadline = nil
        self.action = nil
        clock.now = deadline
        action?()
    }
}

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

#if DEBUG
struct UITestDesignProfileReader: BrowserProfileReading {
    func profiles(for bundleIdentifier: String) -> [BrowserProfileChoice] {
        guard bundleIdentifier == "com.google.Chrome" else { return [] }
        return [BrowserProfileChoice(key: "Default", name: "Personal", family: .chromium), BrowserProfileChoice(key: "Profile 1", name: "Work", family: .chromium)]
    }
    func supportsPrivateWindow(_ bundleIdentifier: String) -> Bool { BrowserProfileCatalog.supportsPrivateWindow(bundleIdentifier) }
}
#endif
