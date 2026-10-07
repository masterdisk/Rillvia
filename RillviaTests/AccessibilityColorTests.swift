import AppKit
import SwiftUI
import XCTest
@testable import Rillvia

@MainActor
final class AccessibilityColorTests: XCTestCase {
    func testTextContrastOnLightAndDarkNativeSurfaces() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                for color in [AppColors.secondaryText, AppColors.warningText, AppColors.errorText, AppColors.linkText] {
                    for surface in [NSColor.windowBackgroundColor, .controlBackgroundColor] {
                        XCTAssertGreaterThanOrEqual(contrast(NSColor(color), surface), 4.5, "\(name) text contrast")
                    }
                }
            }
        }
    }
    func testActionTextAndControlBordersHaveEnoughContrast() {
        XCTAssertGreaterThanOrEqual(contrast(.white, NSColor(AppColors.actionTint)), 4.5)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                XCTAssertGreaterThanOrEqual(contrast(NSColor(AppColors.controlBorder), .controlBackgroundColor), 3)
            }
        }
    }
    private func contrast(_ foreground: NSColor, _ background: NSColor) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    private func luminance(_ color: NSColor) -> Double {
        let color = color.usingColorSpace(.sRGB)!
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent) + 0.0722 * channel(color.blueComponent)
    }
}
