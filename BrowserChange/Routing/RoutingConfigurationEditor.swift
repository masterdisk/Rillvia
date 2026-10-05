import Foundation

enum RoutingConfigurationIssue: Error, Equatable, Sendable {
    case selfTarget
    case invalidDomain
    case invalidName
    case missingProfile
    case missingRule
}

struct RoutingConfigurationEditor {
    private let browserChange: BrowserReference
    private let now: () -> Date

    init(
        browserChange: BrowserReference,
        now: @escaping () -> Date = Date.init
    ) {
        self.browserChange = browserChange
        self.now = now
    }

    @discardableResult
    func createRule(
        domain: String,
        scope: DomainRuleScope = .exactHost,
        browser: BrowserReference,
        profileID: UUID? = nil,
        source: ConfigurationSource = .manual,
        in configuration: inout RoutingConfiguration
    ) throws -> DomainRule {
        try validateTarget(browser)
        try validateProfile(profileID, in: configuration)
        let normalizedDomain: String
        do {
            normalizedDomain = try URLNormalizer.normalizeHost(domain)
        } catch {
            throw RoutingConfigurationIssue.invalidDomain
        }

        let timestamp = now()
        let rule = DomainRule(
            domain: normalizedDomain,
            scope: scope,
            browser: browser,
            profileID: profileID,
            createdAt: timestamp,
            updatedAt: timestamp,
            source: source
        )
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
        configuration.domainRules.append(rule)
        return rule
    }

    func updateRule(
        _ ruleID: UUID,
        domain: String,
        scope: DomainRuleScope,
        browser: BrowserReference,
        profileID: UUID?,
        isEnabled: Bool,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard let index = configuration.domainRules.firstIndex(
            where: { $0.id == ruleID }
        ) else {
            throw RoutingConfigurationIssue.missingRule
        }
        try validateTarget(browser)
        try validateProfile(profileID, in: configuration)
        let normalizedDomain: String
        do {
            normalizedDomain = try URLNormalizer.normalizeHost(domain)
        } catch {
            throw RoutingConfigurationIssue.invalidDomain
        }

        configuration.domainRules[index].domain = normalizedDomain
        configuration.domainRules[index].scope = scope
        configuration.domainRules[index].browser = browser
        configuration.domainRules[index].profileID = profileID
        configuration.domainRules[index].isEnabled = isEnabled
        touchRule(at: index, in: &configuration)
    }

    func setRuleEnabled(
        _ ruleID: UUID,
        isEnabled: Bool,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard let index = configuration.domainRules.firstIndex(
            where: { $0.id == ruleID }
        ) else {
            throw RoutingConfigurationIssue.missingRule
        }
        configuration.domainRules[index].isEnabled = isEnabled
        touchRule(at: index, in: &configuration)
    }

    func deleteRule(
        _ ruleID: UUID,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard configuration.domainRules.contains(
            where: { $0.id == ruleID }
        ) else {
            throw RoutingConfigurationIssue.missingRule
        }
        configuration.domainRules.removeAll { $0.id == ruleID }
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }

    @discardableResult
    func createProfile(
        named name: String,
        in configuration: inout RoutingConfiguration
    ) throws -> RoutingProfile {
        let normalizedName = try validatedName(name)
        let timestamp = now()
        let profile = RoutingProfile(
            name: normalizedName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
        configuration.profiles.append(profile)
        return profile
    }

    func renameProfile(
        _ profileID: UUID,
        to name: String,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard let index = configuration.profiles.firstIndex(
            where: { $0.id == profileID }
        ) else {
            throw RoutingConfigurationIssue.missingProfile
        }
        configuration.profiles[index].name = try validatedName(name)
        configuration.profiles[index].revision += 1
        configuration.profiles[index].updatedAt = now()
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }

    func setProfileEnabled(
        _ profileID: UUID,
        isEnabled: Bool,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard let index = configuration.profiles.firstIndex(
            where: { $0.id == profileID }
        ) else {
            throw RoutingConfigurationIssue.missingProfile
        }
        configuration.profiles[index].isEnabled = isEnabled
        configuration.profiles[index].revision += 1
        configuration.profiles[index].updatedAt = now()
        if !isEnabled, configuration.activeProfileID == profileID {
            configuration.activeProfileID = nil
        }
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }

    func selectProfile(
        _ profileID: UUID?,
        in configuration: inout RoutingConfiguration
    ) throws {
        if let profileID {
            guard configuration.profiles.contains(
                where: { $0.id == profileID && $0.isEnabled }
            ) else {
                throw RoutingConfigurationIssue.missingProfile
            }
        }
        configuration.activeProfileID = profileID
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }

    func deleteProfile(
        _ profileID: UUID,
        in configuration: inout RoutingConfiguration
    ) throws {
        guard configuration.profiles.contains(
            where: { $0.id == profileID }
        ) else {
            throw RoutingConfigurationIssue.missingProfile
        }
        configuration.profiles.removeAll { $0.id == profileID }
        configuration.domainRules.removeAll { $0.profileID == profileID }
        if configuration.activeProfileID == profileID {
            configuration.activeProfileID = nil
        }
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }

    private func validateTarget(_ target: BrowserReference) throws {
        guard target != browserChange else {
            throw RoutingConfigurationIssue.selfTarget
        }
    }

    private func validateProfile(
        _ profileID: UUID?,
        in configuration: RoutingConfiguration
    ) throws {
        guard let profileID else { return }
        guard configuration.profiles.contains(
            where: { $0.id == profileID }
        ) else {
            throw RoutingConfigurationIssue.missingProfile
        }
    }

    private func validatedName(_ name: String) throws -> String {
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw RoutingConfigurationIssue.invalidName
        }
        return result
    }

    private func touchRule(
        at index: Int,
        in configuration: inout RoutingConfiguration
    ) {
        configuration.domainRules[index].revision += 1
        configuration.domainRules[index].updatedAt = now()
        configuration.schemaVersion = RoutingConfiguration.currentSchemaVersion
    }
}
