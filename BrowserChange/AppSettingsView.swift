import ServiceManagement
import SwiftUI

struct AppSettingsView: View {
    @Environment(BrowserStore.self) private var store
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private var isTesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    PageHeading(title: "Settings", subtitle: "Appearance, startup, shortcuts, and help.", identifier: "settings-title", size: 32)
                    VStack(alignment: .trailing, spacing: 8) {
                        RoutingStatus()
                        Button(store.isSmartRoutingActive ? "Turn off rules" : "Turn on rules") {
                            Task { if store.isSmartRoutingActive { await store.disableSmartRouting() } else { await store.enableSmartRouting() } }
                        }.buttonStyle(.glass).controlSize(.small).disabled(store.isSwitching).accessibilityIdentifier("settings-routing-toggle")
                    }.padding(.top, 5)
                }
                settingsSection("General") {
                    HStack(spacing: 18) {
                        Text("Appearance")
                        Spacer(minLength: 8)
                        Picker("Appearance", selection: $appearance) {
                            Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 230)
                    }
                    Divider()
                    Toggle(isOn: Binding(get: { loginEnabled }, set: setLoginEnabled)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Open at login")
                            Text("Keep Rillvia in the menu bar after you sign in.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityIdentifier("open-at-login")
                    if let loginError { Text(loginError).font(.callout).foregroundStyle(.red) }
                    if !isTesting, SMAppService.mainApp.status == .requiresApproval {
                        Button("Open Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                settingsSection("Keyboard shortcuts") {
                    KeyboardShortcutSettings()
                }
                settingsSection("Apple Shortcuts") {
                    Toggle(isOn: Binding(get: { store.allowsAutomationLeases }, set: { _ = store.setAutomationLeasesAllowed($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow temporary switches")
                            Text("Let Apple Shortcuts switch browsers for a while.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityIdentifier("allow-shortcuts")
                }
                settingsSection("Help") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Setup tutorial")
                            Text("Review your browsers and first rule.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Start tutorial") { store.workspace.showTutorial = true }.buttonStyle(.glass).accessibilityIdentifier("replay-tutorial")
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostics")
                            Text("Check link handlers and saved settings.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Open") { store.openDiagnostics() }.buttonStyle(.glass).accessibilityLabel("Open diagnostics")
                    }
                    Divider()
                    HStack {
                        Button("Keyboard shortcuts") { store.workspace.showKeyboardShortcuts = true }.buttonStyle(.link)
                        Spacer(minLength: 12)
                        Button("Configuration history") { store.openTimeMachine() }.buttonStyle(.link)
                    }
                }
                if store.isSmartRoutingConfigured && !store.isSmartRoutingActive {
                    Text(store.routingModeDetail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button(AppBrand.name) { store.tapTitle() }.buttonStyle(.plain).font(.headline)
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0").foregroundStyle(.secondary)
                    Spacer()
                    Text("Your links, your way.").font(.callout).foregroundStyle(.secondary)
                    Button { store.tapMoon() } label: { Image(systemName: "moon.stars") }.buttonStyle(.plain).accessibilityLabel("Night owl")
                }
                StoreNotice()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if isTesting { loginEnabled = false } }
    }
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 0.6))
        }
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
                        Text("Your shortcuts").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(store.shortcuts.bindings) { binding in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ShortcutExecutor.title(binding.action, in: store)).fixedSize(horizontal: false, vertical: true)
                                    Text(binding.isEnabled ? binding.scope.title : "Off").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(binding.chord?.display ?? "No keys").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).fixedSize()
                            }
                        }
                        Divider()
                        Text("Built-in keys").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(shortcuts, id: \.0) { title, keys in HStack { Text(title); Spacer(); Text(keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) } }
                }
            }.frame(maxHeight: 410)
            Text("Inside text fields, ⌘Z undoes typing. Arrow keys move through pickers; Return chooses and Esc cancels.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Customize shortcuts") { dismiss(); store.navigate(to: .settings) }.buttonStyle(.link)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.cancelAction)
            }
        }.padding(28).frame(width: 520)
    }
}
