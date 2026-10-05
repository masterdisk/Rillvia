import SwiftUI

struct FutureFeaturesView: View {
    @Environment(BrowserStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What could come next")
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("future-features-title")
                    Text("Ideas based on the browsers already on this Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Preview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            VStack(spacing: 0) {
                FutureFeatureRow(
                    symbol: "arrow.triangle.branch",
                    title: "Open each site in the right browser",
                    detail: routeDetail
                )
                Divider()
                    .padding(.leading, 34)
                FutureFeatureRow(
                    symbol: "person.2",
                    title: "Keep work and personal browsing separate",
                    detail: profileDetail
                )
                Divider()
                    .padding(.leading, 34)
                FutureFeatureRow(
                    symbol: "moon.stars",
                    title: "Switch when the workday ends",
                    detail: quietHoursDetail,
                    action: {
                        store.tapMoon()
                    }
                )
            }

            Text("These examples do not change where links open yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var routeDetail: String {
        guard let route = store.board.routes.first(where: { $0.id == "github" })
            ?? store.board.routes.first else {
            return "Send specific websites to the browser you choose."
        }
        return "\(route.match) would open in \(route.browserName)."
    }

    private var profileDetail: String {
        let work = store.board.profiles.first(where: { $0.id == "work" })
        let personal = store.board.profiles.first(where: { $0.id == "personal" })
        guard let work, let personal else {
            return "Give work and personal links different homes."
        }
        return "Work would use \(work.browserName); personal would use \(personal.browserName)."
    }

    private var quietHoursDetail: String {
        store.board.nowLine.isEmpty
            ? "Choose a different browser for evenings and weekends."
            : store.board.nowLine
    }
}

private struct FutureFeatureRow: View {
    var symbol: String
    var title: String
    var detail: String
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
                .onTapGesture {
                    action?()
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 12)
    }
}
