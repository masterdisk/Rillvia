import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: BrowserStore?
    var openMainWindow: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--force-dark-appearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await store?.activate() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow?()
        }
        return true
    }
}

@main
struct BrowserChangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: BrowserStore

    init() {
        _store = State(
            initialValue: BrowserStore(environment: .bootstrap())
        )
    }

    var body: some Scene {
        Window("BrowserChange", id: "main") {
            RootView(delegate: appDelegate)
                .environment(store)
        }
        .defaultSize(width: 880, height: 620)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)

        MenuBarExtra {
            MenuPanel()
                .environment(store)
        } label: {
            MenuBarLabel(image: store.menuBarSource, name: store.defaultBrowserName)
                .id(store.revision)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct RootView: View {
    var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(BrowserStore.self) private var store

    var body: some View {
        ContentView()
            .onAppear {
                delegate.store = store
                delegate.openMainWindow = {
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
            .task {
                await store.activate()
            }
    }
}
