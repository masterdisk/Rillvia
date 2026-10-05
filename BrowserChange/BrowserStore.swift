import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BrowserStore {
    var selectedID: String?
    var selectedRouteID: String?
    var selectedProfileID: String?
    var showHall = false

    private(set) var browsers: [InstalledBrowser] = []
    private(set) var switchable: [InstalledBrowser] = []
    private(set) var defaultBundleID: String?
    private(set) var message: String?
    private(set) var isSwitching = false
    private(set) var revision = 0
    private(set) var installedCount = 0
    private(set) var board = PreviewBoard.empty

    private var installed: [InstalledBrowser] = []
    private var icons: [String: NSImage] = [:]
    private var lynxVisible = false
    private var quipIndex = 0
    private var titleGate = TapGate(threshold: 5, interval: 1.5)
    private var moonGate = TapGate(threshold: 4, interval: 2)
    private var lynxKeys = CharacterSequence(target: "lynx", gap: 1.2)

    private let quips: [(String) -> String] = [
        { "\($0) is already the default. The others can wait." },
        { _ in "Still this one. Consistency is a feature." },
        { _ in "macOS agrees with you." },
        { _ in "No change. A peaceful outcome." },
    ]

    init() {
        reload()
    }

    var defaultBrowserName: String {
        switchable.first { $0.id == defaultBundleID }?.name ?? "BrowserChange"
    }

    var menuBarSource: NSImage {
        if let id = defaultBundleID, let icon = icons[id] {
            return icon
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: "BrowserChange")
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    func icon(for browser: InstalledBrowser) -> NSImage {
        if browser.isImaginary {
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: browser.name)
                ?? NSImage()
        }
        return icons[browser.id] ?? NSWorkspace.shared.icon(forFile: browser.iconURL.path)
    }

    func refresh() {
        guard !isSwitching else { return }
        reload()
    }

    func selectBrowser(_ id: String) {
        selectedID = id
    }

    func tapTitle(at date: Date = .now) {
        if titleGate.tap(at: date) {
            showHall = true
        }
    }

    func tapMoon(at date: Date = .now) {
        if moonGate.tap(at: date) {
            message = "The browsers logged off. You do not have to."
        }
    }

    func noteTyping(_ raw: String, at date: Date = .now) {
        guard lynxKeys.consume(raw, at: date) else { return }
        lynxVisible.toggle()
        message = lynxVisible
            ? "Lynx sat down at the end of the shelf."
            : "Lynx went back to the terminal."
        if !lynxVisible, selectedID == ImaginaryBrowser.lynx.id {
            selectedID = defaultBundleID ?? installed.first?.id
        }
        publish()
    }

    func copyIdentity(of browser: InstalledBrowser) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(browser.id, forType: .string)
        message = "Copied \(browser.id)"
    }

    func makeDefault(_ browser: InstalledBrowser) async {
        guard !isSwitching else { return }
        if browser.isImaginary {
            message = "Lynx lives in a terminal. This Mac wants a window."
            return
        }
        if browser.id == defaultBundleID {
            message = quips[quipIndex % quips.count](browser.name)
            quipIndex += 1
            return
        }

        isSwitching = true
        message = "Waiting for macOS to confirm."
        defer { isSwitching = false }

        // Launch Services keeps a handler per scheme. Both have to move together.
        for scheme in ["https", "http"] {
            do {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: browser.appURL,
                    toOpenURLsWithScheme: scheme
                )
            } catch {
                reload()
                if defaultBundleID == browser.id {
                    message = "\(browser.name) is now the default."
                } else {
                    message = DefaultBrowserFailure.message(for: error)
                }
                return
            }
        }

        reload()
        if defaultBundleID == browser.id {
            message = "\(browser.name) is now the default."
        } else {
            message = "macOS kept the previous default."
        }
    }

    private func reload() {
        installed = BrowserLookup.installedBrowsers()
        defaultBundleID = BrowserLookup.defaultBundleID()
        publish()
    }

    private func publish(now: Date = .now) {
        installedCount = installed.count
        switchable = BrowserOrder.shelf(installed, defaultID: defaultBundleID)
        var display = installed
        if lynxVisible {
            display.append(ImaginaryBrowser.lynx)
        }
        let ordered = BrowserOrder.shelf(display, defaultID: defaultBundleID)
        browsers = ordered
        if let selectedID, ordered.contains(where: { $0.id == selectedID }) {
            self.selectedID = selectedID
        } else {
            selectedID = defaultBundleID ?? ordered.first?.id
        }

        let nextBoard = PreviewBoard.make(browsers: installed, defaultID: defaultBundleID, now: now)
        board = nextBoard
        if !nextBoard.routes.contains(where: { $0.id == selectedRouteID }) {
            selectedRouteID = nextBoard.routes.first?.id
        }
        if !nextBoard.profiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = nextBoard.profiles.first { $0.suggestedNow }?.id ?? nextBoard.profiles.first?.id
        }

        icons = Dictionary(uniqueKeysWithValues: installed.map { browser in
            (browser.id, NSWorkspace.shared.icon(forFile: browser.iconURL.path))
        })
        revision += 1
    }
}
