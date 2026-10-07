import Foundation

struct LivingBrowserEra: Equatable, Identifiable, Sendable {
    var year: String
    var name: String
    var line: String
    var representedBy: [String]

    var id: String {
        year
    }

    var isRepresented: Bool {
        !representedBy.isEmpty
    }
}

struct LivingBrowserFacts: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var version: String
    var enabledRuleCount: Int
    var hasActiveLease: Bool
    var status: [String]
}

struct LivingBrowserHallModel: Equatable, Sendable {
    var eras: [LivingBrowserEra]
    var browsers: [LivingBrowserFacts]
    var todayLine: String

    static func make(
        installedBrowsers: [InstalledBrowser],
        configuration: RoutingConfiguration,
        defaultBundleID: String?,
        now: Date
    ) -> LivingBrowserHallModel {
        let installed = installedBrowsers.filter { !$0.isImaginary }
        let eras = eraDefinitions.map { definition in
            LivingBrowserEra(
                year: definition.year,
                name: definition.name,
                line: definition.line,
                representedBy: installed
                    .filter {
                        definition.matches($0.id.lowercased())
                    }
                    .map(\.name)
                    .sorted()
            )
        }
        let browsers = installed
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending
            }
            .map { browser in
                let hasActiveLease = configuration.browserLease.map {
                    $0.browser == browser.reference
                        && $0.isActive(at: now)
                } ?? false
                var status: [String] = []
                if hasActiveLease {
                    status.append("Temporary browser")
                }
                if browser.id == defaultBundleID {
                    status.append(
                        configuration.mode == .smart
                            ? "Browser for sites with no rule"
                            : "Usual browser"
                    )
                }
                return LivingBrowserFacts(
                    id: browser.id,
                    name: browser.name,
                    version: browser.version,
                    enabledRuleCount: configuration.domainRules.filter {
                        $0.isEnabled
                            && $0.browser == browser.reference
                    }.count,
                    hasActiveLease: hasActiveLease,
                    status: status
                )
            }

        return LivingBrowserHallModel(
            eras: eras,
            browsers: browsers,
            todayLine: todayLine(browserCount: installed.count)
        )
    }

    private struct EraDefinition {
        var year: String
        var name: String
        var line: String
        var matches: (String) -> Bool
    }

    private static let eraDefinitions: [EraDefinition] = [
        EraDefinition(
            year: "1993",
            name: "NCSA Mosaic",
            line: "The web got a window.",
            matches: { $0.contains("mosaic") }
        ),
        EraDefinition(
            year: "1994",
            name: "Netscape Navigator",
            line: "Browsing became a product.",
            matches: {
                $0.contains("mozilla")
                    || $0.contains("firefox")
                    || $0.contains("netscape")
            }
        ),
        EraDefinition(
            year: "1995",
            name: "Internet Explorer",
            line: "It won, and then it stayed.",
            matches: {
                $0.contains("internetexplorer")
                    || $0.contains("microsoft.edge")
                    || $0.contains("edgemac")
            }
        ),
        EraDefinition(
            year: "2003",
            name: "Safari",
            line: "The browser that ships with the Mac.",
            matches: {
                $0.contains("apple.safari")
                    || $0.contains("webkit")
            }
        ),
        EraDefinition(
            year: "2008",
            name: "Chrome",
            line: "A new one, and then a crowd of them.",
            matches: {
                $0.contains("chrome")
                    || $0.contains("chromium")
                    || $0.contains("brave")
                    || $0.contains("thebrowser")
                    || $0.contains("vivaldi")
            }
        ),
    ]

    private static func todayLine(browserCount: Int) -> String {
        switch browserCount {
        case 0:
            "No browsers found. The shelf is waiting."
        case 1:
            "1 browser installed. The choice is quiet, and still yours."
        default:
            "\(browserCount) browsers installed. Their live roles are below."
        }
    }
}
