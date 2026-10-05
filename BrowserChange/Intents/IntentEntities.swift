import AppIntents
import Foundation

@MainActor
enum BrowserChangeIntentDependencies {
    static func register(
        _ bridge: BrowserChangeIntentBridge,
        manager: AppDependencyManager = .shared
    ) {
        manager.add(dependency: bridge)
    }
}

struct InstalledBrowserEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Browser"
    )
    static let defaultQuery = InstalledBrowserEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "Installed external browser"
        )
    }
}

struct InstalledBrowserEntityQuery:
    EntityStringQuery,
    EnumerableEntityQuery {
    @AppDependency private var bridge: BrowserChangeIntentBridge
    private var injectedBridge: BrowserChangeIntentBridge?

    init() {
        injectedBridge = nil
    }

    init(manager: AppDependencyManager) {
        injectedBridge = nil
        _bridge = AppDependency(manager: manager)
    }

    init(bridge: BrowserChangeIntentBridge) {
        injectedBridge = bridge
    }

    func entities(
        for identifiers: [InstalledBrowserEntity.ID]
    ) async throws -> [InstalledBrowserEntity] {
        let byID = Dictionary(
            uniqueKeysWithValues: try await allEntities().map {
                ($0.id, $0)
            }
        )
        return identifiers.compactMap { byID[$0] }
    }

    func suggestedEntities() async throws -> [InstalledBrowserEntity] {
        try await allEntities()
    }

    func allEntities() async throws -> [InstalledBrowserEntity] {
        let browsers: [AutomationBrowser]
        if let injectedBridge {
            browsers = try await injectedBridge.availableBrowsers()
        } else {
            browsers = try await bridge.availableBrowsers()
        }
        return browsers.map {
            InstalledBrowserEntity(id: $0.id, name: $0.name)
        }
    }

    func entities(
        matching string: String
    ) async throws -> [InstalledBrowserEntity] {
        let query = string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return try await allEntities()
        }
        return try await allEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }
}

struct RoutingProfileEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Routing Profile"
    )
    static let defaultQuery = RoutingProfileEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "Enabled routing profile"
        )
    }
}

struct RoutingProfileEntityQuery:
    EntityStringQuery,
    EnumerableEntityQuery {
    @AppDependency private var bridge: BrowserChangeIntentBridge
    private var injectedBridge: BrowserChangeIntentBridge?

    init() {
        injectedBridge = nil
    }

    init(manager: AppDependencyManager) {
        injectedBridge = nil
        _bridge = AppDependency(manager: manager)
    }

    init(bridge: BrowserChangeIntentBridge) {
        injectedBridge = bridge
    }

    func entities(
        for identifiers: [RoutingProfileEntity.ID]
    ) async throws -> [RoutingProfileEntity] {
        let byID = Dictionary(
            uniqueKeysWithValues: try await allEntities().map {
                ($0.id, $0)
            }
        )
        return identifiers.compactMap { byID[$0] }
    }

    func suggestedEntities() async throws -> [RoutingProfileEntity] {
        try await allEntities()
    }

    func allEntities() async throws -> [RoutingProfileEntity] {
        let profiles: [AutomationRoutingProfile]
        if let injectedBridge {
            profiles = try await injectedBridge.availableProfiles()
        } else {
            profiles = try await bridge.availableProfiles()
        }
        return profiles.map {
            RoutingProfileEntity(id: $0.id, name: $0.name)
        }
    }

    func entities(
        matching string: String
    ) async throws -> [RoutingProfileEntity] {
        let query = string.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            return try await allEntities()
        }
        return try await allEntities().filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.uuidString
                    .localizedCaseInsensitiveContains(query)
        }
    }
}
