import CryptoKit
import Foundation
import XCTest
@testable import Rillvia

final class UpdateModelTests: XCTestCase {
    func testVersionComparisonUsesNumbersAndTreatsMissingComponentsAsZero() throws {
        XCTAssertEqual(ReleaseVersion("1.0"), ReleaseVersion("v1.0.0"))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.9.0")), try XCTUnwrap(ReleaseVersion("1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(ReleaseVersion("1.99.99")), try XCTUnwrap(ReleaseVersion("2.0.0")))
        for value in ["1.0.0-beta.1", "1.0.0; open /tmp", "1.01.0", "", "1.2.3.4", "-1.0"] {
            XCTAssertNil(ReleaseVersion(value))
        }
    }

    func testDraftsAndPrereleasesDoNotBecomeUpdates() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            document(tag: "v2.0.0", draft: true), document(tag: "v1.2.0", prerelease: true), document(tag: "v1.1.0"),
        ])
        let release = try XCTUnwrap(GitHubReleaseDocument.latest(in: data))
        XCTAssertEqual(release.version.description, "1.1.0")
        XCTAssertEqual(release.url.absoluteString, "https://github.com/masterdisk/Rillvia/releases/tag/v1.1.0")
        XCTAssertNotNil(release.asset)
    }

    func testNoPublishedReleaseIsDifferentFromAnUnuploadedInstaller() throws {
        XCTAssertNil(try GitHubReleaseDocument.latest(in: Data("[]".utf8)))
        var release = document(tag: "v1.1.0")
        release["assets"] = []
        XCTAssertNil(try XCTUnwrap(GitHubReleaseDocument.latest(in: JSONSerialization.data(withJSONObject: [release]))).asset)
    }

    func testAssetMustBelongToThisRepositoryAndHaveAChecksum() throws {
        for change in [
            ["browser_download_url": "https://example.com/Rillvia.dmg"],
            ["digest": "sha256:wrong"], ["size": 0], ["size": 600 * 1_024 * 1_024], ["state": "new"],
        ] as [[String: Any]] {
            var release = document(tag: "v1.1.0")
            var asset = try XCTUnwrap((release["assets"] as? [[String: Any]])?.first)
            asset.merge(change) { _, new in new }
            release["assets"] = [asset]
            XCTAssertThrowsError(try GitHubReleaseDocument.latest(in: JSONSerialization.data(withJSONObject: [release]))) { error in
                XCTAssertEqual(error as? UpdateError, .invalidRelease)
            }
        }
    }

    func testDownloadedBytesMustMatchBothSizeAndChecksum() throws {
        let directory = try UpdateFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("test.dmg")
        let bytes = Data("a verified installer".utf8)
        try bytes.write(to: file)
        var asset = testAsset(bytes)
        XCTAssertNoThrow(try UpdateFiles.verify(file, asset: asset))
        asset.sha256 = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try UpdateFiles.verify(file, asset: asset)) { error in XCTAssertEqual(error as? UpdateError, .checksumMismatch) }
        asset.size += 1
        XCTAssertThrowsError(try UpdateFiles.verify(file, asset: asset)) { error in XCTAssertEqual(error as? UpdateError, .wrongSize) }
    }

    func testADeveloperSignedInstallRejectsAnUpdateFromAnotherTeam() {
        XCTAssertNoThrow(try UpdateBundleValidation.validateTeam(installed: "TEAM1", candidate: "TEAM1"))
        XCTAssertNoThrow(try UpdateBundleValidation.validateTeam(installed: nil, candidate: "TEAM1"))
        for candidate in ["TEAM2", nil] {
            XCTAssertThrowsError(try UpdateBundleValidation.validateTeam(installed: "TEAM1", candidate: candidate)) { error in
                XCTAssertEqual(error as? UpdateError, .wrongSigner)
            }
        }
    }

    func testBuiltAppPassesIdentityVersionAndSignatureValidation() throws {
        let app = Bundle.main.bundleURL
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertNoThrow(try UpdateBundleValidation.validate(app, version: version, installedApp: app))
        XCTAssertThrowsError(try UpdateBundleValidation.validate(app, version: "99.0.0", installedApp: app)) { error in
            XCTAssertEqual(error as? UpdateError, .invalidApp)
        }
    }

    private func document(tag: String, draft: Bool = false, prerelease: Bool = false) -> [String: Any] {
        let version = String(tag.dropFirst())
        let name = "Rillvia-\(version)-universal.dmg"
        return ["tag_name": tag, "body": "Changes for this version.", "draft": draft, "prerelease": prerelease,
            "assets": [["id": 10, "name": name, "size": 10, "state": "uploaded", "digest": "sha256:" + String(repeating: "a", count: 64),
                "browser_download_url": "https://github.com/masterdisk/Rillvia/releases/download/\(tag)/\(name)"]]]
    }
}

