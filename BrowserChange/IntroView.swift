import Foundation
import SwiftUI

enum IntroPreferences {
    static let key = "hasSeenIntro"

    static var shouldPresent: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--skip-intro")
            || arguments.contains("--ui-testing") {
            return false
        }
        return !UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct IntroView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Linkpick works")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("intro-title")

            Text("Pick the browser for sites with no rule.")
            Text("Add a rule when one site should open somewhere else.")
            Text("Opening a link will not open this window.")

            Button("Got it") {
                IntroPreferences.markSeen()
                onDone()
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("intro-done")
        }
        .padding(24)
        .frame(width: 420)
    }
}
