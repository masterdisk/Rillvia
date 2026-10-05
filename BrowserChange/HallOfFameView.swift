import SwiftUI

struct HallOfFameView: View {
    var browserCount: Int
    @Environment(\.dismiss) private var dismiss
    @State private var cometLine = false

    private let eras: [(year: String, name: String, line: String)] = [
        ("1993", "NCSA Mosaic", "The web got a window."),
        ("1994", "Netscape Navigator", "Browsing became a product."),
        ("1995", "Internet Explorer", "It won, and then it stayed."),
        ("2003", "Safari", "The browser that ships with the Mac."),
        ("2008", "Chrome", "A new one, and then a crowd of them."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("A short history of choosing")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 16) {
                ForEach(eras, id: \.year) { era in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(era.year)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(era.name)
                            .font(.headline)
                            .onTapGesture {
                                if era.name == "Netscape Navigator" {
                                    cometLine = true
                                }
                            }
                        Text(era.line)
                            .font(.body)
                            .foregroundStyle(.secondary)
                        if cometLine && era.name == "Netscape Navigator" {
                            Text("The comet still has a name.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("This Mac")
                        .font(.headline)
                    Text(todayLine)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Back to the present") {
                dismiss()
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
    }

    private var todayLine: String {
        switch browserCount {
        case 0:
            "No browsers found. The shelf is waiting."
        case 1:
            "One browser installed. The choice is quiet, and still yours."
        default:
            "\(browserCount) browsers installed. You pick the one links open in."
        }
    }
}
