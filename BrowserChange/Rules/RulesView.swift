import SwiftUI

struct RulesView: View {
    @Environment(BrowserStore.self) private var store
    @State private var domain = ""
    @State private var scope: DomainRuleScope = .exactHost
    @State private var browserID = ""
    @State private var browserProfileKey = ""
    @State private var profileID: UUID?
    @State private var editingRule: DomainRule?
    @State private var formError: String?

    var body: some View {
        LinkpickPage(title: "Rules", identifier: "rules-title") {
            ruleSection(title: "Everywhere", profileID: nil)
            ForEach(store.routingConfiguration.profiles) { profile in
                ruleSection(title: profile.name, profileID: profile.id)
            }
            Section("New rule") {
                addRuleCard
            }
        }
        .onAppear {
            syncBrowserSelection()
        }
        .onChange(of: store.externalBrowsers.map(\.id)) { _, ids in
            syncBrowserSelection(availableIDs: ids)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditView(rule: rule)
        }
    }

    private var addRuleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Domain or pasted link", text: $domain)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rule-domain-field")

            HStack {
                Picker("Scope", selection: $scope) {
                    Text("This site").tag(DomainRuleScope.exactHost)
                    Text("This site and subdomains").tag(
                        DomainRuleScope.includeSubdomains
                    )
                }

                Picker("Browser", selection: $browserID) {
                    ForEach(store.externalBrowsers) { browser in
                        Text(browser.name).tag(browser.id)
                    }
                }

                if browserProfiles.count > 1 {
                    Picker("Browser profile", selection: $browserProfileKey) {
                        Text("Usual window").tag("")
                        ForEach(browserProfiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .accessibilityIdentifier("rule-browser-profile")
                }

                Picker("Put in", selection: $profileID) {
                    Text("Everywhere").tag(UUID?.none)
                    ForEach(store.routingConfiguration.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            }

            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("rule-form-error")
            } else if canCreateRule {
                Text("Create a rule for this domain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter a domain or paste a link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rule-form-hint")
            }

            Button("Create rule") {
                submitNewRule()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreateRule)
        }
    }

    private func ruleSection(title: String, profileID: UUID?) -> some View {
        let rules = store.routingConfiguration.domainRules.filter {
            $0.profileID == profileID
        }
        let inUse = store.routingConfiguration.activeProfileID == profileID
            || profileID == nil
        return Section {
            if rules.isEmpty {
                Text("No rules in \(title).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    ruleCard(rule)
                }
            }
        } header: {
            Text(inUse ? "\(title) · in use" : title)
        }
    }

    private func ruleCard(_ rule: DomainRule) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.domain)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
                Text(
                    "\(scopeTitle(rule.scope)) · \(store.browserChoiceLabel(rule.browser, profile: rule.browserProfile))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: {
                        _ = store.setRuleEnabled(
                            rule.id,
                            isEnabled: $0
                        )
                    }
                )
            )
            .labelsHidden()

            Button("Edit") {
                editingRule = rule
            }

            Button("Delete", role: .destructive) {
                _ = store.deleteRule(rule.id)
            }
        }
        .opacity(rule.isEnabled ? 1 : 0.62)
    }

    private var browserProfiles: [BrowserProfileChoice] {
        store.browserProfiles(for: browserID)
    }

    private var selectedBrowserProfile: BrowserProfileChoice? {
        browserProfiles.first { $0.id == browserProfileKey }
    }

    private var selectedBrowser: InstalledBrowser? {
        store.externalBrowsers.first(where: { $0.id == browserID })
            ?? store.externalBrowsers.first
    }

    private var canCreateRule: Bool {
        (try? URLNormalizer.normalizeHost(domain)) != nil
            && selectedBrowser != nil
    }

    private func syncBrowserSelection(
        availableIDs: [String]? = nil
    ) {
        let ids = availableIDs ?? store.externalBrowsers.map(\.id)
        if browserID.isEmpty || !ids.contains(browserID) {
            browserID = ids.first ?? ""
            browserProfileKey = ""
        }
    }

    private func submitNewRule() {
        formError = nil
        guard let host = try? URLNormalizer.normalizeHost(domain) else {
            formError = domain.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                ? "Enter a domain or paste a link."
                : "That doesn’t look like a domain."
            return
        }
        guard let browser = selectedBrowser else {
            formError = "Choose a browser first."
            return
        }
        if store.createRule(
            domain: host,
            scope: scope,
            browser: browser.reference,
            profileID: profileID,
            browserProfile: selectedBrowserProfile
        ) != nil {
            domain = ""
        } else {
            formError = store.message
        }
    }

    private func scopeTitle(_ scope: DomainRuleScope) -> String {
        switch scope {
        case .exactHost:
            "This site"
        case .includeSubdomains:
            "This site and subdomains"
        }
    }

    private func profileName(_ id: UUID?) -> String {
        guard let id else { return "Everywhere" }
        return store.routingConfiguration.profiles.first {
            $0.id == id
        }?.name ?? "Missing rule set"
    }
}

private struct RuleEditView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var rule: DomainRule

    @State private var domain: String
    @State private var scope: DomainRuleScope
    @State private var browserID: String
    @State private var browserProfileKey: String
    @State private var profileID: UUID?
    @State private var isEnabled: Bool

    init(rule: DomainRule) {
        self.rule = rule
        _domain = State(initialValue: rule.domain)
        _scope = State(initialValue: rule.scope)
        _browserID = State(
            initialValue: rule.browser.bundleIdentifier
        )
        _browserProfileKey = State(
            initialValue: rule.browserProfile?.id ?? ""
        )
        _profileID = State(initialValue: rule.profileID)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    private var editBrowserProfiles: [BrowserProfileChoice] {
        store.browserProfiles(for: browserID)
    }

    var body: some View {
        Form {
            TextField("Domain", text: $domain)
            Picker("Scope", selection: $scope) {
                Text("This site").tag(DomainRuleScope.exactHost)
                Text("This site and subdomains").tag(
                    DomainRuleScope.includeSubdomains
                )
            }
            Picker("Browser", selection: $browserID) {
                ForEach(store.externalBrowsers) { browser in
                    Text(browser.name).tag(browser.id)
                }
            }
            if editBrowserProfiles.count > 1 {
                Picker("Browser profile", selection: $browserProfileKey) {
                    Text("Usual window").tag("")
                    ForEach(editBrowserProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }
            Picker("Rule set", selection: $profileID) {
                Text("Everywhere").tag(UUID?.none)
                ForEach(store.routingConfiguration.profiles) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            Toggle("Enabled", isOn: $isEnabled)

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    guard let browser = store.externalBrowsers.first(
                        where: { $0.id == browserID }
                    ) else {
                        return
                    }
                    if store.updateRule(
                        rule.id,
                        domain: domain,
                        scope: scope,
                        browser: browser.reference,
                        profileID: profileID,
                        browserProfile: editBrowserProfiles.first {
                            $0.id == browserProfileKey
                        },
                        isEnabled: isEnabled
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
