import Foundation
import Darwin

enum URLNormalizationIssue: Error, Equatable, Sendable {
    case unsupportedScheme
    case missingHost
    case malformedHost
}

struct NormalizedWebURL: Equatable, Sendable {
    var originalURL: URL
    var scheme: WebScheme
    var host: String
    var isIPLiteral: Bool
    var isIDN: Bool
}

enum URLNormalizer {
    static func normalize(_ url: URL) throws -> NormalizedWebURL {
        guard let rawScheme = url.scheme?.lowercased(),
              let scheme = WebScheme(rawValue: rawScheme) else {
            throw URLNormalizationIssue.unsupportedScheme
        }
        guard var host = url.host(percentEncoded: false), !host.isEmpty else {
            throw URLNormalizationIssue.missingHost
        }

        host = host.lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty else {
            throw URLNormalizationIssue.malformedHost
        }

        var normalizedHost: String
        if host.first == "[", host.last == "]" {
            normalizedHost = String(host.dropFirst().dropLast())
        } else {
            normalizedHost = host
        }
        if !normalizedHost.unicodeScalars.allSatisfy(\.isASCII) {
            normalizedHost = try punycode(normalizedHost)
        }

        let isIPv4Literal = isIPv4(normalizedHost)
        let isIPv6Literal = isIPv6(normalizedHost)
        let looksLikeIPv4 = normalizedHost.contains(".")
            && normalizedHost.allSatisfy {
                $0.isNumber || $0 == "."
            }
        guard !looksLikeIPv4 || isIPv4Literal else {
            throw URLNormalizationIssue.malformedHost
        }
        guard !normalizedHost.contains(":") || isIPv6Literal else {
            throw URLNormalizationIssue.malformedHost
        }
        let isIPLiteral = isIPv4Literal || isIPv6Literal
        guard isIPLiteral || isValidDomain(normalizedHost) else {
            throw URLNormalizationIssue.malformedHost
        }
        guard normalizedHost.unicodeScalars.allSatisfy(\.isASCII) else {
            throw URLNormalizationIssue.malformedHost
        }

        let encodedHost = url.host(percentEncoded: true)?.lowercased() ?? ""
        let isIDN = normalizedHost.split(separator: ".").contains {
            $0.hasPrefix("xn--")
        } || encodedHost.contains("%")

        return NormalizedWebURL(
            originalURL: url,
            scheme: scheme,
            host: normalizedHost,
            isIPLiteral: isIPLiteral,
            isIDN: isIDN
        )
    }

    static func normalizeHost(_ value: String) throws -> String {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              let url = webURL(fromUserInput: candidate) else {
            throw URLNormalizationIssue.malformedHost
        }
        return try normalize(url).host
    }

    static func host(
        _ host: String,
        matches domain: String,
        scope: DomainRuleScope
    ) -> Bool {
        let hostLabels = host.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        let domainLabels = domain.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        guard !hostLabels.isEmpty,
              !domainLabels.isEmpty,
              !hostLabels.contains(where: \.isEmpty),
              !domainLabels.contains(where: \.isEmpty) else {
            return false
        }
        if scope == .exactHost {
            return hostLabels == domainLabels
        }
        guard hostLabels.count >= domainLabels.count else {
            return false
        }
        return Array(hostLabels.suffix(domainLabels.count)) == domainLabels
    }

    private static func webURL(fromUserInput candidate: String) -> URL? {
        if let url = URL(string: candidate),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return url
        }
        guard candidate.rangeOfCharacter(from: CharacterSet(charactersIn: "@")) == nil else {
            return nil
        }
        let hostEnd = candidate.firstIndex(where: { character in
            character == "/" || character == "?" || character == "#"
        })
        let hostCandidate = hostEnd.map { String(candidate[..<$0]) } ?? candidate
        guard !hostCandidate.isEmpty else {
            return nil
        }
        return URL(string: "https://\(hostCandidate)")
    }

    /// Percent-encoded Unicode hosts decode to Unicode; rules and browsers use their punycode form.
    private static func punycode(_ host: String) throws -> String {
        // Only letters may be non-ASCII, so a decoded "/" or "@" can never reshape the host.
        let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
        guard host.unicodeScalars.allSatisfy({ !$0.isASCII || hostCharacters.contains($0) }),
              let encoded = URL(string: "https://\(host)/")?.host(percentEncoded: false)?.lowercased(),
              encoded.unicodeScalars.allSatisfy(\.isASCII) else {
            throw URLNormalizationIssue.malformedHost
        }
        return encoded
    }

    private static func isValidDomain(_ host: String) -> Bool {
        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, !labels.contains(where: \.isEmpty) else {
            return false
        }
        return labels.allSatisfy { label in
            guard label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            // Underscores are not valid hostnames, but real sites such as foo_bar.s3.amazonaws.com use them.
            return label.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII
                    && (CharacterSet.alphanumerics.contains(scalar)
                        || scalar == "-" || scalar == "_")
            }
        }
    }

    private static func isIPv4(_ host: String) -> Bool {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return false }
        return pieces.allSatisfy { piece in
            guard !piece.isEmpty,
                  piece.allSatisfy(\.isNumber),
                  let value = Int(piece) else {
                return false
            }
            return value <= 255
        }
    }

    private static func isIPv6(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        var address = in6_addr()
        return host.withCString {
            inet_pton(AF_INET6, $0, &address) == 1
        }
    }
}
