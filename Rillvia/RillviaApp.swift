import AppKit
import SwiftUI

struct AppLaunchWindowPolicy {
    private var didFinishLaunching = false
    private var receivedIncomingURLs = false
    private(set) var shouldSuppressMainWindow = false
    private(set) var generation = 0

    mutating func recordIncomingURLs() {
        receivedIncomingURLs = true
        shouldSuppressMainWindow = true
        generation += 1
    }

    mutating func finishLaunching() -> Bool {
        guard !didFinishLaunching else { return false }
        didFinishLaunching = true
        return !receivedIncomingURLs
    }

    mutating func allowWindowPresentation() {
        generation += 1
        shouldSuppressMainWindow = false
    }

    mutating func finishHandlingIncomingURLs(generation: Int) {
        guard generation == self.generation else { return }
        shouldSuppressMainWindow = false
    }

    func shouldOpenOnReopen(hasVisibleWindows: Bool) -> Bool {
        !hasVisibleWindows && !shouldSuppressMainWindow
    }

    func reopenAction(hasVisibleWindows: Bool) -> ReopenAction {
        if shouldSuppressMainWindow {
            return .keepClosed
        }
        if hasVisibleWindows {
            return .leaveAsIs
        }
        return .openAfterURLDeadline
    }
}

enum ReopenAction: Equatable {
    case keepClosed
    case leaveAsIs
    case openAfterURLDeadline
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: BrowserStore?
    var openMainWindow: (() -> Void)?
    private let incomingURLQueue: IncomingURLQueue
    private var launchWindowPolicy = AppLaunchWindowPolicy()
    private var shouldPresentMainWindowWhenConnected = false
    private var isPreparedForIncomingURLs = false
    private var isPreparingForIncomingURLs = false
    private var shortcutController: KeyboardShortcutController?

    override init() {
        self.incomingURLQueue = IncomingURLQueue()
        super.init()
    }

    init(incomingURLQueue: IncomingURLQueue) {
        self.incomingURLQueue = incomingURLQueue
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            launchWindowPolicy.recordIncomingURLs()
            incomingURLQueue.enqueue([url])
        }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateInstallerHelper.recordSuccessfulLaunch()
        if launchWindowPolicy.finishLaunching() {
            shouldPresentMainWindowWhenConnected = true
            presentMainWindowIfPossible()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await prepareForIncomingURLs() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchWindowPolicy.recordIncomingURLs()
        shouldPresentMainWindowWhenConnected = false
        incomingURLQueue.enqueue(urls)
        NSApp.setActivationPolicy(.accessory)
        suppressAccidentalMainWindow()
        scheduleSuppression()
        Task {
            if isPreparedForIncomingURLs {
                await incomingURLQueue.drain()
            } else {
                await prepareForIncomingURLs()
            }
        }
    }

    var isSuppressingMainWindow: Bool {
        launchWindowPolicy.shouldSuppressMainWindow
    }

    func userWantsMainWindow() {
        launchWindowPolicy.allowWindowPresentation()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if !launchWindowPolicy.shouldSuppressMainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        switch launchWindowPolicy.reopenAction(hasVisibleWindows: flag) {
        case .keepClosed:
            suppressAccidentalMainWindow()
        case .leaveAsIs:
            break
        case .openAfterURLDeadline:
            scheduleUserReopen()
        }
        return false
    }