@MainActor
final class UpdateControllerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "RillviaUpdateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }
    override func tearDownWithError() throws { defaults.removePersistentDomain(forName: suite) }

    func testCheckingAndDownloadingNeverInstallUntilTheUserRequestsIt() async throws {
        let bytes = Data("sample installer".utf8)
        let directory = try UpdateFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.dmg")
        try bytes.write(to: file)
        let release = UpdateRelease(version: ReleaseVersion("1.1.0")!, tag: "v1.1.0", notes: "", asset: testAsset(bytes))
        let client = UpdateTestClient(release: release, file: file)
        let installer = UpdateTestInstaller()
        let controller = UpdateController(client: client, installer: installer, defaults: defaults, installedVersion: "1.0")

        await controller.installAndRestart()
        XCTAssertEqual(installer.calls, 0)
        await controller.check()
        XCTAssertEqual(controller.phase, .available(release))
        XCTAssertEqual(client.downloads, 0)
        XCTAssertNotNil(controller.lastChecked)
        await controller.download()
        XCTAssertEqual(controller.phase, .ready(release, file))
        XCTAssertEqual(installer.calls, 0)
        await controller.installAndRestart()
        XCTAssertEqual(installer.calls, 1)
    }

    func testCurrentOrOlderVersionDoesNotOfferAnInstall() async {
        for version in ["1.0.0", "0.9.0"] {
            let client = UpdateTestClient(release: UpdateRelease(version: ReleaseVersion(version)!, tag: "v\(version)", notes: "", asset: nil))
            let controller = UpdateController(client: client, installer: UpdateTestInstaller(), defaults: defaults, installedVersion: "1.0")
            await controller.check()
            XCTAssertEqual(controller.phase, .current)
            await controller.download()
            XCTAssertEqual(client.downloads, 0)
        }
    }

    func testAccessFailureIsNeverReportedAsUpToDate() async {
        let controller = UpdateController(client: UpdateTestClient(error: .accessRequired), installer: UpdateTestInstaller(), defaults: defaults)
        await controller.check()
        XCTAssertEqual(controller.phase, .failed(UpdateError.accessRequired.localizedDescription))
        XCTAssertNil(controller.lastChecked)
        XCTAssertNil(defaults.object(forKey: "updates.lastChecked"))
    }

    func testEmptyReleaseListHasItsOwnStatusAndPersistsLastCheck() async {
        let client = UpdateTestClient()
        let controller = UpdateController(client: client, installer: UpdateTestInstaller(), defaults: defaults)
        await controller.check()
        XCTAssertEqual(controller.phase, .noRelease)
        XCTAssertNotNil(UpdateController(client: client, installer: UpdateTestInstaller(), defaults: defaults).lastChecked)
    }

    func testInstallerFailureLeavesTheDownloadAvailableForManualInstallation() async throws {
        let directory = try UpdateFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sample.dmg")
        let bytes = Data("sample installer".utf8)
        try bytes.write(to: file)
        let release = UpdateRelease(version: ReleaseVersion("1.1.0")!, tag: "v1.1.0", notes: "", asset: testAsset(bytes))
        let installer = UpdateTestInstaller(error: .cannotReplace)
        let controller = UpdateController(client: UpdateTestClient(release: release, file: file), installer: installer, defaults: defaults, installedVersion: "1.0")
        await controller.check()
        await controller.download()
        await controller.installAndRestart()
        XCTAssertEqual(controller.phase, .failed(UpdateError.cannotReplace.localizedDescription))
        XCTAssertEqual(controller.downloadedInstaller, file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}

final class BundleReplacementTests: XCTestCase {
    private var directory: URL!
    private var plan: UpdateInstallPlan!
    override func setUpWithError() throws {
        directory = try UpdateFiles.makeTemporaryDirectory()
        plan = UpdateInstallPlan(id: UUID(), installedApp: directory.appendingPathComponent("Rillvia.app"), previousVersion: "1.0", version: "1.1.0", parentPID: 1)
        try FileManager.default.createDirectory(at: plan.installedApp, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plan.stagedApp, withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: plan.installedApp.appendingPathComponent("version"))
        try Data("new".utf8).write(to: plan.stagedApp.appendingPathComponent("version"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testSuccessfulLaunchReplacesTheBundleAndRemovesTheTemporaryBackup() throws {
        try BundleReplacement.perform(plan) { app in
            XCTAssertEqual(try? String(contentsOf: app.appendingPathComponent("version"), encoding: .utf8), "new")
            return true
        }
        XCTAssertEqual(try String(contentsOf: plan.installedApp.appendingPathComponent("version"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.backupApp.path))
    }

    func testFailedLaunchRestoresThePreviousBundleAndKeepsTheFailedCandidate() throws {
        XCTAssertThrowsError(try BundleReplacement.perform(plan, launch: { _ in false })) { error in
            XCTAssertEqual(error as? UpdateError, .launchFailed)
        }
        XCTAssertEqual(try String(contentsOf: plan.installedApp.appendingPathComponent("version"), encoding: .utf8), "previous")
        XCTAssertEqual(try String(contentsOf: plan.stagedApp.appendingPathComponent("version"), encoding: .utf8), "new")
    }

    func testFailedCandidateRenameRestoresThePreviousBundleBeforeReturning() throws {
        XCTAssertThrowsError(try BundleReplacement.perform(plan, fileManager: FailingReplacementFileManager(), launch: { _ in true }))
        XCTAssertEqual(try String(contentsOf: plan.installedApp.appendingPathComponent("version"), encoding: .utf8), "previous")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.stagedApp.path))
    }

    func testAnExistingBackupStopsReplacementWithoutChangingEitherVersion() throws {
        try FileManager.default.createDirectory(at: plan.backupApp, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BundleReplacement.perform(plan, launch: { _ in true }))
        XCTAssertEqual(try String(contentsOf: plan.installedApp.appendingPathComponent("version"), encoding: .utf8), "previous")
        XCTAssertEqual(try String(contentsOf: plan.stagedApp.appendingPathComponent("version"), encoding: .utf8), "new")
    }
}

private func testAsset(_ bytes: Data) -> UpdateAsset {
    UpdateAsset(id: 1, name: "sample.dmg", size: Int64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), downloadURL: UpdateSource.releasesURL)
}
private final class UpdateTestClient: UpdateProviding {
    var release: UpdateRelease?
    var error: UpdateError?
    var file: URL?
    var downloads = 0
    init(release: UpdateRelease? = nil, error: UpdateError? = nil, file: URL? = nil) { self.release = release; self.error = error; self.file = file }
    func latestRelease() async throws -> UpdateRelease? { if let error { throw error }; return release }
    func download(_ release: UpdateRelease) async throws -> URL { downloads += 1; return try XCTUnwrap(file) }
}
@MainActor
private final class UpdateTestInstaller: UpdateInstalling {
    var calls = 0
    var error: UpdateError?
    init(error: UpdateError? = nil) { self.error = error }
    func install(_ diskImage: URL, release: UpdateRelease) async throws { calls += 1; if let error { throw error } }
}
private final class FailingReplacementFileManager: FileManager, @unchecked Sendable {
    override func moveItem(at source: URL, to destination: URL) throws {
        if source.lastPathComponent.hasPrefix(".Rillvia-update-") { throw CocoaError(.fileWriteUnknown) }
        try super.moveItem(at: source, to: destination)
    }
}
