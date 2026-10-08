import AppKit
import SwiftUI

enum AppColors {
    // These text colors keep their contrast on the app's light and dark surfaces.
    static let secondaryText = adaptive(light: 0x54545B, dark: 0xB8BAC2)
    static let warningText = adaptive(light: 0x805300, dark: 0xFFD08A)
    static let errorText = adaptive(light: 0xB42318, dark: 0xFFA69B)
    static let linkText = adaptive(light: 0x005AC1, dark: 0x9ECCFF)
    static let actionTint = Color(red: 0, green: 98.0 / 255, blue: 210.0 / 255)
    static let controlBorder = adaptive(light: 0x8A8A90, dark: 0x929298)
    static let focusRing = adaptive(light: 0x005AC1, dark: 0x9ECCFF)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

struct AccessibleButtonStyle: ViewModifier {
    var prominent = false
    func body(content: Content) -> some View {
        content.buttonStyle(ReadableButtonStyle(prominent: prominent))
    }
}

private struct ReadableButtonStyle: PrimitiveButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.rillviaTextScale) private var textScale
    var prominent = false
    private var minimumLabelHeight: CGFloat {
        controlSize == .large ? 32 : controlSize == .small ? 16 : controlSize == .mini ? 12 : 20
    }
    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            button(configuration).buttonStyle(.borderedProminent).tint(AppColors.actionTint)
        } else {
            button(configuration).buttonStyle(.bordered)
        }
    }
    private func button(_ configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label.font(.system(size: 13 * textScale))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: minimumLabelHeight * textScale)
        }
    }
}

/// One opaque surface and one inset outline, shared by inputs and selectors.
struct ControlSurface: ViewModifier {
    var isFocused = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.rillviaIncreaseContrastOverride) private var testingIncreasedContrast
    private var increasedContrast: Bool { contrast == .increased || testingIncreasedContrast }
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(increasedContrast ? Color.primary : isFocused ? AppColors.focusRing : AppColors.controlBorder,
                        lineWidth: isFocused ? (increasedContrast ? 3 : 2) : (increasedContrast ? 2 : 1))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

struct AppTextField: View {
    let title: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var localFocus: Bool
    @Environment(\.rillviaTextScale) private var textScale
    @Environment(\.isEnabled) private var isEnabled
    private var fieldFocus: FocusState<Bool>.Binding { focus ?? $localFocus }
    init(_ title: String, text: Binding<String>, axis: Axis = .horizontal, focus: FocusState<Bool>.Binding? = nil) {
        self.title = title
        _text = text
        self.axis = axis
        self.focus = focus
    }
    var body: some View {
        TextField(title, text: $text, prompt: Text(title).foregroundColor(AppColors.secondaryText), axis: axis)
            .textFieldStyle(.plain).appFont(size: 15)
            .focused(fieldFocus).focusEffectDisabled()
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(minHeight: 44 * textScale)
            .modifier(ControlSurface(isFocused: fieldFocus.wrappedValue))
            .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct RillviaTextScaleKey: EnvironmentKey {
    static let defaultValue = 1.0
}

extension EnvironmentValues {
    var rillviaTextScale: Double {
        get { self[RillviaTextScaleKey.self] }
        set { self[RillviaTextScaleKey.self] = min(2, max(1, newValue)) }
    }
}

private struct AppFontModifier: ViewModifier {
    @Environment(\.rillviaTextScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(AppFontModifier(size: size, weight: weight, design: design))
    }
    func appFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default) -> some View {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline, .body: size = 13
        case .subheadline, .callout: size = 12
        case .caption: size = 11
        default: size = 10
        }
        return appFont(size: size, weight: weight ?? (style == .headline ? .semibold : .regular), design: design)
    }
}

@MainActor
enum AccessibilityAnnouncement {
    static func post(_ text: String) {
        guard NSApp.isActive, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
