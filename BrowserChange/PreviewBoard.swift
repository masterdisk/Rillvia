import Foundation

enum DayPhase: Equatable {
    case work
    case personal
}

enum QuietHours {
    static func phase(at date: Date, calendar: Calendar) -> DayPhase {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let isWeekday = (2...6).contains(weekday)
        if isWeekday && (9..<17).contains(hour) {
            return .work
        }
        return .personal
    }
}

struct RoutePreview: Identifiable, Equatable {
    var id: String
    var match: String
    var browserName: String
    var sentence: String
}

struct ProfilePreview: Identifiable, Equatable {
    var id: String
    var title: String
    var browserName: String
    var suggestedNow: Bool
}

struct QuietHourPreview: Identifiable, Equatable {
    var id: String
    var title: String
    var browserName: String
    var activeNow: Bool
    var symbol: String
}

struct PreviewBoard: Equatable {
    var routes: [RoutePreview]
    var profiles: [ProfilePreview]
    var hours: [QuietHourPreview]
    var nowLine: String

    static let empty = PreviewBoard(routes: [], profiles: [], hours: [], nowLine: "")

    static func make(
        browsers: [InstalledBrowser],
        defaultID: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> PreviewBoard {
        let real = browsers.filter { !$0.isImaginary }
        guard let fallback = real.first else { return .empty }

        let personal = pick(
            ["com.apple.Safari", "org.mozilla.firefox"],
            in: real
        ) ?? fallback
        let work = pick(
            [
                "com.google.Chrome",
                "com.microsoft.edgemac",
                "com.brave.Browser",
                "company.thebrowser.Browser",
            ],
            in: real,
            excluding: personal.id
        ) ?? personal
        let github = pick(
            ["org.mozilla.firefox", "com.brave.Browser"],
            in: real,
            excluding: personal.id
        ) ?? work
        let everyone = real.first { $0.id == defaultID } ?? personal
        let phase = QuietHours.phase(at: now, calendar: calendar)

        let nowLine: String
        switch phase {
        case .work:
            nowLine = "Right now, work hours would use \(work.name)."
        case .personal:
            nowLine = "Right now, off hours would use \(personal.name)."
        }

        return PreviewBoard(
            routes: [
                RoutePreview(
                    id: "github",
                    match: "github.com",
                    browserName: github.name,
                    sentence: "A link to github.com would open in \(github.name)."
                ),
                RoutePreview(
                    id: "apple",
                    match: "developer.apple.com",
                    browserName: personal.name,
                    sentence: "A link to developer.apple.com would open in \(personal.name)."
                ),
                RoutePreview(
                    id: "else",
                    match: "Everything else",
                    browserName: everyone.name,
                    sentence: "Any other link would open in \(everyone.name)."
                ),
            ],
            profiles: [
                ProfilePreview(
                    id: "work",
                    title: "Work",
                    browserName: work.name,
                    suggestedNow: phase == .work
                ),
                ProfilePreview(
                    id: "personal",
                    title: "Personal",
                    browserName: personal.name,
                    suggestedNow: phase == .personal
                ),
            ],
            hours: [
                QuietHourPreview(
                    id: "work",
                    title: "Weekdays, 9:00–17:00",
                    browserName: work.name,
                    activeNow: phase == .work,
                    symbol: "sun.max"
                ),
                QuietHourPreview(
                    id: "personal",
                    title: "Evenings and weekends",
                    browserName: personal.name,
                    activeNow: phase == .personal,
                    symbol: "moon.stars"
                ),
            ],
            nowLine: nowLine
        )
    }

    private static func pick(
        _ identifiers: [String],
        in browsers: [InstalledBrowser],
        excluding: String? = nil
    ) -> InstalledBrowser? {
        for identifier in identifiers {
            if identifier == excluding { continue }
            if let match = browsers.first(where: { $0.id == identifier }) {
                return match
            }
        }
        return nil
    }
}
