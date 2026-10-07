import ServiceManagement
import SwiftUI

struct AppSettingsView: View {
    @Environment(BrowserStore.self) private var store
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @AppStorage("textScale", store: AppPreferences.defaults) private var textScale = 1.0
    @Environment(\.rillviaTextScale) private var readingScale
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var appearancePicker = false
    @State private var textSizePicker = false
    private var isTesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    PageHeading(title: "Settings", subtitle: "Appearance, startup, updates, and shortcuts.", identifier: "settings-title", size: 32)
                    VStack(alignment: .trailing, spacing: 8) {
                        RoutingStatus()
                        Button(store.isSmartRoutingActive ? "Turn off rules" : "Turn on rules") {
                            Task { if store.isSmartRoutingActive { await store.disableSmartRouting() } else { await store.enableSmartRouting() } }
                        }.modifier(AccessibleGlassStyle()).controlSize(.small).disabled(store.isSwitching).accessibilityIdentifier("settings-routing-toggle")
                    }.padding(.top, 5)
                }
                settingsSection("General") {
                    settingsField {
                        Text("Appearance")
                        if readingScale <= 1.25 { Spacer(minLength: 8) }
                        WideSelector(label: "Appearance", selectedID: appearance, choices: [
                            SelectorChoice(id: "system", title: "System", symbol: "circle.lefthalf.filled"),
                            SelectorChoice(id: "light", title: "Light", symbol: "sun.max"),
                            SelectorChoice(id: "dark", title: "Dark", symbol: "moon")
                        ], isPresented: $appearancePicker) { appearance = $0 }
                            .frame(width: readingScale <= 1.25 ? 230 : nil)
                    }
                    Divider()
                    settingsField {
                        Text("Text size")
                        if readingScale <= 1.25 { Spacer(minLength: 8) }
                        WideSelector(label: "Text size", selectedID: String(textScale), choices: [1.0, 1.25, 1.5, 2.0].map {
                            SelectorChoice(id: String($0), title: "\(Int($0 * 100))%", symbol: "textformat.size")
                        }, isPresented: $textSizePicker) { if let value = Double($0) { textScale = value } }
                            .frame(width: readingScale <= 1.25 ? 230 : nil).accessibilityIdentifier("text-size-picker")
                    }
                    Divider()
                    Toggle(isOn: Binding(get: { loginEnabled }, set: setLoginEnabled)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open at login")
                            Text("Keep Rillvia in the menu bar after you sign in.").appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityIdentifier("open-at-login")
                    if let loginError { Text(loginError).appFont(.callout).foregroundStyle(AppColors.errorText) }
                    if !isTesting, SMAppService.mainApp.status == .requiresApproval {
                        Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                settingsSection("Updates") {
                    UpdateSettingsView()
                }
                settingsSection("Keyboard shortcuts") {
                    KeyboardShortcutSettings()
                }
                settingsSection("Apple Shortcuts") {
                    Toggle(isOn: Binding(get: { store.allowsAutomationLeases }, set: { _ = store.setAutomationLeasesAllowed($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow temporary switches")
                            Text("Let Apple Shortcuts switch browsers for a while.").appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityIdentifier("allow-shortcuts")
                }
                settingsSection("Help") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Setup tutorial")
                            Text("Review your browsers and first rule.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button("Start tutorial") { store.workspace.showTutorial = true }.modifier(AccessibleGlassStyle()).accessibilityIdentifier("replay-tutorial")
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostics")
                            Text("Check link handlers and saved settings.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Button("Open") { store.openDiagnostics() }.modifier(AccessibleGlassStyle()).accessibilityLabel("Open diagnostics")
                    }
                    Divider()
                    HStack {
                        Button("Keyboard shortcuts") { store.workspace.showKeyboardShortcuts = true }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                        Spacer(minLength: 12)
                        Button("Configuration history") { store.openTimeMachine() }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                    }
                }
                if store.isSmartRoutingConfigured && !store.isSmartRoutingActive {
                    Text(store.routingModeDetail).appFont(.callout).foregroundStyle(AppColors.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(AppBrand.name) { store.tapTitle() }.buttonStyle(.plain).appFont(.headline)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0").foregroundStyle(AppColors.secondaryText)
                    Spacer()
                    Text("Your links, your way.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    Button { store.tapMoon() } label: { Image(systemName: "moon.stars") }.buttonStyle(.plain).accessibilityLabel("Night owl")
                }
                StoreNotice()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if isTesting { loginEnabled = false } }
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).appFont(size: 16, weight: .semibold)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 0.6))
        }
    }
    private func settingsField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = readingScale > 1.25
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 18))
        return layout { content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func setLoginEnabled(_ enabled: Bool) {
        if isTesting { loginEnabled = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = "The login setting could not be changed. Open System Settings → General → Login Items and try again."
        }
    }
}

struct KeyboardShortcutsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let shortcuts: [(String, String)] = [
        ("Overview", "⌘1"), ("Preview a link", "⌘2"), ("Rules", "⌘3"), ("Browsers", "⌘4"), ("Settings", "⌘,"),
        ("Focus link preview", "⌘L"), ("Choose Other links browser", "⌘B"), ("Choose active rule set", "⇧⌘R"),
        ("Use a browser temporarily", "⌘T"), ("Search the current list", "⌘F"), ("New rule in Rules", "⌘N"),
        ("Save the current rule", "⌘S"), ("Preview the focused link", "Return"), ("Open a current preview", "⌘Return"),
        ("Undo a rule or rule-set change", "⌘Z"), ("Close a sheet or picker", "Esc"),
        ("Diagnostics", "⌥⌘U"), ("Configuration history", "⌥⌘T"), ("Show keyboard shortcuts", "⌘/")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Keyboard shortcuts", subtitle: "Built-in keys work while Rillvia is active. Add your own in Settings.", identifier: "keyboard-shortcuts-title")
            ScrollView {
                VStack(spacing: 11) {
                    if !store.shortcuts.bindings.isEmpty {
                        Text("Your shortcuts").appFont(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(store.shortcuts.bindings) { binding in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ShortcutExecutor.title(binding.action, in: store)).fixedSize(horizontal: false, vertical: true)
                                    Text(binding.isEnabled ? binding.scope.title : "Off").appFont(.caption).foregroundStyle(AppColors.secondaryText)
                                }
                                Spacer()
                                Text(binding.chord?.display ?? "No keys").appFont(.body, design: .monospaced).foregroundStyle(AppColors.secondaryText).fixedSize()
                            }
                        }
                        Divider()
                        Text("Built-in keys").appFont(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(shortcuts, id: \.0) { title, keys in HStack { Text(title); Spacer(); Text(keys).appFont(.body, design: .monospaced).foregroundStyle(AppColors.secondaryText) } }
                    Text("Inside text fields, ⌘Z undoes typing. Arrow keys move through pickers; Return chooses and Esc cancels.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }
            }
            HStack {
                Button("Customize shortcuts") { dismiss(); store.navigate(to: .settings) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                Spacer()
                Button("Done") { dismiss() }.modifier(AccessibleGlassStyle(prominent: true)).keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 520, height: 600)
    }
}
