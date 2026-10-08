import AppKit
import SwiftUI

struct LinkAirlockView: View {
    @Environment(BrowserStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "Preview a link", subtitle: "See where it will open and why.", identifier: "airlock-title")
                PreviewInputSection(compact: false)
                if store.workspace.previewIsCurrent(revision: store.revision) {
                    ForEach(store.airlockResult.items) { item in PreviewResultCard(item: item) }
                } else if !store.airlockResult.items.isEmpty {
                    Label("The link or routing changed. Preview again to see the current destination.", systemImage: "arrow.clockwise")
                        .foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                } else {
                    ContentUnavailableView("Try a link", systemImage: "link", description: Text("Paste or drop an HTTP or HTTPS link above. Preview checks your local rules without opening the link."))
                }
                StoreNotice()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .dropDestination(for: String.self) { values, _ in
            store.workspace.previewInput = values.joined(separator: "\n")
            preview()
            return true
        }
        .dropDestination(for: URL.self) { values, _ in
            store.workspace.previewInput = values.map(\.absoluteString).joined(separator: "\n")
            preview()
            return true
        }
    }
    private func preview() {
        store.stageAirlock(text: store.workspace.previewInput)
        store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
    }
}

struct PreviewInputSection: View {
    @Environment(BrowserStore.self) private var store
    var compact: Bool
    @FocusState private var urlIsFocused: Bool
    var body: some View {
        @Bindable var workspace = store.workspace
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Try a link").appFont(size: 23, weight: .bold)
                    Text("See the browser and rule before opening.").foregroundStyle(AppColors.secondaryText)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                AppTextField("https://example.com", text: $workspace.previewInput, axis: compact ? .horizontal : .vertical, focus: $urlIsFocused)
                    .onSubmit(preview)
                    .accessibilityLabel("Link to preview").accessibilityIdentifier("airlock-input")
                Button(action: preview) { Text("Preview").frame(minWidth: 100, minHeight: 24) }.modifier(AccessibleButtonStyle(prominent: true)).controlSize(.large)
                    .disabled(workspace.previewInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("airlock-preview")
            }
            if !compact {
                HStack {
                    Label("Preview checks your local rules. It does not open or fetch the link.", systemImage: "lock")
                        .appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Clear") { workspace.previewInput = ""; workspace.previewedInput = ""; store.clearAirlock() }
                        .disabled(workspace.previewInput.isEmpty)
                }
            }
            if workspace.previewIsCurrent(revision: store.revision), store.airlockResult.items.isEmpty {
                Text("Enter a complete HTTP or HTTPS link, such as https://example.com.").foregroundStyle(AppColors.warningText)
                    .accessibilityIdentifier("airlock-error")
            }
            if store.airlockResult.rejectedCandidateCount > 0 {
                Text("\(store.airlockResult.rejectedCandidateCount) invalid or unsupported links were left out.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
            }
            if store.airlockResult.wasURLLimitReached || store.airlockResult.wasTextTruncated {
                Text("Preview accepts up to 20 links and 100,000 characters at a time.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
            }
        }
        .onAppear { if workspace.focus == .url { urlIsFocused = true } }
        .onChange(of: workspace.focusRequest) { _, _ in if workspace.focus == .url { urlIsFocused = true } }
    }
    private func preview() {
        store.stageAirlock(text: store.workspace.previewInput)
        store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
    }
}

struct PreviewResultCard: View {
    @Environment(BrowserStore.self) private var store
    let item: AirlockItem
    var compact = false
    @State private var showOriginal = false
    @State private var isOpening = false
    private var decision: RoutingDecision? { store.prediction(for: item) }
    private var browser: InstalledBrowser? { store.externalBrowsers.first { $0.reference == decision?.target } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                VStack(alignment: .leading, spacing: 9) {
                    Text(item.normalized.host).appFont(size: 22, weight: .semibold).textSelection(.enabled)
                    DisclosureGroup("Original link", isExpanded: $showOriginal) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.normalized.originalURL.absoluteString).appFont(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Button("Copy original link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.normalized.originalURL.absoluteString, forType: .string) }
                        }.padding(.top, 8)
                    }
                }
                Divider()
                Text("Why this browser?").appFont(.headline)
            }
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { destination.frame(minWidth: 230); HStack(spacing: 12) { actions } }
                    VStack(alignment: .leading, spacing: 16) { destination; HStack(spacing: 12) { actions } }
                }
            } else { destination }

            if !compact {
                ForEach(item.warnings, id: \.self) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle").appFont(.callout).foregroundStyle(AppColors.warningText).fixedSize(horizontal: false, vertical: true)
                }
                if !item.warnings.isEmpty {
                    Text("These notes describe the URL. Rillvia does not scan the destination.").appFont(.caption).foregroundStyle(AppColors.secondaryText)
                }
            }
            if !compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { actions }
                    VStack(alignment: .leading, spacing: 10) { actions }
                }
            }
        }
        .padding(compact ? 0 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(compact ? Color.clear : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
    private var destination: some View {
            HStack(alignment: .center, spacing: 14) {
                BrowserIcon(browser: browser, size: compact ? 38 : 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(browser.map { store.browserChoiceLabel($0.reference, profile: decision?.browserProfile) } ?? "No browser available").appFont(.body, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    Text(reasonText).appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
    }
    @ViewBuilder private var actions: some View {
        Button("Open in \(browser?.name ?? "browser")") {
            guard let decision else { return }
            isOpening = true
            let revision = store.revision
            Task { _ = await store.openPreview(item, expected: decision, revision: revision); isOpening = false }
        }
        .modifier(AccessibleButtonStyle(prominent: true)).controlSize(.large)
        .keyboardShortcut(store.airlockResult.items.count == 1 ? KeyboardShortcut(.return, modifiers: .command) : nil)
        .disabled(decision == nil || isOpening || !store.workspace.previewIsCurrent(revision: store.revision))
        .accessibilityIdentifier("airlock-open-now")
        if let ruleID = matchedRuleID {
            Button("Edit rule") { store.editRule(ruleID) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText).accessibilityIdentifier("airlock-edit-rule")
        }
        if !compact {
            Button("Choose another browser") { store.workspace.chooserItem = item }.modifier(AccessibleButtonStyle()).controlSize(.large)
                .accessibilityIdentifier("airlock-open-in")
        }
    }
    private var matchedRuleID: UUID? {
        switch decision?.reason {
        case .activeProfileExactHost(let id), .activeProfileParentDomain(let id), .globalExactHost(let id), .globalParentDomain(let id): id
        default: nil
        }
    }
    private var reasonText: String {
        if let id = matchedRuleID, let rule = store.routingConfiguration.domainRules.first(where: { $0.id == id }) {
            let set = store.routingConfiguration.profiles.first { $0.id == rule.profileID }?.name ?? "Shared rules"
            return "Matches \(rule.domain) in \(set)"
        }
        if decision?.reason == .externalFallback { return store.isSmartRoutingActive ? "No rule matches. Uses Other links." : store.isSmartRoutingConfigured ? "Rules are paused. Uses the current macOS default." : "Rules are off. Uses the current macOS default." }
        return decision?.reason.summary ?? "Choose an installed browser to open this link."
    }
}

struct BrowserChooserView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: AirlockItem
    @State private var browserID = ""
    @State private var search = ""
    @State private var browserProfileID = ""
    @State private var privateWindow = false
    @State private var alwaysOpen = false
    @State private var scope: DomainRuleScope = .exactHost
    @State private var profileID: UUID?
    @State private var error: String?
    @State private var isOpening = false
    @FocusState private var searchFocused: Bool
    private var selected: InstalledBrowser? { store.externalBrowsers.first { $0.id == browserID } }
    private var choices: [BrowserProfileChoice] { selected.map { store.browserProfiles(for: $0.id) } ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "Choose a browser", subtitle: item.normalized.host, identifier: "airlock-chooser-title")
            AppTextField("Search browsers", text: $search, focus: $searchFocused)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(store.externalBrowsers.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { browser in
                        Button {
                            browserID = browser.id; browserProfileID = ""; privateWindow = false
                        } label: {
                            HStack(spacing: 12) {
                                BrowserIcon(browser: browser)
                                Text(browser.name).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if browserID == browser.id { Image(systemName: "checkmark").foregroundStyle(.blue) }
                            }.padding(10).frame(maxWidth: .infinity).contentShape(Rectangle())
                                .background(browserID == browser.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).accessibilityIdentifier("chooser-browser-\(browser.name)")
                    }
                }
            }.frame(maxHeight: 160)
            if !choices.isEmpty {
                Picker("Browser profile", selection: $browserProfileID) {
                    Text("Default profile").tag("")
                    ForEach(choices) { Text($0.name).tag($0.id) }
                }.disabled(privateWindow)
            }
            if let selected, store.supportsPrivateWindow(selected.id) {
                Toggle("Open this link in a private window", isOn: $privateWindow)
                    .onChange(of: privateWindow) { _, value in if value { alwaysOpen = false; browserProfileID = "" } }
            }
            Toggle("Always open this site in this browser", isOn: $alwaysOpen).disabled(privateWindow)
                .accessibilityIdentifier("airlock-always-open")
            if privateWindow { Text("This link only. Private-window choices are not saved in rules.").appFont(.callout).foregroundStyle(AppColors.secondaryText) }
            if alwaysOpen {
                Picker("Match", selection: $scope) { Text("Only this domain").tag(DomainRuleScope.exactHost); Text("Include subdomains").tag(DomainRuleScope.includeSubdomains) }
                Picker("Rule set", selection: $profileID) {
                    Text("Shared rules").tag(Optional<UUID>.none)
                    ForEach(store.routingConfiguration.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let error { Text(error).foregroundStyle(AppColors.errorText).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("airlock-chooser-error") }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(isOpening)
                Spacer()
                Button("Open in \(selected?.name ?? "browser")") { open() }.modifier(AccessibleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction).disabled(selected == nil || isOpening).accessibilityIdentifier("chooser-open")
            }
        }.padding(28).frame(width: 510)
        .onAppear { browserID = store.prediction(for: item)?.target.bundleIdentifier ?? store.externalBrowsers.first?.id ?? ""; profileID = store.routingConfiguration.activeProfileID }
        .background(Button("Search browsers") { searchFocused = true }.keyboardShortcut("f").hidden())
    }
    private func open() {
        guard let selected else { return }
        isOpening = true
        let profile = choices.first { $0.id == browserProfileID }
        let launch: BrowserLaunchMode = privateWindow ? .privateWindow : profile.map(BrowserLaunchMode.profile) ?? .standard
        Task {
            let result = await store.openAirlockFromChooser(item, in: selected.reference, always: alwaysOpen ? scope : nil, profileID: profileID, launch: launch)
            isOpening = false
            if result.shouldDismiss { dismiss() } else { error = result.errorMessage }
        }
    }
}
