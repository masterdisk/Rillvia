import SwiftUI

enum BrowserChangeMotionPolicy {
    static func animationsEnabled(
        systemReduceMotion: Bool,
        testingOverride: Bool
    ) -> Bool {
        !systemReduceMotion && !testingOverride
    }
}

private struct BrowserChangeReduceMotionOverrideKey:
    EnvironmentKey
{
    static let defaultValue = false
}

extension EnvironmentValues {
    var browserChangeReduceMotionOverride: Bool {
        get {
            self[BrowserChangeReduceMotionOverrideKey.self]
        }
        set {
            self[BrowserChangeReduceMotionOverrideKey.self] =
                newValue
        }
    }
}
