import Foundation

enum RoutingMode: String, Codable, CaseIterable, Sendable {
    case direct
    case smart
}

enum DomainRuleScope: String, Codable, CaseIterable, Sendable {
    case exactHost
    case includeSubdomains
}

enum ConfigurationSource: String, Codable, Sendable {
    case manual
    case airlock
    case migrated
}

/// A durable browser identity. Application URLs may change when an app is moved
/// or updated, so persisted routing values keep only the bundle identifier.
struct BrowserReference: Codable, Hashable, Identifiable, Sendable {
    var bundleIdentifier: String

    var id: String {
        bundleIdentifier
    }

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
}

struct DomainRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var revision: Int
    var domain: String
    var scope: DomainRuleScope
    var browser: BrowserReference
    var profileID: UUID?
    var browserProfile: BrowserProfileChoice?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var source: ConfigurationSource

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        domain: String,
        scope: DomainRuleScope = .exactHost,
        browser: BrowserReference,
        profileID: UUID? = nil,
        browserProfile: BrowserProfileChoice? = nil,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        source: ConfigurationSource = .manual
    ) {
        self.id = id
        self.revision = revision
        self.domain = domain
        self.scope = scope
        self.browser = browser
        self.profileID = profileID
        self.browserProfile = browserProfile
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case domain
        case scope
        case browser
        case profileID
        case browserProfile
        case isEnabled
        case createdAt
        case updatedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let migratedAt = Date(timeIntervalSince1970: 0)
        id = try values.decode(UUID.self, forKey: .id)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        domain = try values.decode(String.self, forKey: .domain)
        scope = try values.decodeIfPresent(
            DomainRuleScope.self,
            forKey: .scope
        ) ?? .exactHost
        browser = try values.decode(BrowserReference.self, forKey: .browser)
        profileID = try values.decodeIfPresent(UUID.self, forKey: .profileID)
        browserProfile = try values.decodeIfPresent(
            BrowserProfileChoice.self,
            forKey: .browserProfile
        )
        isEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? true
        createdAt = try values.decodeIfPresent(
            Date.self,
            forKey: .createdAt
        ) ?? migratedAt
        updatedAt = try values.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? createdAt
        source = try values.decodeIfPresent(
            ConfigurationSource.self,
            forKey: .source
        ) ?? .migrated
    }
}

struct RoutingProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var revision: Int
    var name: String
    var browser: BrowserReference?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var source: ConfigurationSource

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        name: String,
        browser: BrowserReference? = nil,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        source: ConfigurationSource = .manual
    ) {
        self.id = id
        self.revision = revision
        self.name = name
        self.browser = browser
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case revision
        case name
        case browser
        case isEnabled
        case createdAt
        case updatedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let migratedAt = Date(timeIntervalSince1970: 0)
        id = try values.decode(UUID.self, forKey: .id)
        revision = try values.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        name = try values.decode(String.self, forKey: .name)
        browser = try values.decodeIfPresent(
            BrowserReference.self,
            forKey: .browser
        )
        isEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .isEnabled
        ) ?? true
        createdAt = try values.decodeIfPresent(
            Date.self,
            forKey: .createdAt
        ) ?? migratedAt
        updatedAt = try values.decodeIfPresent(
            Date.self,
            forKey: .updatedAt
        ) ?? createdAt
        source = try values.decodeIfPresent(
            ConfigurationSource.self,
            forKey: .source
        ) ?? .migrated
    }
}

struct BrowserLease: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var revision: Int
    var browser: BrowserReference
    var startedAt: Date
    var expiresAt: Date?

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        browser: BrowserReference,
        startedAt: Date,
        expiresAt: Date?
    ) {
        self.id = id
        self.revision = revision
        self.browser = browser
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    func isActive(at date: Date) -> Bool {
        guard date >= startedAt else { return false }
        return !hasExpired(at: date)
    }

    /// A clock stepped back before `startedAt` pauses the lease rather than ending it.
    func hasExpired(at date: Date) -> Bool {
        expiresAt.map { date >= $0 } ?? false
    }
}

struct RoutingConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion: Int
    var mode: RoutingMode
    var fallbackBrowser: BrowserReference?
    var domainRules: [DomainRule]
    var profiles: [RoutingProfile]
    var activeProfileID: UUID?
    var browserLease: BrowserLease?
    var allowAutomationLeases: Bool

    init(
        schemaVersion: Int = currentSchemaVersion,
        mode: RoutingMode = .direct,
        fallbackBrowser: BrowserReference? = nil,
        domainRules: [DomainRule] = [],
        profiles: [RoutingProfile] = [],
        activeProfileID: UUID? = nil,
        browserLease: BrowserLease? = nil,
        allowAutomationLeases: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.fallbackBrowser = fallbackBrowser
        self.domainRules = domainRules
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.browserLease = browserLease
        self.allowAutomationLeases = allowAutomationLeases
    }

    static let fresh = RoutingConfiguration()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case mode
        case fallbackBrowser
        case domainRules
        case profiles
        case activeProfileID
        case browserLease
        case allowAutomationLeases
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.currentSchemaVersion
        mode = try values.decodeIfPresent(
            RoutingMode.self,
            forKey: .mode
        ) ?? .direct
        fallbackBrowser = try values.decodeIfPresent(
            BrowserReference.self,
            forKey: .fallbackBrowser
        )
        domainRules = try values.decodeIfPresent(
            [DomainRule].self,
            forKey: .domainRules
        ) ?? []
        profiles = try values.decodeIfPresent(
            [RoutingProfile].self,
            forKey: .profiles
        ) ?? []
        activeProfileID = try values.decodeIfPresent(
            UUID.self,
            forKey: .activeProfileID
        )
        browserLease = try values.decodeIfPresent(
            BrowserLease.self,
            forKey: .browserLease
        )
        allowAutomationLeases = try values.decodeIfPresent(
            Bool.self,
            forKey: .allowAutomationLeases
        ) ?? false

        if let activeProfileID,
           !profiles.contains(where: { $0.id == activeProfileID }) {
            self.activeProfileID = nil
        }
    }
}
