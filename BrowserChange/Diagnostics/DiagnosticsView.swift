import SwiftUI

struct DiagnosticsView: View {
    @Environment(BrowserStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        let snapshot = store.diagnosticsSnapshot

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("View Source")
                    .font(.system(size: 28, weight: .semibold))
                    .accessibilityIdentifier("diagnostics-title")
                Text(
                    "A read-only, redacted snapshot of BrowserChange state."
                )
                .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(snapshot.visibleText)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .quaternary.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityIdentifier(
                        "diagnostics-snapshot"
                    )
                    .accessibilityLabel(snapshot.visibleText)
            }

            HStack {
                Button(
                    "Copy Redacted Snapshot",
                    systemImage: didCopy
                        ? "checkmark"
                        : "doc.on.doc"
                ) {
                    didCopy = snapshot.copy()
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("copy-diagnostics")
                .accessibilityValue(
                    didCopy ? "Copied" : "Not copied"
                )

                if didCopy {
                    Text("Copied")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(
                            "diagnostics-copy-status"
                        )
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(
            minWidth: 560,
            idealWidth: 720,
            minHeight: 480,
            idealHeight: 620
        )
    }
}
