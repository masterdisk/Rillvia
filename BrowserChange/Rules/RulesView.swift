import SwiftUI

struct RulesView: View {
    @Environment(BrowserStore.self) private var store
    @State private var domain = ""
    @State private var scope: DomainRuleScope = .exactHost
    @State private var browserID = ""
    @State private var profileID: UUID?
    @State private var editingRule: DomainRule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Domain rules")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("rules-title")
                    Text(
                        "Exact-host rules win before parent-domain rules. Active-profile rules win before global rules."
                    )
                    .foregroundStyle(.secondary)
                }

                addRuleCard

                if store.routingConfiguration.domainRules.isEmpty {
                    ContentUnavailableView(
                        "No rules yet",
                        systemImage: "arrow.triangle.branch",
                        description: Text(
                            "Create one here or teach one from Link Airlock."
                        )
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.routingConfiguration.domainRules) {
                            rule in
                            ruleCard(rule)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if browserID.isEmpty {
                browserID = store.externalBrowsers.first?.id ?? ""
            }
        }
        .sheet(item: $editingRule) { rule in
            RuleEditView(rule: rule)
        }
    }

    private var addRuleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create rule")
                .font(.headline)

            TextField("example.com", text: $domain)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Scope", selection: $scope) {
                    Text("Exact host").tag(DomainRuleScope.exactHost)
                    Text("Include subdomains").tag(
                        DomainRuleScope.includeSubdomains
                    )
                }

                Picker("Browser", selection: $browserID) {
                    ForEach(store.externalBrowsers) { browser in
                        Text(browser.name).tag(browser.id)
                    }
                }

                Picker("Profile", selection: $profileID) {
                    Text("Global").tag(UUID?.none)
                    ForEach(store.routingConfiguration.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            }

            Button("Create rule") {
                guard let browser = store.externalBrowsers.first(
                    where: { $0.id == browserID }
                ) else {
                    return
                }
                if store.createRule(
                    domain: domain,
                    scope: scope,
                    browser: browser.reference,
                    profileID: profileID
                ) != nil {
                    domain = ""
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(
                domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || browserID.isEmpty
            )
        }
        .padding(16)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
    }

    private func ruleCard(_ rule: DomainRule) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.domain)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
                Text(scopeTitle(rule.scope))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "\(store.displayName(for: rule.browser)) · \(profileName(rule.profileID))"
                )
                .font(.callout)
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
        .padding(16)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .opacity(rule.isEnabled ? 1 : 0.62)
    }

    private func scopeTitle(_ scope: DomainRuleScope) -> String {
        switch scope {
        case .exactHost:
            "Exact host"
        case .includeSubdomains:
            "Include subdomains"
        }
    }

    private func profileName(_ id: UUID?) -> String {
        guard let id else { return "Global" }
        return store.routingConfiguration.profiles.first {
            $0.id == id
        }?.name ?? "Missing profile"
    }
}

private struct RuleEditView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var rule: DomainRule

    @State private var domain: String
    @State private var scope: DomainRuleScope
    @State private var browserID: String
    @State private var profileID: UUID?
    @State private var isEnabled: Bool

    init(rule: DomainRule) {
        self.rule = rule
        _domain = State(initialValue: rule.domain)
        _scope = State(initialValue: rule.scope)
        _browserID = State(
            initialValue: rule.browser.bundleIdentifier
        )
        _profileID = State(initialValue: rule.profileID)
        _isEnabled = State(initialValue: rule.isEnabled)
    }

    var body: some View {
        Form {
            TextField("Domain", text: $domain)
            Picker("Scope", selection: $scope) {
                Text("Exact host").tag(DomainRuleScope.exactHost)
                Text("Include subdomains").tag(
                    DomainRuleScope.includeSubdomains
                )
            }
            Picker("Browser", selection: $browserID) {
                ForEach(store.externalBrowsers) { browser in
                    Text(browser.name).tag(browser.id)
                }
            }
            Picker("Profile", selection: $profileID) {
                Text("Global").tag(UUID?.none)
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
