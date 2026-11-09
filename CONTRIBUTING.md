# Contributing to Rillvia

Thanks for helping. Rillvia is a small, focused Mac app, so the best contributions keep it quiet, native and private.

## Reporting a bug

Open an [issue](https://github.com/masterdisk/Rillvia/issues/new/choose) with:

- your macOS version and the browsers involved
- what you did, what you expected and what happened
- the text from **Settings → Help → Diagnostics → Copy Redacted Snapshot**, which lists handler and version facts without any links or browsing data

Security problems go through [SECURITY.md](SECURITY.md) instead.

## Suggesting a feature

Describe the situation first, then the change you'd like. Rillvia favours a small number of clear controls over many options.

## Changing the code

You need Xcode with the macOS 26 SDK or newer. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers building, the sample data and the tests.

1. Fork the repository and branch from `main`.
2. Keep the change focused, and match the code around it.
3. Add or update tests. Run the unit tests before opening a pull request:

   ```sh
   xcodebuild test -project Rillvia.xcodeproj -scheme Rillvia \
     -destination 'platform=macOS' -parallel-testing-enabled NO -only-testing:RillviaTests
   ```

4. Note user-visible changes in [CHANGELOG.md](CHANGELOG.md) under **Unreleased**.
5. Open a pull request that explains the problem and how you checked the fix. CI runs the unit tests and builds the DMG.

UI tests drive real native controls with fake browser handlers, so they never change your default browser. Run them with `-only-testing:RillviaUITests` when you touch views.

## Licence

By contributing, you agree that your work is released under the [GNU General Public License v3.0](LICENSE), the same licence as the rest of Rillvia.
