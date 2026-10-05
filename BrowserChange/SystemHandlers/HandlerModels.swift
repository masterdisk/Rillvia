import Foundation

enum WebScheme: String, Codable, CaseIterable, Sendable {
    case http
    case https

    var probeURL: URL {
        switch self {
        case .http:
            ProbeURL.http
        case .https:
            ProbeURL.https
        }
    }
}

struct HandlerApplication: Codable, Equatable, Sendable {
    var browser: BrowserReference
    var applicationURL: URL
}

struct HTTPHandlerSnapshot: Codable, Equatable, Sendable {
    var http: HandlerApplication?
    var https: HandlerApplication?

    static let missing = HTTPHandlerSnapshot(http: nil, https: nil)

    static func same(_ application: HandlerApplication) -> HTTPHandlerSnapshot {
        HTTPHandlerSnapshot(http: application, https: application)
    }

    subscript(scheme: WebScheme) -> HandlerApplication? {
        get {
            switch scheme {
            case .http:
                http
            case .https:
                https
            }
        }
        set {
            switch scheme {
            case .http:
                http = newValue
            case .https:
                https = newValue
            }
        }
    }

    func ownership(browserChange: BrowserReference) -> HandlerOwnership {
        guard let http, let https else {
            return .missing(http: http, https: https)
        }

        let httpID = http.browser.bundleIdentifier
        let httpsID = https.browser.bundleIdentifier
        guard httpID == httpsID else {
            return .split(http: http, https: https)
        }

        if httpID == browserChange.bundleIdentifier {
            return .browserChange
        }
        return .external(http.browser)
    }
}

enum HandlerOwnership: Codable, Equatable, Sendable {
    case external(BrowserReference)
    case browserChange
    case split(http: HandlerApplication, https: HandlerApplication)
    case missing(http: HandlerApplication?, https: HandlerApplication?)
}

enum SchemeHandlerHealth: Equatable, Sendable {
    case external(HandlerApplication)
    case browserChange(HandlerApplication)
    case missing
}

struct HTTPHandlerHealth: Equatable, Sendable {
    var http: SchemeHandlerHealth
    var https: SchemeHandlerHealth
    var ownership: HandlerOwnership

    var hasSplitHandlers: Bool {
        if case .split = ownership {
            return true
        }
        return false
    }

    var agreedExternalBrowser: BrowserReference? {
        if case .external(let browser) = ownership {
            return browser
        }
        return nil
    }
}

extension HTTPHandlerSnapshot {
    func health(browserChange: BrowserReference) -> HTTPHandlerHealth {
        HTTPHandlerHealth(
            http: schemeHealth(for: .http, browserChange: browserChange),
            https: schemeHealth(for: .https, browserChange: browserChange),
            ownership: ownership(browserChange: browserChange)
        )
    }

    private func schemeHealth(
        for scheme: WebScheme,
        browserChange: BrowserReference
    ) -> SchemeHandlerHealth {
        guard let application = self[scheme] else {
            return .missing
        }
        if application.browser == browserChange {
            return .browserChange(application)
        }
        return .external(application)
    }
}
