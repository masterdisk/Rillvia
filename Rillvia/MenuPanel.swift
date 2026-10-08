import AppKit
import SwiftUI

struct MenuBarLabel: View {
    var image: NSImage?
    var name: String
    var body: some View {
        Group {
            if let image { Image(nsImage: menuImage(image)) }
            else { Image(systemName: "arrow.triangle.branch") }
        }.accessibilityLabel(name)
    }
    private func menuImage(_ source: NSImage) -> NSImage {
        let copy = (source.copy() as? NSImage) ?? source
        copy.size = NSSize(width: 18, height: 18)
        copy.isTemplate = true
        return copy
    }
}

struct MenuPanel: View {
    private let panelWidth: CGFloat = 400
    private let contentInset: CGFloat = 16
    var delegate: AppDelegate
    @Environment(BrowserStore.self) private var store
    @Environment(UpdateController.self) private var updates
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @AppStorage("textScale", store: AppPreferences.defaults) private var savedTextScale = 1.0
    @Environment(\.rillviaTextScale) private var inheritedTextScale
    private var textScale: Double { max(inheritedTextScale, min(2, max(1, savedTextScale))) }
    @State private var browserID = ""
    @State private var duration: BrowserLeasePreset = .fifteenMinutes
    @State private var largeRuleSetPicker = false
    @State private var largeDurationPicker = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image("AppLogo").resizable().frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppBrand.name).appFont(size: 20, weight: .semibold)
                    RoutingStatus().accessibilityIdentifier("menu-routing-mode-title")
                }
                Spacer()
            }.frame(width: panelWidth - 40, alignment: .leading).padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text(store.isSmartRoutingActive ? "Other links" : "Default browser").foregroundStyle(AppColors.secondaryText).frame(width: 118, alignment: .leading)
                            BrowserIcon(browser: store.isSmartRoutingActive ? store.smartFallbackBrowser : store.currentMacOSBrowser, size: 22)
                            Text(store.isSmartRoutingActive ? store.smartFallbackBrowser?.name ?? "Choose a browser" : store.currentMacOSBrowserName)
                                .fontWeight(.medium).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("menu-other-links-browser")
                            Spacer(minLength: 0)
                        }.frame(minHeight: 28).accessibilityElement(children: .contain)
                        HStack(spacing: 12) {
                            Text("Active rule set").foregroundStyle(AppColors.secondaryText).frame(width: 118, alignment: .leading)
                            Image(systemName: "square.3.layers.3d").resizable().scaledToFit().foregroundStyle(AppColors.secondaryText).frame(width: 22, height: 22).accessibilityHidden(true)
                            if textScale > 1.25 {
                                WideSelector(label: "Active rule set", selectedID: store.routingConfiguration.activeProfileID?.uuidString ?? "shared",
                                    choices: [SelectorChoice(id: "shared", title: "Shared rules only")] + store.routingConfiguration.profiles.filter(\.isEnabled).map { SelectorChoice(id: $0.id.uuidString, title: $0.name) },
                                    isPresented: $largeRuleSetPicker) { _ = store.selectProfile(UUID(uuidString: $0)) }
                                    .accessibilityIdentifier("menu-rule-set-picker")
                            } else {
                            Menu {
                                ruleSetChoice("Shared rules only", id: nil)
                                ForEach(store.routingConfiguration.profiles.filter(\.isEnabled)) { profile in
                                    ruleSetChoice(profile.name, id: profile.id)
                                }
                                Divider()
                                Button("Manage rule sets") {
                                    presentMainWindow()
                                    store.workspace.showRuleSets = true
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(activeRuleSetName).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.down").appFont(size: 10, weight: .semibold).foregroundStyle(AppColors.secondaryText)
                                }.frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                                .accessibilityLabel("Active rule set").accessibilityValue(activeRuleSetName)
                                .accessibilityIdentifier("menu-rule-set-picker").disabled(store.isSwitching)
                            }
                        }.frame(minHeight: 28).accessibilityElement(children: .contain)
                    }.appFont(.callout)

                    Divider()
                    ActiveBrowserNotice()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Use temporarily").appFont(size: 20, weight: .semibold)
                        Text("Send links to one browser for a while.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    }
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(store.externalBrowsers) { browser in
                                Button { browserID = browser.id } label: {
                                    HStack(spacing: 10) {
                                        BrowserIcon(browser: browser, size: 24)
                                        Text(browser.name).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        Image(systemName: browserID == browser.id ? "checkmark.circle.fill" : "circle").foregroundStyle(browserID == browser.id ? Color.accentColor : Color.secondary)
                                    }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        .background(browserID == browser.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityLabel(browser.name)
                                    .accessibilityAddTraits(browserID == browser.id ? [.isSelected] : [])
                                    .accessibilityIdentifier("menu-choice-\(browser.id)")
                            }
                        }
                    }.frame(height: min(CGFloat(store.externalBrowsers.count) * 38 * textScale, 152 * textScale))
                    HStack(spacing: 10) {
                        Text("For").foregroundStyle(AppColors.secondaryText).frame(width: 22 * textScale, alignment: .leading)
                        durationPicker
                            .controlSize(.small)
                            .frame(width: panelWidth - contentInset * 2 - 10 - 22 * textScale)
                            .accessibilityIdentifier("menu-duration")
                    }
                    Button {
                        if let chosen { _ = store.borrowBrowser(chosen, for: duration) }
                    } label: { Text(duration.actionTitle(browserName: chosen?.name ?? "a browser")).fixedSize(horizontal: false, vertical: true).frame(minWidth: 0, maxWidth: .infinity, minHeight: 24) }
                    .modifier(AccessibleButtonStyle(prominent: true)).controlSize(.large)
                        .disabled(chosen == nil || !store.isSmartRoutingActive)
                        .accessibilityIdentifier("menu-start-temporary-browser")
                    Text(store.isSmartRoutingActive ? "Your rules resume when it ends." : "Turn on rules in Overview first.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    if store.hasClipboardWebURL {
                        Button("Preview clipboard link", systemImage: "doc.on.clipboard") {
                            guard store.stageClipboardURL() else { return }
                            store.workspace.previewInput = store.airlockResult.items.map(\.originalText).joined(separator: "\n")
                            store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
                            presentMainWindow()
                        }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText).accessibilityIdentifier("menu-open-clipboard-link")
                    }
                    StoreNotice()
                    if let message = store.shortcuts.lastMessage {
                        Text(message).appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Scroll content must keep the panel's width when native controls update their intrinsic size.
                .frame(width: panelWidth - contentInset * 2, alignment: .leading)
                .padding(contentInset)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Button("Open Rillvia", systemImage: "macwindow") { presentMainWindow() }.modifier(AccessibleButtonStyle()).controlSize(.large).accessibilityIdentifier("menu-open-app")
                Spacer(minLength: 0)
                Menu {
                    Button("Customize shortcuts") { presentMainWindow(); store.navigate(to: .settings) }
                    Button("Check for updates") { presentMainWindow(); store.navigate(to: .settings); Task { await updates.check() } }.disabled(updates.phase.isBusy)
                    Button("Keyboard shortcuts") { presentMainWindow(); store.workspace.showKeyboardShortcuts = true }
                    Button("Diagnostics") { presentMainWindow(); store.openDiagnostics() }
                    Divider()
                    Button("Quit Rillvia") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options")
            }.frame(width: panelWidth - contentInset * 2, alignment: .leading).padding(contentInset)
        }.appFont(size: 14).buttonBorderShape(.roundedRectangle)
            .environment(\.rillviaTextScale, textScale)
            .frame(width: panelWidth, height: 560, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .accentColor(AppColors.actionTint)
            .onAppear {
                browserID = store.activeLeaseBrowser?.id ?? store.externalBrowsers.first { $0.reference != store.smartFallbackBrowser?.reference }?.id ?? store.externalBrowsers.first?.id ?? ""
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-design-fixture") { browserID = "com.google.Chrome" }
                #endif
            }
    }
    private var chosen: InstalledBrowser? { store.externalBrowsers.first { $0.id == browserID } }
    @ViewBuilder private var durationPicker: some View {
        if textScale > 1.25 {
            WideSelector(label: "Temporary duration", selectedID: duration.rawValue,
                choices: BrowserLeasePreset.allCases.map { SelectorChoice(id: $0.rawValue, title: $0.title) },
                isPresented: $largeDurationPicker) { if let value = BrowserLeasePreset(rawValue: $0) { duration = value } }
        }
        else { durationOptions.pickerStyle(.segmented) }
    }
    private var durationOptions: some View {
        Picker("Temporary duration", selection: $duration) {
            Text("15 min").tag(BrowserLeasePreset.fifteenMinutes)
            Text("30 min").tag(BrowserLeasePreset.thirtyMinutes)
            Text("60 min").tag(BrowserLeasePreset.sixtyMinutes)
            Text("Until ended").tag(BrowserLeasePreset.untilEnded)
        }.labelsHidden()
    }
    private var activeRuleSetName: String { store.routingConfiguration.profiles.first { $0.id == store.routingConfiguration.activeProfileID }?.name ?? "Shared rules only" }
    @ViewBuilder private func ruleSetChoice(_ name: String, id: UUID?) -> some View {
        Button { _ = store.selectProfile(id) } label: {
            if store.routingConfiguration.activeProfileID == id { Label(name, systemImage: "checkmark") }
            else { Text(name) }
        }
    }
    private func presentMainWindow() {
        delegate.userWantsMainWindow()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        dismiss()
    }
}
