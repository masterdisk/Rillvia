import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store
        @Bindable var workspace = store.workspace
        Group {
            if store.browsers.isEmpty {
                ContentUnavailableView(
                    "No browsers found",
                    systemImage: "globe",
                    description: Text("Rillvia looks for apps that open http and https links.")
                )
            } else {
                NavigationSplitView {
                    BrowserSidebar()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 232, max: 300)
                } detail: {
                    BrowserWorkspace()
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .font(.system(size: 15))
        .buttonBorderShape(.roundedRectangle)
        .frame(minWidth: 820, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh browsers", systemImage: "arrow.clockwise") {
                    store.refresh()
                }
                .help("Look for installed browsers again")
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains(
                "--ui-testing-lease-expiry-control"
            ) {
                ToolbarItem {
                    Button(
                        "Expire test lease",
                        systemImage: "clock.arrow.circlepath"
                    ) {
                        store.expireUITestLease()
                    }
                    .accessibilityIdentifier(
                        "ui-test-expire-lease"
                    )
                }
            }
            #endif
        }
        .sheet(isPresented: $store.showHall) {
            HallOfFameView(model: store.livingHallModel)
        }
        .sheet(isPresented: $store.showDiagnostics) {
            DiagnosticsView()
                .environment(store)
        }
        .sheet(isPresented: $store.showTimeMachine) {
            PreviewTimeMachineView()
                .environment(store)
        }
        .sheet(item: $workspace.chooserItem) { item in
            BrowserChooserView(item: item).environment(store)
        }
        .sheet(isPresented: $workspace.showTemporaryBrowser) {
            TemporaryBrowserSheet().environment(store)
        }
        .sheet(isPresented: $workspace.showKeyboardShortcuts) {
            KeyboardShortcutsView().environment(store)
        }
        .sheet(isPresented: $workspace.showTutorial) {
            IntroView { store.workspace.showTutorial = false }.environment(store)
        }
        .sheet(isPresented: $workspace.showRuleSets) {
            RuleSetsSheet().environment(store)
        }
        .alert("Discard unsaved changes?", isPresented: $workspace.showDiscardChanges) {
            Button("Keep editing", role: .cancel) { store.workspace.keepEditing() }
            Button("Discard changes", role: .destructive) { store.workspace.discardAndContinue() }
        } message: {
            Text("Your saved rule stays unchanged.")
        }
        .background {
            KeyCatcher()
        }
    }
}

private struct KeyCatcher: View {
    @Environment(BrowserStore.self) private var store
    @State private var monitor: Any?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                    if modifiers == [.command], event.charactersIgnoringModifiers == "z",
                       !(NSApp.keyWindow?.firstResponder is NSTextView), store.canUndoConfiguration {
                        store.workspace.request { _ = store.undoConfigurationChange() }
                        return nil
                    }
                    let blocked = event.modifierFlags.intersection([.command, .control, .option])
                    if blocked.isEmpty, let characters = event.charactersIgnoringModifiers {
                        let text = characters
                        Task { @MainActor in
                            store.noteTyping(text)
                        }
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }
}

#Preview {
    ContentView()
        .environment(BrowserStore())
        .frame(width: 880, height: 620)
}
