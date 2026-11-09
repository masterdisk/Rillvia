import Foundation

struct ReleaseVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let value = value.hasPrefix("v") ? String(value.dropFirst()) : value
        guard value.range(of: #"^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == value.split(separator: ".").count else { return nil }
        major = parts[0]
        minor = parts.count > 1 ? parts[1] : 0
        patch = parts.count > 2 ? parts[2] : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum UpdateSource {
    static let repository = "masterdisk/Rillvia"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases")!
    static let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=100")!
}

struct UpdateAsset: Equatable, Sendable {
    var id: Int
    var name: String
    var size: Int64
    var sha256: String
    var downloadURL: URL
}

struct UpdateRelease: Equatable, Sendable {
    var version: ReleaseVersion
    var tag: String
    var notes: String
    var asset: UpdateAsset?
    var url: URL { UpdateSource.releasesURL.appendingPathComponent("tag").appendingPathComponent(tag) }
}

enum UpdateError: Error, Equatable, LocalizedError {
    case accessRequired, noInstaller, invalidRelease, checksumMismatch, wrongSize
    case downloadFailed, toolFailed, timeout, invalidApp, wrongSigner, cannotReplace, launchFailed

    var errorDescription: String? {
        switch self {
        case .accessRequired: "GitHub access is required. Sign in with GitHub CLI, or open Releases to download the update."
        case .noInstaller: "The installer is not ready yet. Check the release page."
        case .invalidRelease: "This release could not be verified. Open Releases to check it."
        case .checksumMismatch: "The download did not match its checksum. Download it again."
        case .wrongSize: "The download is incomplete. Download it again."
        case .downloadFailed: "The update could not be downloaded. Check your connection and try again."
        case .toolFailed: "The installer could not be opened. Download it again or open Releases."
        case .timeout: "The update took too long. Try again."
        case .invalidApp: "This installer does not contain the expected Rillvia version."
        case .wrongSigner: "This update was signed by a different developer. The installed app has been kept."
        case .cannotReplace: "Rillvia could not replace this copy, so the installed version was kept. Open the installer to update it yourself."
        case .launchFailed: "The updated app could not start. Your previous version has been restored."
        }
    }
}

struct GitHubReleaseDocument: Decodable {
    var tag_name: String
    var body: String?
    var draft: Bool
    var prerelease: Bool
    var assets: [Asset]

    struct Asset: Decodable {
        var id: Int
        var name: String
        var size: Int64
        var state: String
        var digest: String?
        var browser_download_url: URL
    }

    static func latest(in data: Data) throws -> UpdateRelease? {
        let documents = try JSONDecoder().decode([Self].self, from: data)
        let candidates = documents.compactMap { document -> (ReleaseVersion, Self)? in
            guard !document.draft, !document.prerelease,
                  document.tag_name.range(of: #"^v[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
                  let version = ReleaseVersion(document.tag_name) else { return nil }
            return (version, document)
        }
        guard let (version, document) = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        let expectedName = "Rillvia-\(version)-universal.dmg"
        var asset: UpdateAsset?
        if let source = document.assets.first(where: { $0.name == expectedName }) {
            let expectedURL = "https://github.com/\(UpdateSource.repository)/releases/download/\(document.tag_name)/\(expectedName)"
            guard source.id > 0, source.state == "uploaded", source.size > 0, source.size <= 512 * 1_024 * 1_024,
                  source.browser_download_url.absoluteString == expectedURL,
                  let digest = source.digest, digest.range(of: #"^sha256:[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else {
                throw UpdateError.invalidRelease
            }
            asset = UpdateAsset(id: source.id, name: source.name, size: source.size,
                sha256: String(digest.dropFirst(7)).lowercased(), downloadURL: source.browser_download_url)
        }
        return UpdateRelease(version: version, tag: document.tag_name, notes: document.body ?? "", asset: asset)
    }
}
