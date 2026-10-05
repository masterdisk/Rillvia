import Foundation

enum AirlockWarning: Equatable, Hashable, Sendable {
    case plainHTTP
    case embeddedCredentials
    case ipLiteral
    case idnOrPunycode
    case trackingParameters([String])

    var message: String {
        switch self {
        case .plainHTTP:
            "This link uses plain HTTP."
        case .embeddedCredentials:
            "This link contains embedded credentials."
        case .ipLiteral:
            "This link uses an IP address instead of a domain."
        case .idnOrPunycode:
            "This link contains an internationalized domain."
        case .trackingParameters(let names):
            "Common tracking parameters: \(names.joined(separator: ", "))."
        }
    }
}

struct AirlockItem: Equatable, Identifiable, Sendable {
    var originalText: String
    var normalized: NormalizedWebURL
    var warnings: [AirlockWarning]

    var id: String {
        originalText
    }
}

struct AirlockParseResult: Equatable, Sendable {
    var items: [AirlockItem]
    var rejectedCandidateCount: Int
    var wasTextTruncated: Bool
    var wasURLLimitReached: Bool
}

struct AirlockParser: Sendable {
    /// Text beyond this character count is ignored before URL extraction.
    static let defaultMaxTextLength = 100_000
    /// At most this many unique valid links are staged in one operation.
    static let defaultMaxURLCount = 20

    var maxTextLength: Int
    var maxURLCount: Int

    init(
        maxTextLength: Int = defaultMaxTextLength,
        maxURLCount: Int = defaultMaxURLCount
    ) {
        self.maxTextLength = max(0, maxTextLength)
        self.maxURLCount = max(0, maxURLCount)
    }

    func parse(text: String) -> AirlockParseResult {
        let wasTextTruncated = text.count > maxTextLength
        let boundedText = String(text.prefix(maxTextLength))
        return parse(
            candidates: extractCandidates(from: boundedText).map {
                ($0, URL(string: $0))
            },
            wasTextTruncated: wasTextTruncated
        )
    }

    func parse(urls: [URL]) -> AirlockParseResult {
        parse(
            candidates: urls.map { ($0.absoluteString, Optional($0)) },
            wasTextTruncated: false
        )
    }

    private func parse(
        candidates: [(original: String, url: URL?)],
        wasTextTruncated: Bool
    ) -> AirlockParseResult {
        var items: [AirlockItem] = []
        var rejectedCandidateCount = 0
        var wasURLLimitReached = false
        var seen = Set<String>()

        for candidate in candidates {
            guard let url = candidate.url else {
                rejectedCandidateCount += 1
                continue
            }

            let normalized: NormalizedWebURL
            do {
                normalized = try URLNormalizer.normalize(url)
            } catch {
                rejectedCandidateCount += 1
                continue
            }

            let duplicateKey = [
                normalized.scheme.rawValue,
                normalized.host,
                String(url.port ?? defaultPort(for: normalized.scheme)),
                url.user ?? "",
                url.password ?? "",
                url.path,
                url.query ?? "",
                url.fragment ?? "",
            ].joined(separator: "\u{1F}")
            guard seen.insert(duplicateKey).inserted else {
                continue
            }
            guard items.count < maxURLCount else {
                wasURLLimitReached = true
                continue
            }

            items.append(
                AirlockItem(
                    originalText: candidate.original,
                    normalized: normalized,
                    warnings: warnings(for: normalized)
                )
            )
        }

        return AirlockParseResult(
            items: items,
            rejectedCandidateCount: rejectedCandidateCount,
            wasTextTruncated: wasTextTruncated,
            wasURLLimitReached: wasURLLimitReached
        )
    }

    private func extractCandidates(from text: String) -> [String] {
        let pattern = #"(?i)\b[a-z][a-z0-9+.-]*://[^\s<>"']+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }
            return trimSentencePunctuation(String(text[matchRange]))
        }
    }

    private func trimSentencePunctuation(_ candidate: String) -> String {
        var result = candidate
        let punctuation = CharacterSet(charactersIn: ".,;!?)]}")
        while let scalar = result.unicodeScalars.last,
              punctuation.contains(scalar) {
            result.removeLast()
        }
        return result
    }

    private func warnings(
        for normalized: NormalizedWebURL
    ) -> [AirlockWarning] {
        var warnings: [AirlockWarning] = []
        let url = normalized.originalURL

        if normalized.scheme == .http {
            warnings.append(.plainHTTP)
        }
        if url.user != nil || url.password != nil {
            warnings.append(.embeddedCredentials)
        }
        if normalized.isIPLiteral {
            warnings.append(.ipLiteral)
        }
        if normalized.isIDN {
            warnings.append(.idnOrPunycode)
        }

        let trackingNames = Set(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems ?? [])
                .map { $0.name.lowercased() }
                .filter(Self.trackingParameterNames.contains)
        ).sorted()
        if !trackingNames.isEmpty {
            warnings.append(.trackingParameters(trackingNames))
        }
        return warnings
    }

    private func defaultPort(for scheme: WebScheme) -> Int {
        switch scheme {
        case .http:
            80
        case .https:
            443
        }
    }

    private static let trackingParameterNames: Set<String> = [
        "dclid",
        "fbclid",
        "gclid",
        "mc_cid",
        "mc_eid",
        "msclkid",
        "utm_campaign",
        "utm_content",
        "utm_medium",
        "utm_source",
        "utm_term",
    ]
}
