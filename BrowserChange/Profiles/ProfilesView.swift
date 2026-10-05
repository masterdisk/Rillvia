import SwiftUI

struct ProfilesView: View {
    @Environment(BrowserStore.self) private var store
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Routing profiles")
                        .font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("profiles-title")
                    Text(
                        "Only the selected profile participates in routing. Global rules always remain available."
                    )
                    .foregroundStyle(.secondary)
                }

                HStack {
                    TextField("Profile name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create profile") {
                        if store.createProfile(named: newName) != nil {
                            newName = ""
                        }
                    }
                    .buttonStyle(.glassProminent)
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
                            Text("Global rules only")
                                .font(.body.weight(.semibold))
                            Text("No profile-specific rules are active.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.routingConfiguration.activeProfileID == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    .quaternary.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 12)
                )

                ForEach(store.routingConfiguration.profiles) { profile in
                    ProfileRow(profile: profile)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
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
                TextField("Profile name", text: $name)
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

            HStack {
                if store.routingConfiguration.activeProfileID == profile.id {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Inactive")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let ruleCount = store.routingConfiguration.domainRules.filter {
                    $0.profileID == profile.id
                }.count
                Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }
}
