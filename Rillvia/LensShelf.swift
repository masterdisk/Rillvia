import SwiftUI

struct BrowserSidebar: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.rillviaTextScale) private var textScale
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
              VStack(alignment: .leading, spacing: 3) {
                navigation("Overview", icon: "house", key: "⌘1", destination: .overview)
                navigation("Preview a link", icon: "link", key: "⌘2", destination: .airlock)
                navigation("Rules", icon: "arrow.triangle.branch", key: "⌘3", destination: .rules)
                navigation("Browsers", icon: "safari", key: "⌘4", destination: .direct)
                if store.workspaceDestination == .rules || store.workspaceDestination == .profiles {
                    Section("Rule sets") {
                        ruleSet("Shared rules", id: nil, icon: "square.3.layers.3d")
                        ForEach(store.routingConfiguration.profiles) { profile in
                            ruleSet(profile.name, id: profile.id, icon: "folder")
                        }
                        Button("Manage rule sets", systemImage: "slider.horizontal.3") {
                            store.workspace.request { store.workspace.showRuleSets = true }
                        }.buttonStyle(.plain).foregroundStyle(AppColors.secondaryText)
                            .accessibilityIdentifier("nav-profiles")
                    }
                }
              }.padding(12)
            }
            .accessibilityIdentifier("browser-sidebar")
            Divider().padding(.horizontal, 14)
            navigation("Settings", icon: "gearshape", key: "⌘,", destination: .settings)
                .padding(12)
        }
        .background(.regularMaterial)
    }

    private func navigation(_ title: String, icon: String, key: String, destination: WorkspaceDestination) -> some View {
        Button { store.navigate(to: destination) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).frame(width: 23).foregroundStyle(.blue).accessibilityHidden(true)
                Text(title).appFont(size: 14, weight: store.workspaceDestination == destination ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                Spacer(minLength: 3)
                if textScale <= 1.25 { ShortcutHint(keys: key) }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(store.workspaceDestination == destination ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .accessibilityIdentifier("nav-\(destination.rawValue)")
            .accessibilityAddTraits(store.workspaceDestination == destination ? .isSelected : [])
    }

    private func ruleSet(_ name: String, id: UUID?, icon: String) -> some View {
        Button {
            store.workspace.request {
                store.workspace.didChooseRuleSet = true
                store.workspace.browsedProfileID = id
                store.workspace.draft = nil
                store.workspace.savedDraft = nil
                store.workspace.ruleSearch = ""
                store.workspaceDestination = .rules
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 23).foregroundStyle(AppColors.secondaryText)
                Text(name).fontWeight(store.workspace.browsedProfileID == id ? .semibold : .regular)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if id != nil, store.routingConfiguration.activeProfileID == id {
                    Image(systemName: "circle.fill").appFont(size: 7).foregroundStyle(.green).accessibilityLabel("Active rule set")
                }
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Browse \(name). The active rule set stays the same.")
    }
}

struct BrowserWorkspace: View {
    @Environment(BrowserStore.self) private var store
    var body: some View {
        Group {
            switch store.workspaceDestination {
            case .overview: OverviewView()
            case .airlock: LinkAirlockView()
            case .rules: RulesView()
            case .direct: BrowsersView()
            case .profiles: ProfilesView()
            case .settings: AppSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
