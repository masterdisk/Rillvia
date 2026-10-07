import SwiftUI

struct ProfilesView: View {
    @Environment(BrowserStore.self) private var store
    @State private var newName = ""

    var body: some View {
        RillviaPage(title: "Rule sets", identifier: "profiles-title") {
            Section {
                HStack {
                    TextField("Rule set name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create rule set") {
                        if store.createProfile(named: newName) != nil {
                            newName = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        newName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }

                Button {
                    _ = store.selectProfile(nil)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Everywhere")
                                .appFont(.body, weight: .semibold)
                            Text(ruleSites(profileID: nil, in: store))
                                .appFont(.caption)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        Spacer()
                        if store.routingConfiguration.activeProfileID == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityLabel("In use")
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                ForEach(store.routingConfiguration.profiles) { profile in
                    ProfileRow(profile: profile)
                }
            }
        }
    }
}

private struct ProfileRow: View {
    @Environment(BrowserStore.self) private var store
    var profile: RoutingProfile
    @State private var name: String

    init(profile: RoutingProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Rule set name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Button("Rename") {
                    _ = store.renameProfile(profile.id, to: name)
                }
                .disabled(
                    name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || name == profile.name
                )

                Button("Select") {
                    _ = store.selectProfile(profile.id)
                }
                .disabled(
                    store.routingConfiguration.activeProfileID == profile.id
                )

                Button("Delete", role: .destructive) {
                    _ = store.deleteProfile(profile.id)
                }
            }

            Text(ruleSites(profileID: profile.id, in: store))
                .appFont(.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private func ruleSites(profileID: UUID?, in store: BrowserStore) -> String {
    let names = store.routingConfiguration.domainRules
        .filter { $0.profileID == profileID }
        .map(\.domain)
    if names.isEmpty {
        return profileID == nil
            ? "No rules yet. New rules go here unless you pick another set."
            : "No rules in this set."
    }
    return names.joined(separator: ", ")
}
