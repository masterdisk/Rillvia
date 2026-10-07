# README screenshots

These are captures of the native SwiftUI app with isolated sample data, not generated design mockups. Images are copied without cropping, resizing, or repainting.

| Image | Native source | Size in pixels |
| --- | --- | --- |
| `overview-light.png` | `testOverviewAndKeyboardNavigation` | 940 × 680 |
| `overview-dark.png` | `testDarkAppearanceAtDefaultTextSize` | 940 × 680 |
| `preview.png` | `testPreviewStaysCurrentOnlyUntilInputChanges` | 940 × 680 |
| `rules.png` | `testRuleDraftNeedsSaveAndGuardsNavigation` | 940 × 680 |
| `browsers.png` | `testBrowserSelectionDoesNotChangeFallback` | 940 × 680 |
| `menu-bar.png` | `testMenuPanelShowsFullActionAndExplicitTemporarySwitch`, actual status popup | 400 × 560 |
| `shortcut-builder.png` | `testAppScopedShortcutDoesNotRunOutsideRillviaAndDeletionCanBeUndone`, recorded browser action before changing its scope | 940 × 680 |
| `tutorial.png` | `testSettingsTutorialReplayAndKeyboardHelp`, first tour step in its owner window | 940 × 680 |

These images come from the passing 7 October run, `build/rillvia-complete-validation.xcresult`, on macOS 27 with Xcode 27. Sheets are shown in their owner window; the menu capture contains only the status popup. See [design-qa.md](../../design-qa.md) for the checks and their limits, and [the capture manifest](capture-manifest.json) for source filenames and hashes. The earlier review remains in [reviews/2026-10-06-rillvia-implementation](../../reviews/2026-10-06-rillvia-implementation).
