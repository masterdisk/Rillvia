import Foundation

@MainActor
final class RillviaServices {
    let environment: AppEnvironment
    let rillvia: BrowserReference
    let transactionCoordinator: HandlerTransactionCoordinator
    let smartRoutingCoordinator: SmartRoutingCoordinator
    let browserLeaseCoordinator: BrowserLeaseCoordinator
    let routingCoordinator: RoutingCoordinator
    let configurationEditor: RoutingConfigurationEditor

    lazy var intentBridge = RillviaIntentBridge(
        browserCatalog: environment.browserCatalog,
        systemHandler: environment.systemBrowserHandler,
        repository: environment.stateRepository,
        rillvia: rillvia,
        transactionCoordinator: transactionCoordinator,
        smartRoutingCoordinator: smartRoutingCoordinator,
        browserLeaseCoordinator: browserLeaseCoordinator,
        routingCoordinator: routingCoordinator,
        configurationEditor: configurationEditor
    )

    init(
        environment: AppEnvironment,
        rillvia: BrowserReference = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? AppIdentity.bundleIdentifier
        )
    ) {
        self.environment = environment
        self.rillvia = rillvia

        let transactionCoordinator = HandlerTransactionCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            rillvia: rillvia,
            now: environment.now
        )
        self.transactionCoordinator = transactionCoordinator
        self.smartRoutingCoordinator = SmartRoutingCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            transactionCoordinator: transactionCoordinator,
            rillvia: rillvia
        )
        self.browserLeaseCoordinator = BrowserLeaseCoordinator(
            systemHandler: environment.systemBrowserHandler,
            repository: environment.stateRepository,
            rillvia: rillvia,
            smartRoutingCoordinator: smartRoutingCoordinator,
            scheduler: environment.leaseScheduler,
            now: environment.now
        )
        self.routingCoordinator = RoutingCoordinator(
            launcher: environment.urlLauncher,
            rillvia: rillvia,
            now: environment.now
        )
        self.configurationEditor = RoutingConfigurationEditor(
            rillvia: rillvia,
            now: environment.now
        )
    }
}

@MainActor
struct RillviaAppRuntime {
    let services: RillviaServices
    let store: BrowserStore

    init(
        environment: AppEnvironment,
        rillvia: BrowserReference = BrowserReference(
            bundleIdentifier: Bundle.main.bundleIdentifier
                ?? AppIdentity.bundleIdentifier
        ),
        registerIntentBridge: @MainActor (
            RillviaIntentBridge
        ) -> Void = {
            RillviaIntentDependencies.register($0)
        }
    ) {
        let services = RillviaServices(
            environment: environment,
            rillvia: rillvia
        )
        registerIntentBridge(services.intentBridge)
        self.services = services
        self.store = BrowserStore(services: services)
    }
}
