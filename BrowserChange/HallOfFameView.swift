import SwiftUI

struct HallOfFameView: View {
    var model: LivingBrowserHallModel
    @Environment(\.dismiss) private var dismiss
    @State private var cometLine = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("The Living Browser Hall")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier(
                            "living-hall-title"
                        )
                    Text(
                        "Browser history, illuminated by what is installed on this Mac."
                    )
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.eras) { era in
                        HStack(alignment: .top, spacing: 12) {
                            Image(
                                systemName: era.isRepresented
                                    ? "lightbulb.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                era.isRepresented
                                    ? Color.yellow
                                    : Color.secondary
                            )
                            .frame(width: 18)
                            .accessibilityHidden(true)

                            VStack(
                                alignment: .leading,
                                spacing: 3
                            ) {
                                Text(era.year)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()

                                if era.name
                                    == "Netscape Navigator" {
                                    Button(era.name) {
                                        cometLine = true
                                    }
                                    .buttonStyle(.plain)
                                    .font(.headline)
                                    .accessibilityIdentifier(
                                        "hall-era-netscape"
                                    )
                                } else {
                                    Text(era.name)
                                        .font(.headline)
                                }

                                Text(era.line)
                                    .foregroundStyle(.secondary)

                                if era.isRepresented {
                                    Label(
                                        "Represented here by \(era.representedBy.joined(separator: ", "))",
                                        systemImage: "macbook"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                if cometLine
                                    && era.name
                                        == "Netscape Navigator" {
                                    Text(
                                        "The comet still has a name."
                                    )
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier(
                                        "netscape-footnote"
                                    )
                                }
                            }
                        }
                        .accessibilityElement(
                            children: .contain
                        )
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("This Mac")
                            .font(.headline)
                        Text(model.todayLine)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }

                    ForEach(model.browsers) { browser in
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(browser.name)
                                    .font(.body.weight(.semibold))
                                    .accessibilityIdentifier(
                                        "hall-browser-\(browser.id)"
                                    )
                                Spacer()
                                Text("Version \(browser.version)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(
                                browser.status,
                                id: \.self
                            ) { status in
                                Label(
                                    status,
                                    systemImage: status
                                        == "Temporary browser"
                                        ? "clock.badge.checkmark"
                                        : "checkmark.circle"
                                )
                                .font(.caption)
                            }

                            Text(
                                "\(browser.enabledRuleCount) enabled \(browser.enabledRuleCount == 1 ? "rule" : "rules")"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            .quaternary.opacity(0.25),
                            in: RoundedRectangle(
                                cornerRadius: 10
                            )
                        )
                        .accessibilityElement(
                            children: .contain
                        )
                    }
                }

                Button("Back to the present") {
                    dismiss()
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            minWidth: 540,
            idealWidth: 660,
            minHeight: 540,
            idealHeight: 700
        )
    }
}
