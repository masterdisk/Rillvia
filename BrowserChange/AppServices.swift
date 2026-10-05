import Foundation

@MainActor
final class BrowserChangeServices {
    let environment: AppEnvironment
    let browserChange: BrowserReference
    let transactionCoordinator: HandlerTransactionCoordinator
    let smartRoutingCoordinator: SmartRoutingCoordinator
    let browserLeaseCoordinator: BrowserLeaseCoordinator
    let routingCoordinator: RoutingCoordinator
    let configurationEditor: RoutingConfigurationEditor

    lazy var intentBridge = BrowserChangeIntentBridge(
        browserCatalog: environment.browserCatalog,
        systemHandler: environment.systemBrowserHandler,
        repository: environment.stateRepository,
        browserChange: browserChange,
        transactionCoordinator: transactionCoordinator,
        smartRoutingCoordinator: smartRoutingCoordinator,
        browserLeaseCoordinator: browserLeaseCoordinator,
        routingCoordinator: routingCoordinator,
        configurationEditor: configurationEditor
    )

    init(
        environment: AppEnvironment,
        browserChange: BrowserReference = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? "com.browserchange.BrowserChange"
        )
    ) {
        self.environment = environment
        self.browserChange = browserChange

        let transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            browserChange: browserChange,
            now: environment.now
        )
        self.transactionCoordinator = transactionCoordinator
        self.smartRoutingCoordinator = SmartRoutingCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            transactionCoordinator: transactionCoordinator,
            browserChange: browserChange
        )
        self.browserLeaseCoordinator = BrowserLeaseCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            browserChange: browserChange,
            scheduler: environment.leaseScheduler,
            now: environment.now
        )
        self.routingCoordinator = RoutingCoordinator(
            launcher: environment.urlLauncher,
            browserChange: browserChange,
            now: environment.now
        )
        self.configurationEditor = RoutingConfigurationEditor(
            browserChange: browserChange,
            now: environment.now
        )
    }
}

@MainActor
struct BrowserChangeAppRuntime {
    let services: BrowserChangeServices
    let store: BrowserStore

    init(
        environment: AppEnvironment,
        browserChange: BrowserReference = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? "com.browserchange.BrowserChange"
        ),
        registerIntentBridge: @MainActor (
            BrowserChangeIntentBridge
        ) -> Void = {
            BrowserChangeIntentDependencies.register($0)
        }
    ) {
        let services = BrowserChangeServices(
            environment: environment,
            browserChange: browserChange
        )
        registerIntentBridge(services.intentBridge)
        self.services = services
        self.store = BrowserStore(services: services)
    }
}
