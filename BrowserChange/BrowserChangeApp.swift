import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: BrowserStore?
    var openMainWindow: (() -> Void)?
    private let incomingURLQueue: IncomingURLQueue
    private var isPreparedForIncomingURLs = false
    private var isPreparingForIncomingURLs = false

    override init() {
        self.incomingURLQueue = IncomingURLQueue()
        super.init()
    }

    init(incomingURLQueue: IncomingURLQueue) {
        self.incomingURLQueue = incomingURLQueue
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--force-dark-appearance") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if ProcessInfo.processInfo.arguments.contains(
            "--force-light-appearance"
        ) {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        if ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-incoming-fallback"
        ), let url = URL(
            string: "https://unmatched.invalid/incoming"
        ) {
            incomingURLQueue.enqueue([url])
        }
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await prepareForIncomingURLs() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        incomingURLQueue.enqueue(urls)
        Task {
            if isPreparedForIncomingURLs {
                await incomingURLQueue.drain()
            } else {
                await prepareForIncomingURLs()
            }
        }
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

    func connect(
        store: BrowserStore,
        openMainWindow: @escaping () -> Void
    ) {
        self.store = store
        self.openMainWindow = openMainWindow
        incomingURLQueue.attach { [weak store] url in
            guard let store else {
                return .retryLater
            }
            return await store.routeIncomingURL(url)
        }
        store.onRoutingAvailabilityChanged = { [weak self] in
            guard let self else { return }
            Task { await self.incomingURLQueue.drain() }
        }
    }

    func prepareForIncomingURLs() async {
        guard let store, !isPreparingForIncomingURLs else {
            return
        }
        isPreparingForIncomingURLs = true
        await store.activate()
        isPreparedForIncomingURLs = true
        isPreparingForIncomingURLs = false
        await incomingURLQueue.drain()
    }
}

@main
struct BrowserChangeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: BrowserStore
    private let runtime: BrowserChangeAppRuntime

    init() {
        let runtime = BrowserChangeAppRuntime(
            environment: .bootstrap()
        )
        self.runtime = runtime
        BrowserChangeAppShortcuts.updateAppShortcutParameters()
        _store = State(
            initialValue: runtime.store
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
        .commands {
            BrowserChangeCommands(store: store)
        }

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
            .modifier(UITestingAccessibilityEnvironment())
            .onAppear {
                delegate.connect(store: store) {
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
            .task {
                await delegate.prepareForIncomingURLs()
            }
    }
}

private struct UITestingAccessibilityEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        content
            .environment(
                \.browserChangeReduceMotionOverride,
                arguments.contains(
                    "--ui-testing-reduce-motion"
                )
            )
            .transformEnvironment(\.dynamicTypeSize) {
                dynamicTypeSize in
                if arguments.contains(
                    "--ui-testing-large-text"
                ) {
                    dynamicTypeSize = .accessibility3
                }
            }
        #else
        content
        #endif
    }
}
