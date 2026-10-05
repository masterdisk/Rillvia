import SwiftUI

struct PreviewTimeMachineView: View {
    @Environment(BrowserStore.self) private var store
    @State private var selectedSnapshotID: UUID?
    @State private var input = ""
    @State private var evaluation: HistoricalRoutingEvaluation?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Preview Time Machine")
                    .font(.system(size: 28, weight: .semibold))
                    .accessibilityIdentifier("time-machine-title")
                Text(
                    "Inspect past routing configurations without changing the present."
                )
                .foregroundStyle(.secondary)
            }

            if store.timeMachineModel.snapshots.isEmpty {
                ContentUnavailableView(
                    "No configuration history",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Configuration changes will appear here after they are saved."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    snapshotList
                    snapshotDetail
                }
            }

            Divider()

            HStack {
                Button(
                    "Return to Now",
                    systemImage: "arrow.uturn.forward"
                ) {
                    store.returnToNow()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("return-to-now")

                Spacer()

                Text("No rollback is performed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(
            minWidth: 680,
            idealWidth: 820,
            minHeight: 500,
            idealHeight: 620
        )
        .onAppear {
            selectedSnapshotID =
                store.timeMachineModel.snapshots.first?.id
        }
        .onChange(of: selectedSnapshotID) {
            evaluation = nil
        }
    }

    private var snapshotList: some View {
        List(
            store.timeMachineModel.snapshots,
            selection: $selectedSnapshotID
        ) { snapshot in
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    snapshot.recordedAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                .font(.callout.weight(.semibold))
                .monospacedDigit()

                Text(snapshot.changes.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .padding(.vertical, 4)
            .tag(snapshot.id)
            .accessibilityLabel(
                snapshot.recordedAt.formatted(
                    date: .complete,
                    time: .standard
                )
            )
            .accessibilityValue(
                snapshot.changes.joined(separator: " ")
            )
        }
        .frame(minWidth: 260, idealWidth: 300)
        .accessibilityIdentifier("time-machine-snapshots")
    }

    private var snapshotDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = selectedSnapshot {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Configuration at this moment")
                        .font(.headline)
                    Text(
                        snapshot.changes.joined(separator: "\n")
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Test a URL")
                        .font(.headline)
                    TextField(
                        "https://example.com",
                        text: $input
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(
                        "URL to evaluate against this historical configuration"
                    )
                    .accessibilityIdentifier("time-machine-url")

                    Text(
                        "The URL is evaluated in memory. It is never opened or saved."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Evaluate", systemImage: "clock.badge.questionmark") {
                        evaluation = store.evaluateHistoricalURL(
                            input,
                            snapshotID: snapshot.id
                        )
                    }
                    .disabled(
                        input.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                    .accessibilityIdentifier(
                        "time-machine-evaluate"
                    )
                }

                if let evaluation {
                    VStack(alignment: .leading, spacing: 4) {
                        if let targetName = evaluation.targetName {
                            Text(targetName)
                                .font(.title3.weight(.semibold))
                                .accessibilityIdentifier(
                                    "historical-result-target"
                                )
                                .accessibilityLabel(targetName)
                        }
                        Text(evaluation.reason)
                            .foregroundStyle(.secondary)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .accessibilityIdentifier(
                                "historical-result-reason"
                            )
                            .accessibilityLabel(
                                evaluation.reason
                            )
                    }
                    .padding(14)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background(
                        .quaternary.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityElement(
                        children: .contain
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(
            minWidth: 320,
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }

    private var selectedSnapshot:
        HistoricalConfigurationSnapshot? {
        guard let selectedSnapshotID else {
            return nil
        }
        return store.timeMachineModel.snapshots.first {
            $0.id == selectedSnapshotID
        }
    }
}