    private func scheduleUserReopen() {
        let generation = launchWindowPolicy.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            guard self.launchWindowPolicy.generation == generation,
                  !self.launchWindowPolicy.shouldSuppressMainWindow else {
                return
            }
            self.userWantsMainWindow()
            self.openMainWindow?()
        }
    }

    private func suppressAccidentalMainWindow() {
        guard launchWindowPolicy.shouldSuppressMainWindow else { return }
        for window in NSApp.windows where window.canBecomeMain || window.title == "Rillvia" {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
    }

    private func scheduleSuppression() {
        let generation = launchWindowPolicy.generation
        for delay in [0.05, 0.2, 0.6, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.launchWindowPolicy.shouldSuppressMainWindow,
                      self.launchWindowPolicy.generation == generation else {
                    return
                }
                self.suppressAccidentalMainWindow()
                if delay == 1.2 {
                    self.launchWindowPolicy.finishHandlingIncomingURLs(
                        generation: generation
                    )
                }
            }
        }
    }

    func connect(
        store: BrowserStore,
        openMainWindow: @escaping () -> Void
    ) {
        self.store = store
        self.openMainWindow = openMainWindow
        if shortcutController == nil, NSClassFromString("XCTestCase") == nil {
            shortcutController = KeyboardShortcutController(store: store) { [weak self] in
                self?.userWantsMainWindow()
                self?.openMainWindow?()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        presentMainWindowIfPossible()
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
        guard let store,
              !isPreparingForIncomingURLs,
              !isPreparedForIncomingURLs else {
            return
        }
        isPreparingForIncomingURLs = true
        await store.activate()
        isPreparedForIncomingURLs = true
        isPreparingForIncomingURLs = false
        await incomingURLQueue.drain()
    }

    func applicationWillTerminate(_ notification: Notification) { shortcutController?.stop() }

    private func presentMainWindowIfPossible() {
        guard shouldPresentMainWindowWhenConnected,
              let openMainWindow else {
            return
        }
        shouldPresentMainWindowWhenConnected = false
        openMainWindow()
    }
}

@main
struct RillviaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: BrowserStore
    @State private var updates: UpdateController
    private let runtime: RillviaAppRuntime

    init() {
        UpdateInstallerHelper.runIfRequested()
        let runtime = RillviaAppRuntime(
            environment: .bootstrap()
        )
        self.runtime = runtime
        RillviaAppShortcuts.updateAppShortcutParameters()
        _store = State(
            initialValue: runtime.store
        )
        _updates = State(initialValue: UpdateController.bootstrap())
    }

    var body: some Scene {
        Window("Rillvia", id: "main") {
            RootView(delegate: appDelegate)
                .environment(store)
                .environment(updates)
        }
        .defaultSize(width: UITestingMenuPreview.enabled ? 600 : UITestingWindowSize.minimum ? 820 : 940,
            height: UITestingMenuPreview.enabled ? 640 : UITestingWindowSize.minimum ? 580 : 680)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .commands {
            RillviaCommands(store: store, updates: updates, delegate: appDelegate)
        }

        MenuBarExtra {
            MenuPanel(delegate: appDelegate)
                .environment(store)
                .environment(updates)
                .modifier(UITestingAccessibilityEnvironment())
        } label: {
            ConnectedMenuBarLabel(
                delegate: appDelegate,
                store: store
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct ConnectedMenuBarLabel: View {
    var delegate: AppDelegate
    var store: BrowserStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(
            image: AppBrand.menuImage,
            name: AppBrand.name
        )
        .onAppear {
            delegate.connect(store: store) {
                delegate.userWantsMainWindow()
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Task {
                await delegate.prepareForIncomingURLs()
            }
        }
    }
}

private enum UITestingMenuPreview {
    static var enabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--ui-testing-menu-preview")
        #else
        return false
        #endif
    }
}

private struct RootView: View {
    var delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(BrowserStore.self) private var store
    @State private var showIntro = false
    @AppStorage("appearance", store: AppPreferences.defaults) private var appearance = "system"
    @AppStorage("textScale", store: AppPreferences.defaults) private var textScale = 1.0

    var body: some View {
        Group {
            // Capture the real menu component with isolated handlers when status-bar automation is unavailable.
            if UITestingMenuPreview.enabled {
                MenuPanel(delegate: delegate)
            } else {
                ContentView()
            }
        }
            .appFont(size: 15)
            .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
            .accentColor(AppColors.actionTint)
            .modifier(UITestingAccessibilityEnvironment())
            .environment(\.rillviaTextScale, textScale)
            .sheet(isPresented: $showIntro) {
                IntroView {
                    showIntro = false
                }.environment(store)
            }
            .onAppear {
                delegate.connect(store: store) {
                    delegate.userWantsMainWindow()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                if !delegate.isSuppressingMainWindow {
                    showIntro = IntroPreferences.shouldPresent
                }
            }
            .task {
                await delegate.prepareForIncomingURLs()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-design-fixture") {
                    store.workspace.previewInput = "https://github.com/openai"
                    store.stageAirlock(text: store.workspace.previewInput)
                    store.workspace.markPreview(input: store.workspace.previewInput, revision: store.revision)
                }
                #endif
            }
    }
}

private struct UITestingAccessibilityEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        content
            .environment(\.rillviaReduceTransparencyOverride, arguments.contains("--ui-testing-reduce-transparency"))
            .environment(\.rillviaIncreaseContrastOverride, arguments.contains("--ui-testing-increased-contrast"))
            .transformEnvironment(\.rillviaTextScale) { value in
                if arguments.contains("--ui-testing-large-text") { value = 2 }
            }
            .environment(
                \.rillviaReduceMotionOverride,
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

private enum UITestingWindowSize {
    static var minimum: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-testing-minimum-size")
        #else
        false
        #endif
    }
}
