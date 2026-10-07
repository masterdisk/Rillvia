import SwiftUI

struct RillviaPage<Content: View>: View {
    var title: String
    var identifier: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            Section {
                Text(title)
                    .appFont(.title2, weight: .semibold)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier)
            }
            content()
        }
        .formStyle(.grouped)
    }
}

struct CallSheetRow: View {
    var title: String
    var detail: String
    var trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .appFont(.body)
                if !detail.isEmpty {
                    Text(detail)
                        .appFont(.subheadline)
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
            Spacer(minLength: 16)
            if !trailing.isEmpty {
                Text(trailing)
                    .appFont(.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 11)
    }
}
