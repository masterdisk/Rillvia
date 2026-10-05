import AppIntents
import Foundation

extension BrowserLeasePreset: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Lease Duration"
    )

    static let caseDisplayRepresentations: [
        BrowserLeasePreset: DisplayRepresentation
    ] = [
        .fifteenMinutes: "15 minutes",
        .thirtyMinutes: "30 minutes",
        .sixtyMinutes: "60 minutes",
        .untilEnded: "Until ended",
    ]
}

struct OpenLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Link"
    static let description = IntentDescription(
        "Opens an HTTP or HTTPS link in a chosen browser or through active Smart Routing."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @Parameter(title: "Link")
    var url: URL

    @Parameter(
        title: "Browser",
        description: "Leave empty to use active Smart Routing."
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
    static let title: LocalizedStringResource = "Set Routing Profile"
    static let description = IntentDescription(
        "Selects an existing enabled BrowserChange routing profile."
    )
    static var supportedModes: IntentModes {
        [.background, .foreground]
    }

    @Parameter(title: "Routing Profile")
    var profile: RoutingProfileEntity

    @AppDependency
    private var bridge: BrowserChangeIntentBridge

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await bridge.setRoutingProfile(profile.id)
        return .result(dialog: IntentDialog("\(message)"))
    }
}

struct StartBrowserLeaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Browser Lease"
    static let description = IntentDescription(
        "Temporarily routes links to a browser while verified Smart Routing is active and automation leases are allowed."
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
    static let title: LocalizedStringResource = "End Browser Lease"
    static let description = IntentDescription(
        "Ends the current BrowserChange browser lease, if one is active."
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
        "Restores a browser lease change when available, otherwise safely undoes the last Direct browser change."
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
                "Change routing profile with \(.applicationName)",
            ],
            shortTitle: "Set Profile",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: StartBrowserLeaseIntent(),
            phrases: [
                "Borrow a browser with \(.applicationName)",
            ],
            shortTitle: "Borrow Browser",
            systemImageName: "clock.badge.checkmark"
        )
        AppShortcut(
            intent: EndBrowserLeaseIntent(),
            phrases: [
                "End browser lease with \(.applicationName)",
            ],
            shortTitle: "End Lease",
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
