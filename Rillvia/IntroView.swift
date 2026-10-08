import Foundation
import SwiftUI

enum AppPreferences {
    static let defaults: UserDefaults = {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") || NSClassFromString("XCTestCase") != nil {
            return UserDefaults(suiteName: "Rillvia-UITests-\(ProcessInfo.processInfo.processIdentifier)")!
        }
        let defaults = UserDefaults.standard
        AppIdentityMigration.migratePreferences(to: defaults, legacyValues: defaults.persistentDomain(forName: AppIdentityMigration.legacyBundleIdentifier) ?? [:])
        return defaults
    }()
}

enum IntroPreferences {
    static let key = "hasSeenIntro"
    static var shouldPresent: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--skip-intro") || arguments.contains("--ui-testing") { return false }
        return !AppPreferences.defaults.bool(forKey: key)
    }
    static func markSeen() { AppPreferences.defaults.set(true, forKey: key) }
}

struct IntroView: View {
    @Environment(BrowserStore.self) private var store
    var onDone: () -> Void
    @State private var step = 0
    @State private var fallbackID = ""
    @State private var sampleURL = "https://github.com"
    private let steps = ["Your links, your way", "Choose where other links go", "Give a site its own browser", "Try it before opening", "Switch for a little while"]
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack {
                Image("AppLogo").resizable().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
                Spacer()
                Text("\(step + 1) of \(steps.count)").appFont(.callout).foregroundStyle(AppColors.secondaryText)
            }
            ScrollView {
            VStack(alignment: .leading, spacing: 23) {
            PageHeading(title: steps[step], identifier: "intro-title")
            Group {
                switch step {
                case 0:
                    Text("Rillvia opens links in the browser you choose for each site. Everything happens on your Mac.")
                    Text("Opening a link stays quiet. This window appears when you ask for it.").foregroundStyle(AppColors.secondaryText)
                case 1:
                    Text("Other links is the browser used when no rule matches. Choose it in Overview.")
                    RoutingStatus()
                    if !store.isSmartRoutingActive {
                        Picker("Other links", selection: $fallbackID) {
                            ForEach(store.externalBrowsers) { Text($0.name).tag($0.id) }
                        }
                        Button("Turn on rules") {
                            Task {
                                await store.enableSmartRouting()
                                if store.isSmartRoutingActive, let chosen = store.externalBrowsers.first(where: { $0.id == fallbackID }) { await store.makeDefault(chosen) }
                            }
                        }.modifier(AccessibleButtonStyle(prominent: true)).disabled(store.isSwitching)
                        Text("macOS will ask to let Rillvia handle web links. You can turn rules off at any time.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    } else { Text("Rules are already on. Your saved choices are ready.").foregroundStyle(AppColors.secondaryText) }
                case 2:
                    Text("In Rules, add a domain such as github.com and choose a browser. Include subdomains when you want docs.example.com to follow example.com.")
                    Text("Use rule sets for Work or Personal. Shared rules apply alongside the active set.").foregroundStyle(AppColors.secondaryText)
                case 3:
                    Text("Preview shows the browser and rule before opening. It does not visit the link.")
                    AppTextField("A link to try", text: $sampleURL)
                    Button("Preview this link") {
                        store.workspace.previewInput = sampleURL
                        store.stageAirlock(text: sampleURL)
                        store.workspace.markPreview(input: sampleURL, revision: store.revision)
                        store.workspaceDestination = .airlock
                        finish()
                    }.modifier(AccessibleButtonStyle())
                default:
                    Text("Use one browser for 15, 30, or 60 minutes—or until you stop. Your rules resume when the temporary choice ends.")
                    Text("Find it in the menu bar or press ⌘T. Press ⌘1–4 to move between pages, and ⌘/ for all keyboard shortcuts.").foregroundStyle(AppColors.secondaryText)
                }
            }.fixedSize(horizontal: false, vertical: true)
            StoreNotice()
            }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(step == 0 ? "Skip tour" : "Back") { if step == 0 { finish() } else { step -= 1 } }.modifier(AccessibleButtonStyle())
                Spacer()
                Button(step == steps.count - 1 ? "Get started" : "Continue") { if step == steps.count - 1 { finish() } else { step += 1 } }
                    .modifier(AccessibleButtonStyle(prominent: true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("intro-done")
            }
        }.appFont(size: 15).padding(30).frame(width: 530, height: 490)
        .onAppear { fallbackID = store.smartFallbackBrowser?.id ?? store.defaultBundleID ?? store.externalBrowsers.first?.id ?? "" }
    }
    private func finish() { IntroPreferences.markSeen(); onDone() }
}
