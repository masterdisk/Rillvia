import SwiftUI

struct OverviewView: View {
    @Environment(BrowserStore.self) private var store
    @State private var showFallbackPicker = false
    @State private var showRuleSetPicker = false
    var body: some View {
        @Bindable var workspace = store.workspace
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    PageHeading(title: "Your links", subtitle: subtitle, size: 32)
                    RoutingStatus().padding(.top, 7)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) { fallbackPicker.frame(minWidth: 240); ruleSetPicker.frame(minWidth: 240) }
                    VStack(alignment: .leading, spacing: 18) { fallbackPicker; ruleSetPicker }
                }
                if store.isSmartRoutingActive {
                    Button {
                        workspace.showTemporaryBrowser = true
                    } label: {
                        HStack(spacing: 24) { Text("Use a browser temporarily"); ShortcutHint(keys: "⌘T") }.frame(minHeight: 24)
                    }.buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("temporary-browser")
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        Button("Turn on rules") { Task { await store.enableSmartRouting() } }
                            .buttonStyle(.glassProminent).controlSize(.large).disabled(store.isSwitching || store.externalBrowsers.isEmpty)
                            .accessibilityIdentifier("enable-rules")
                        Text(store.isSmartRoutingConfigured ? store.routingModeDetail : "macOS will ask to let Rillvia handle web links. Your chosen browser opens links without a matching rule.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ActiveBrowserNotice()
                if store.hasSplitHandlers, let splitMessage = store.splitHandlerMessage {
                    Text(splitMessage).foregroundStyle(.orange).accessibilityIdentifier("split-handler-warning")
                    Button("Review HTTP and HTTPS") { store.navigate(to: .direct) }
                }
                Divider().padding(.vertical, 1)
                PreviewInputSection(compact: true)
                if workspace.previewIsCurrent(revision: store.revision) {
                    ForEach(store.airlockResult.items) { item in PreviewResultCard(item: item, compact: true) }
                }
                Divider()
                HStack(alignment: .top) {
                    Label("Previewing does not open the link.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Button("Keyboard shortcuts") { workspace.showKeyboardShortcuts = true }.buttonStyle(.link)
                }
                StoreNotice()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: handlePickerFocus)
        .onChange(of: workspace.focusRequest) { _, _ in handlePickerFocus() }
    }
    private var subtitle: String {
        let browser = store.isSmartRoutingConfigured ? store.smartFallbackBrowser?.name ?? "Your browser" : store.defaultBrowserName
        if store.isSmartRoutingActive { return "\(browser) opens links unless a rule says otherwise." }
        if store.hasSplitHandlers { return "HTTP and HTTPS links use different browsers." }
        if let current = store.currentMacOSBrowser { return "Links currently open in \(current.name)." }
        return "macOS opens links with its current browser."
    }
    private var fallbackPicker: some View {
        FieldCaption(title: store.isSmartRoutingConfigured ? "Other links" : "Default browser") {
            WideSelector(label: "Other links browser", selectedID: store.isSmartRoutingConfigured ? store.smartFallbackBrowser?.id ?? "" : store.defaultBundleID ?? "",
                choices: store.externalBrowsers.map { SelectorChoice(id: $0.id, title: $0.name, icon: store.icon(for: $0)) }, isPresented: $showFallbackPicker) { id in
                if let browser = store.externalBrowsers.first(where: { $0.id == id }) { Task { await store.makeDefault(browser) } }
            }.disabled(store.isSwitching).accessibilityIdentifier("fallback-picker")
        }
    }
    private var ruleSetPicker: some View {
        FieldCaption(title: "Active rule set") {
            WideSelector(label: "Active rule set", selectedID: store.routingConfiguration.activeProfileID?.uuidString ?? "shared",
                choices: [SelectorChoice(id: "shared", title: "Shared rules only", symbol: "square.3.layers.3d")] + store.routingConfiguration.profiles.filter(\.isEnabled).map { SelectorChoice(id: $0.id.uuidString, title: $0.name, symbol: "square.3.layers.3d") }, isPresented: $showRuleSetPicker) { id in
                _ = store.selectProfile(UUID(uuidString: id))
            }.accessibilityIdentifier("active-rule-set-picker")
        }
    }
    private func handlePickerFocus() {
        if store.workspace.focus == .fallback { showFallbackPicker = true; store.workspace.focus = .url }
        if store.workspace.focus == .ruleSet { showRuleSetPicker = true; store.workspace.focus = .url }
    }
}
