import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.browsers.isEmpty {
                ContentUnavailableView(
                    "No browsers found",
                    systemImage: "globe",
                    description: Text("BrowserChange looks for apps that open http and https links.")
                )
            } else {
                NavigationSplitView {
                    BrowserSidebar()
                        .navigationSplitViewColumnWidth(min: 208, ideal: 232, max: 280)
                } detail: {
                    BrowserWorkspace()
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh browsers", systemImage: "arrow.clockwise") {
                    store.refresh()
                }
                .help("Look for installed browsers again")
            }
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
