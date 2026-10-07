import SwiftUI

enum RillviaMotionPolicy {
    static func animationsEnabled(
        systemReduceMotion: Bool,
        testingOverride: Bool
    ) -> Bool {
        !systemReduceMotion && !testingOverride
    }
}

private struct RillviaReduceMotionOverrideKey:
    EnvironmentKey
{
    static let defaultValue = false
}

private struct RillviaReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

private struct RillviaIncreaseContrastOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rillviaReduceTransparencyOverride: Bool {
        get { self[RillviaReduceTransparencyOverrideKey.self] }
        set { self[RillviaReduceTransparencyOverrideKey.self] = newValue }
    }
    var rillviaIncreaseContrastOverride: Bool {
        get { self[RillviaIncreaseContrastOverrideKey.self] }
        set { self[RillviaIncreaseContrastOverrideKey.self] = newValue }
    }
    var rillviaReduceMotionOverride: Bool {
        get {
            self[RillviaReduceMotionOverrideKey.self]
        }
        set {
            self[RillviaReduceMotionOverrideKey.self] =
                newValue
        }
    }
}
