import AppKit
import SwiftUI

@MainActor
struct RillviaCommands: Commands {
    let store: BrowserStore
    let updates: UpdateController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings") { navigate(.settings) }.keyboardShortcut(",")
        }
        CommandGroup(after: .appInfo) {
            Button("Check for updates") { navigate(.settings); Task { await updates.check() } }.disabled(updates.phase.isBusy)
        }
        CommandGroup(replacing: .newItem) {
            Button("New rule") {
                store.workspace.request {
                    store.workspace.startRule(browserID: store.smartFallbackBrowser?.id ?? store.externalBrowsers.first?.id ?? "", profileID: store.workspace.browsedProfileID)
                }
            }.keyboardShortcut("n").disabled(store.workspaceDestination != .rules)
        }
        CommandGroup(after: .sidebar) {
            Button("Overview") { navigate(.overview) }.keyboardShortcut("1")
            Button("Preview a link") { navigate(.airlock) }.keyboardShortcut("2")
            Button("Rules") { navigate(.rules) }.keyboardShortcut("3")
            Button("Browsers") { navigate(.direct) }.keyboardShortcut("4")
            Divider()
            Button("Focus link preview") { navigate(.airlock); store.workspace.requestFocus(.url) }.keyboardShortcut("l")
            Button("Choose Other links browser") { navigate(.overview); store.workspace.requestFocus(.fallback) }.keyboardShortcut("b")
            Button("Choose active rule set") { navigate(.overview); store.workspace.requestFocus(.ruleSet) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Use a browser temporarily") { showWindow(); store.workspace.showTemporaryBrowser = true }.keyboardShortcut("t").disabled(!store.isSmartRoutingActive)
            Button("Search") { store.workspace.requestFocus(.search) }.keyboardShortcut("f").disabled(store.workspaceDestination != .rules && store.workspaceDestination != .direct)
        }
        CommandMenu("Tools") {
            Button("Diagnostics") { showWindow(); store.openDiagnostics() }.keyboardShortcut("u", modifiers: [.command, .option])
            Button("Configuration history") { showWindow(); store.openTimeMachine() }.keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Living Browser Hall") { showWindow(); store.showHall = true }
            Button("Undo rule or rule-set change") { _ = store.undoConfigurationChange() }.disabled(!store.canUndoConfiguration)
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard shortcuts") { showWindow(); store.workspace.showKeyboardShortcuts = true }.keyboardShortcut("/")
            Button("Take the tour again") { showWindow(); store.workspace.showTutorial = true }
        }
    }
    private func navigate(_ destination: WorkspaceDestination) { showWindow(); store.navigate(to: destination) }
    private func showWindow() { delegate.userWantsMainWindow(); openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
}
