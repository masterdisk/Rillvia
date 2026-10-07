import Foundation

struct TapGate {
    var threshold: Int
    var interval: TimeInterval
    private var count = 0
    private var last: Date?

    mutating func tap(at date: Date) -> Bool {
        if let last, date.timeIntervalSince(last) > interval {
            count = 0
        }
        last = date
        count += 1
        if count >= threshold {
            count = 0
            last = nil
            return true
        }
        return false
    }
}

struct CharacterSequence {
    var target: String
    var gap: TimeInterval
    private var progress = ""
    private var last: Date?

    mutating func consume(_ raw: String, at date: Date) -> Bool {
        guard raw.count == 1, let character = raw.lowercased().first, character.isLetter else {
            return false
        }
        if let last, date.timeIntervalSince(last) > gap {
            progress = ""
        }
        last = date
        progress.append(character)
        if progress.hasSuffix(target) {
            progress = ""
            last = nil
            return true
        }
        if progress.count > target.count {
            progress = String(progress.suffix(target.count))
        }
        return false
    }
}

enum ImaginaryBrowser {
    static let lynx = InstalledBrowser(
        id: "org.lynx.lynx",
        name: "Lynx",
        version: "Text only",
        appURL: URL(fileURLWithPath: "/usr/bin/lynx"),
        isImaginary: true
    )
}

enum DefaultBrowserFailure {
    static func message(for error: Error) -> String {
        if error is CancellationError {
            return "Left the default where it was."
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return "Left the default where it was."
        }
        return "macOS did not change the default. \(nsError.localizedDescription)"
    }
}
