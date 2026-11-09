import SwiftUI

struct RulesView: View {
    @Environment(BrowserStore.self) private var store
    @FocusState private var searchFocused: Bool
    private var workspace: WorkspaceModel { store.workspace }
    private var setName: String { store.routingConfiguration.profiles.first { $0.id == workspace.browsedProfileID }?.name ?? "Shared rules" }
    private var rules: [DomainRule] {
        store.routingConfiguration.domainRules.filter {
            $0.profileID == workspace.browsedProfileID && (workspace.ruleSearch.isEmpty || $0.domain.localizedCaseInsensitiveContains(workspace.ruleSearch) || store.displayName(for: $0.browser).localizedCaseInsensitiveContains(workspace.ruleSearch))
        }.sorted { $0.domain.localizedStandardCompare($1.domain) == .orderedAscending }
    }
    var body: some View {
        @Bindable var workspace = store.workspace
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(setName).appFont(size: 25, weight: .bold).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rules-title")
                        Text("\(rules.count) \(rules.count == 1 ? "rule" : "rules")").foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer(minLength: 5)
                    Button("New rule", systemImage: "plus") { newRule() }.labelStyle(.iconOnly).modifier(AccessibleButtonStyle()).controlSize(.large)
                        .help("New rule (⌘N)").accessibilityIdentifier("new-rule")
                }
                AppTextField("Search rules", text: $workspace.ruleSearch, focus: $searchFocused).accessibilityIdentifier("rule-search")
                if let profileID = workspace.browsedProfileID, store.routingConfiguration.activeProfileID != profileID {
                    Button("Make \(setName) active") { _ = store.selectProfile(profileID) }.modifier(AccessibleButtonStyle())
                        .accessibilityIdentifier("activate-browsed-rule-set")
                }
                if rules.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(workspace.ruleSearch.isEmpty ? "No rules yet" : "No matching rules").appFont(.headline)
                        Text(workspace.ruleSearch.isEmpty ? "Add a domain and choose where its links should open." : "Try another domain or browser name.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                        if workspace.ruleSearch.isEmpty { Button("Add a rule") { newRule() } }
                    }.padding(.vertical, 14)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(rules) { rule in
                                ruleRow(rule)
                            }
                        }
                    }
                }
                if workspace.browsedProfileID == nil {
                    Text("Shared rules apply alongside the active rule set. A matching rule in that set takes priority.").appFont(.caption).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(20).frame(width: 255)
            Divider()
            if let draft = workspace.draft {
                RuleDraftEditor(draft: Binding(get: { workspace.draft ?? draft }, set: { workspace.draft = $0 }))
            } else {
                VStack {
                    ContentUnavailableView("Choose a rule", systemImage: "arrow.triangle.branch", description: Text("Select a domain to edit it, or add a new rule."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    StoreNotice().padding(28)
                }
            }
        }
        .onAppear {
            if !workspace.didChooseRuleSet {
                workspace.browsedProfileID = store.routingConfiguration.activeProfileID
                workspace.didChooseRuleSet = true
            }
            if workspace.draft == nil, let first = rules.first { workspace.load(first) }
        }
        .onChange(of: workspace.focusRequest) { _, _ in if workspace.focus == .search { searchFocused = true } }
    }
    private func newRule() {
        workspace.request {
            workspace.startRule(browserID: store.smartFallbackBrowser?.id ?? store.externalBrowsers.first?.id ?? "", profileID: workspace.browsedProfileID)
        }
    }
    private func ruleRow(_ rule: DomainRule) -> some View {
        Button { workspace.request { workspace.load(rule) } } label: {
            HStack(spacing: 11) {
                Image(systemName: "globe").appFont(size: 21).foregroundStyle(rule.isEnabled ? Color.accentColor : .secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.domain).appFont(.body, weight: .medium).fixedSize(horizontal: false, vertical: true)
                    Text(store.browserChoiceLabel(rule.browser, profile: rule.browserProfile)).appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    if !rule.isEnabled { Text("Off").appFont(.caption).foregroundStyle(AppColors.secondaryText) }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(workspace.draft?.id == rule.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityAddTraits(workspace.draft?.id == rule.id ? [.isSelected] : [])
            .accessibilityIdentifier("rule-row-\(rule.domain)")
            .contextMenu {
                Button(rule.isEnabled ? "Turn rule off" : "Turn rule on") {
                    workspace.request {
                        if store.setRuleEnabled(rule.id, isEnabled: !rule.isEnabled), let updated = store.routingConfiguration.domainRules.first(where: { $0.id == rule.id }), workspace.draft?.id == rule.id { workspace.load(updated) }
                    }
                }
                Button("Delete rule", role: .destructive) {
                    workspace.request {
                        if store.deleteRule(rule.id), workspace.draft?.id == rule.id { workspace.draft = nil; workspace.savedDraft = nil }
                    }
                }
            }
    }
}

struct RuleDraftEditor: View {
    @Environment(BrowserStore.self) private var store
    @Binding var draft: RuleDraft
    @State private var error: String?
    @State private var showScopePicker = false
    @State private var showBrowserPicker = false
    @State private var showRuleSetPicker = false
    @State private var showBrowserProfilePicker = false
    private var browser: InstalledBrowser? { store.externalBrowsers.first { $0.id == draft.browserID } }
    private var profiles: [BrowserProfileChoice] { browser.map { store.browserProfiles(for: $0.id) } ?? [] }
    private var isValid: Bool { draft.normalizedDomain != nil && browser != nil }
    private var setName: String { store.routingConfiguration.profiles.first { $0.id == draft.profileID }?.name ?? "Shared rules" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: draft.id == nil ? "New rule" : draft.normalizedDomain ?? draft.domain, subtitle: "Rule in \(setName)", identifier: "rule-editor-title")
                Divider()
                FieldCaption(title: "Domain") {
                    AppTextField("example.com or a full URL", text: $draft.domain).accessibilityIdentifier("rule-domain")
                    if !draft.domain.isEmpty, draft.normalizedDomain == nil {
                        Text("Enter a valid domain or an HTTP or HTTPS link.").appFont(.callout).foregroundStyle(AppColors.errorText)
                    } else if let normalized = draft.normalizedDomain, normalized != draft.domain {
                        Text("Saves as \(normalized)").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    }
                }
                FieldCaption(title: "Match") {
                    WideSelector(label: "Domain matching", selectedID: draft.scope.rawValue,
                        choices: [SelectorChoice(id: DomainRuleScope.exactHost.rawValue, title: "Only this domain"), SelectorChoice(id: DomainRuleScope.includeSubdomains.rawValue, title: "This domain and its subdomains")], isPresented: $showScopePicker) { id in
                        if let scope = DomainRuleScope(rawValue: id) { draft.scope = scope }
                    }.accessibilityIdentifier("rule-scope")
                }
                FieldCaption(title: "Browser") {
                    WideSelector(label: "Browser for this rule", selectedID: draft.browserID,
                        choices: store.externalBrowsers.map { SelectorChoice(id: $0.id, title: $0.name, icon: store.icon(for: $0)) }, isPresented: $showBrowserPicker) { id in
                        // Reset only on a user pick; loading another rule must keep its saved profile.
                        guard id != draft.browserID else { return }
                        draft.browserID = id
                        draft.browserProfileID = ""
                    }
                        .accessibilityIdentifier("rule-browser")
                }
                DisclosureGroup("More options") {
                    VStack(alignment: .leading, spacing: 15) {
                        FieldCaption(title: "Rule set") {
                            WideSelector(label: "Rule set", selectedID: draft.profileID?.uuidString ?? "shared",
                                choices: [SelectorChoice(id: "shared", title: "Shared rules", symbol: "square.3.layers.3d")] + store.routingConfiguration.profiles.map { SelectorChoice(id: $0.id.uuidString, title: $0.name, symbol: "square.3.layers.3d") },
                                isPresented: $showRuleSetPicker) { draft.profileID = UUID(uuidString: $0) }
                        }
                        if !profiles.isEmpty {
                            FieldCaption(title: "Browser profile") {
                                WideSelector(label: "Browser profile", selectedID: draft.browserProfileID,
                                    choices: [SelectorChoice(id: "", title: "Default profile", symbol: "person.crop.circle")] + profiles.map { SelectorChoice(id: $0.id, title: $0.name, symbol: "person.crop.circle") },
                                    isPresented: $showBrowserProfilePicker) { draft.browserProfileID = $0 }
                            }
                        }
                        Toggle("Rule is on", isOn: $draft.isEnabled).accessibilityLabel("Rule for \(draft.normalizedDomain ?? "this domain") is on")
                    }.padding(.top, 12)
                }
                Text(draft.profileID == nil ? "Applies alongside your active rule set." : "Applies while \(setName) is active.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                FieldCaption(title: "Preview") {
                    HStack(spacing: 12) {
                        Image(systemName: "globe").foregroundStyle(AppColors.secondaryText)
                        Text(draft.normalizedDomain ?? "Your domain").fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right").foregroundStyle(AppColors.secondaryText)
                        BrowserIcon(browser: browser)
                        Text(browser?.name ?? "Choose a browser").fixedSize(horizontal: false, vertical: true)
                    }.appFont(.callout).padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
                if let error { Text(error).foregroundStyle(AppColors.errorText).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rule-save-error") }
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Button("Cancel") { store.workspace.cancelRule(); error = nil }.modifier(AccessibleButtonStyle()).controlSize(.large)
                    Button(draft.id == nil ? "Save rule" : "Save changes", action: save).modifier(AccessibleButtonStyle(prominent: true)).controlSize(.large)
                        .keyboardShortcut("s").disabled(!isValid || !store.workspace.hasUnsavedRule).accessibilityIdentifier("save-rule")
                }
                StoreNotice()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: draft.id) { _, _ in error = nil }
    }
    private func save() {
        guard let domain = draft.normalizedDomain, let browser else { return }
        let browserProfile = profiles.first { $0.id == draft.browserProfileID }
        let savedID: UUID?
        if let id = draft.id {
            savedID = store.updateRule(id, domain: domain, scope: draft.scope, browser: browser.reference, profileID: draft.profileID, browserProfile: browserProfile, isEnabled: draft.isEnabled) ? id : nil
        } else {
            savedID = store.createRule(domain: domain, scope: draft.scope, browser: browser.reference, profileID: draft.profileID, browserProfile: browserProfile, isEnabled: draft.isEnabled)?.id
        }
        if let id = savedID, let rule = store.routingConfiguration.domainRules.first(where: { $0.id == id }) {
            store.workspace.browsedProfileID = rule.profileID
            store.workspace.load(rule)
            error = nil
        } else { error = store.message ?? "The rule could not be saved. Try again." }
    }
}

struct RuleSetsSheet: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "Rule sets", subtitle: "Group rules for work, home, or anything else. Browsing a set does not make it active.")
            HStack {
                AppTextField("New rule set name", text: $newName)
                Button("Create") { if store.createProfile(named: newName) != nil { newName = "" } }.modifier(AccessibleButtonStyle()).controlSize(.large).disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.routingConfiguration.profiles) { profile in RuleSetEditRow(profile: profile) }
                }
            }.frame(maxHeight: 230)
            StoreNotice()
            HStack { Spacer(); Button("Done") { dismiss() }.modifier(AccessibleButtonStyle(prominent: true)).keyboardShortcut(.cancelAction) }
        }.padding(28).frame(width: 540)
    }
}

private struct RuleSetEditRow: View {
    @Environment(BrowserStore.self) private var store
    let profile: RoutingProfile
    @State private var name: String
    init(profile: RoutingProfile) { self.profile = profile; _name = State(initialValue: profile.name) }
    var body: some View {
        HStack {
            AppTextField("Rule set name", text: $name)
            Button("Rename") { _ = store.renameProfile(profile.id, to: name) }.modifier(AccessibleButtonStyle()).controlSize(.large).disabled(name == profile.name || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Menu {
                Button("Delete set and its rules", role: .destructive) { _ = store.deleteProfile(profile.id) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Options for \(profile.name)")
        }
    }
}
