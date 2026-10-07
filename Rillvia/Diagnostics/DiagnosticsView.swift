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
                    .appFont(size: 28, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("diagnostics-title")
                Text(
                    "A read-only, redacted snapshot of Rillvia state."
                )
                .foregroundStyle(AppColors.secondaryText)
            }

            ScrollView {
                Text(snapshot.visibleText)
                    .appFont(.body, design: .monospaced)
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

            ViewThatFits(in: .horizontal) {
                HStack {
                    copyButton
                    copyStatus
                    Spacer()
                    doneButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    copyButton
                    copyStatus
                    HStack { Spacer(); doneButton }
                }
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

    private var copyButton: some View {
        Button(
            "Copy Redacted Snapshot",
            systemImage: didCopy ? "checkmark" : "doc.on.doc"
        ) {
            didCopy = store.diagnosticsSnapshot.copy()
        }
        .modifier(AccessibleGlassStyle(prominent: true))
        .accessibilityIdentifier("copy-diagnostics")
        .accessibilityValue(didCopy ? "Copied" : "Not copied")
    }

    @ViewBuilder private var copyStatus: some View {
        if didCopy {
            Text("Copied")
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityIdentifier("diagnostics-copy-status")
        }
    }

    private var doneButton: some View {
        Button("Done") { dismiss() }
            .keyboardShortcut(.cancelAction)
    }
}
