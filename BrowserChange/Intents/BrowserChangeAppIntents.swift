import AppIntents
import Foundation

extension BrowserLeasePreset: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "How long"
    )

    static let caseDisplayRepresentations: [
        BrowserLeasePreset: DisplayRepresentation
    ] = [
        .fifteenMinutes: "15 minutes",
        .thirtyMinutes: "30 minutes",
        .sixtyMinutes: "60 minutes",
        .untilEnded: "Until I stop",
    ]
}

struct OpenLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Link"
    static let description = IntentDescription(
        "Opens an HTTP or HTTPS link in a chosen browser, or through Linkpick when no browser is chosen."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @Parameter(title: "Link")
    var url: URL

    @Parameter(
        title: "Browser",
        description: "Leave empty to use Linkpick."
    )
    var browser: InstalledBrowserEntity?

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.openLink(
            url,
            browserID: browser?.id
        )
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct SetRoutingProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Rule Set"
    static let description = IntentDescription(
        "Selects an existing enabled Linkpick rule set."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @Parameter(title: "Rule set")
    var profile: RoutingProfileEntity

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.setRoutingProfile(profile.id)
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct StartBrowserLeaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Another Browser"
    static let description = IntentDescription(
        "Sends links to one browser for a while. Linkpick must be sending links, and Shortcuts must be allowed to switch browsers."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @Parameter(title: "Browser")
    var browser: InstalledBrowserEntity

    @Parameter(title: "Duration")
    var duration: BrowserLeasePreset

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.startBrowserLease(
            browserID: browser.id,
            preset: duration
        )
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct EndBrowserLeaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Temporary Browser"
    static let description = IntentDescription(
        "Stops the temporary browser, if one is on."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.endBrowserLease()
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct RestorePreviousBrowserIntent: AppIntent {
    static let title: LocalizedStringResource =
        "Restore Previous Browser"
    static let description = IntentDescription(
        "Restores a temporary browser when one can be restored. Otherwise undoes the last usual-browser change."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.restorePreviousBrowser()
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct BrowserChangeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLinkIntent(),
            phrases: [
                "Open a link with \(.applicationName)",
            ],
            shortTitle: "Open Link",
            systemImageName: "link"
        )
        AppShortcut(
            intent: SetRoutingProfileIntent(),
            phrases: [
                "Change rule set with \(.applicationName)",
            ],
            shortTitle: "Set Rule Set",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: StartBrowserLeaseIntent(),
            phrases: [
                "Use another browser with \(.applicationName)",
            ],
            shortTitle: "Use Another Browser",
            systemImageName: "clock.badge.checkmark"
        )
        AppShortcut(
            intent: EndBrowserLeaseIntent(),
            phrases: [
                "Stop the temporary browser with \(.applicationName)",
            ],
            shortTitle: "Stop Temporary Browser",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: RestorePreviousBrowserIntent(),
            phrases: [
                "Restore previous browser with \(.applicationName)",
            ],
            shortTitle: "Restore Browser",
            systemImageName: "arrow.uturn.backward"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .purple
}
