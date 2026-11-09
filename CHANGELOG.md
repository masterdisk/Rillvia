# Changes

## Unreleased

## 1.0.0 (9 November 2026)

The first public release. Rillvia sends each link to the browser you choose for that site, from a quiet menu bar app.

- Let **Turn on rules** resume rules that paused when macOS changed the default browser, using the saved Other links browser. Settings can turn paused rules off without replacing the browser macOS now uses.
- Open every link that reaches Rillvia. While rules are off or paused, links go to the browser macOS uses. If a rule's browser can't launch, the link opens in Other links instead of holding up the links behind it.
- Deliver profile and private-window links to browsers that are already open.
- Accept links to hosts with underscores or percent-encoded Unicode, and send unusual hosts such as `127.1` to Other links instead of dropping them.
- When two rules name the same site, use the one saved most recently.
- Keep a temporary browser when the clock steps back, keep it visible and endable when its browser is uninstalled, and count its time down live. Ending or restoring one waits for a browser switch in progress.
- Require the Shortcuts permission before a shortcut brings a temporary browser back.
- Clear status messages after 10 seconds, or 30 when they offer Undo, with a button to dismiss them sooner. Keep a rule's browser profile when switching between rules.
- Install updates after **Open installer** has mounted the disk image. Remove a failed update's hidden copy, explain whether it failed to start or wasn't swapped in, and report server errors and slow downloads accurately.
- Reject reserved commands such as ⌘Z on any keyboard layout, not only US key positions.
- Replace glass action buttons with solid native controls. Give every text field and selector one inset outline, use a solid menu background, and remove the extra Settings group border.
- Rename the project, scheme, source folders, and bundle ID to Rillvia. Import the previous app's saved rules, history, and shortcuts while keeping the original files available.
- Add Updates in Settings and both app menus. Download a verified installer, then confirm when to install and restart. Restore the previous app if replacement or launch fails.
- Build a universal DMG locally or in GitHub Actions. Prepare draft releases from version tags, with optional Developer ID signing and notarization.
- Rewrite the README with native screenshots, setup steps, and the keyboard reference.
- Match selector heights, show keyboard focus on the selected option, and use readable text and control colors. Add text sizes up to 200%, scrolling tour content, and solid buttons for Reduce Transparency.
- Keep keyboard-help actions visible, scale diagnostics text, and give larger Settings controls and browser headings room to read.
