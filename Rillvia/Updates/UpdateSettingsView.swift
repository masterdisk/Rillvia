import AppKit
import SwiftUI

struct UpdateSettingsView: View {
    @Environment(UpdateController.self) private var updates
    @Environment(BrowserStore.self) private var store
    @State private var confirmInstall = false
    @Environment(\.rillviaTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rillvia \(updates.installedVersion)").fontWeight(.medium)
                    Text("Check for a new version when you're ready.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button("Check for updates") { Task { await updates.check() } }
                    .modifier(AccessibleGlassStyle()).disabled(updates.phase.isBusy).accessibilityIdentifier("check-for-updates")
            }
            switch updates.phase {
            case .idle: EmptyView()
            case .checking: busy("Checking GitHub releases…")
            case .current: Text("You're up to date.").accessibilityIdentifier("update-status")
            case .noRelease: Text("No published release yet.").accessibilityIdentifier("update-status")
            case .available(let release):
                Text("Rillvia \(release.version) is available.").fontWeight(.medium).accessibilityIdentifier("update-status")
                HStack(spacing: 12) {
                    if release.asset != nil {
                        Button("Download update") { Task { await updates.download() } }.modifier(AccessibleGlassStyle(prominent: true)).accessibilityIdentifier("download-update")
                    } else { Text("The installer is not ready yet.").appFont(.callout).foregroundStyle(AppColors.secondaryText) }
                    Button("Release notes") { NSWorkspace.shared.open(release.url) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                }
            case .downloading: busy("Downloading and verifying the update…")
            case .ready(let release, let file):
                Text("Rillvia \(release.version) is ready to install.").fontWeight(.medium).accessibilityIdentifier("update-status")
                if textScale > 1.25 { VStack(alignment: .leading, spacing: 12) { installActions(file) } }
                else { HStack(spacing: 12) { installActions(file) } }
                if store.workspace.hasUnsavedRule {
                    Text("Save or discard your rule changes before restarting.").appFont(.callout).foregroundStyle(AppColors.secondaryText)
                }
            case .installing: busy("Installing. Rillvia will restart…")
            case .failed(let message):
                Text(message).appFont(.callout).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("update-status")
                if let file = updates.downloadedInstaller {
                    Button("Open installer") { NSWorkspace.shared.open(file) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
                }
            }
            HStack(spacing: 12) {
                if let checked = updates.lastChecked {
                    Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))").appFont(.caption).foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Open Releases") { NSWorkspace.shared.open(UpdateSource.releasesURL) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
            }
        }
        .onChange(of: updates.phase) { _, phase in
            switch phase {
            case .current: AccessibilityAnnouncement.post("You're up to date.")
            case .noRelease: AccessibilityAnnouncement.post("No published release yet.")
            case .available(let release): AccessibilityAnnouncement.post("Rillvia \(release.version) is available.")
            case .ready(let release, _): AccessibilityAnnouncement.post("Rillvia \(release.version) is ready to install.")
            case .failed(let message): AccessibilityAnnouncement.post(message)
            default: break
            }
        }
        .confirmationDialog("Install the update and restart Rillvia?", isPresented: $confirmInstall, titleVisibility: .visible) {
            Button("Install and restart") { Task { await updates.installAndRestart() } }
            Button("Later", role: .cancel) {}
        } message: { Text("Your saved rules and shortcuts will stay in place.") }
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).appFont(.callout).foregroundStyle(AppColors.secondaryText) }
            .accessibilityIdentifier("update-status")
    }
    @ViewBuilder private func installActions(_ file: URL) -> some View {
        Button("Install and restart") { confirmInstall = true }.modifier(AccessibleGlassStyle(prominent: true))
            .disabled(store.workspace.hasUnsavedRule || store.isSwitching || store.shortcuts.isEditing)
            .accessibilityIdentifier("install-update")
        Button("Open installer") { NSWorkspace.shared.open(file) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(.link).tint(AppColors.linkText).accentColor(AppColors.linkText)
    }
}
