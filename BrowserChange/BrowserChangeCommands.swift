import SwiftUI

@MainActor
struct BrowserChangeCommands: Commands {
    let store: BrowserStore

    var body: some Commands {
        CommandMenu("Tools") {
            Button("View Source Diagnostics…") {
                store.openDiagnostics()
            }
            .keyboardShortcut(
                "u",
                modifiers: [.command, .option]
            )

            Button("Preview Time Machine…") {
                store.openTimeMachine()
            }
            .keyboardShortcut(
                "t",
                modifiers: [.command, .option]
            )

            Divider()

            Button("Living Browser Hall…") {
                store.showHall = true
            }
        }
    }
}
