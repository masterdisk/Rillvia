import Foundation

enum RoutingMode: String, Codable, CaseIterable, Sendable {
    case direct
    case smart
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
    var browser: BrowserReference
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        domain: String,
        browser: BrowserReference,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.revision = revision
        self.domain = domain
        self.browser = browser
        self.isEnabled = isEnabled
    }
}

struct RoutingProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var revision: Int
    var name: String
    var browser: BrowserReference
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        name: String,
        browser: BrowserReference,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.revision = revision
        self.name = name
        self.browser = browser
        self.isEnabled = isEnabled
    }
}

struct RoutingLease: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var revision: Int
    var domain: String
    var browser: BrowserReference
    var expiresAt: Date

    init(
        id: UUID = UUID(),
        revision: Int = 1,
        domain: String,
        browser: BrowserReference,
        expiresAt: Date
    ) {
        self.id = id
        self.revision = revision
        self.domain = domain
        self.browser = browser
        self.expiresAt = expiresAt
    }
}

struct RoutingConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var mode: RoutingMode
    var fallbackBrowser: BrowserReference?
    var domainRules: [DomainRule]
    var profiles: [RoutingProfile]
    var leases: [RoutingLease]

    init(
        schemaVersion: Int = currentSchemaVersion,
        mode: RoutingMode = .direct,
        fallbackBrowser: BrowserReference? = nil,
        domainRules: [DomainRule] = [],
        profiles: [RoutingProfile] = [],
        leases: [RoutingLease] = []
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.fallbackBrowser = fallbackBrowser
        self.domainRules = domainRules
        self.profiles = profiles
        self.leases = leases
    }

    static let fresh = RoutingConfiguration()
}
