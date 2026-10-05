import Foundation

struct AirlockChooserResult: Equatable, Sendable {
    var routingOutcome: RoutingOutcome
    var teachingRequested: Bool
    var teachingSucceeded: Bool
    var errorMessage: String?

    var shouldDismiss: Bool {
        guard case .opened = routingOutcome else {
            return false
        }
        return !teachingRequested || teachingSucceeded
    }
}
