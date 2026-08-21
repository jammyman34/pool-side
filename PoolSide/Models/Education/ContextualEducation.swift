import Foundation

/// Stable identifiers for first-time contextual education.
enum ContextualTipID: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case firstChemistryEntry
    case firstPoolStateQuestions
    case firstTreatmentPlanOverview
    case firstTreatmentCompletion
    case firstTreatmentSkip
    case firstTreatmentReinstate
    case firstWatchlist
    case firstNextPoolTest
    case firstDashboardScoreAndNextTest
    case firstDashboardRecentTests
    case firstDashboardNavigation

    case firstRecoveryTreatment
    case firstAcidTreatment
    case firstChlorineTreatment
    case firstCYAAdjustment
    case firstPoolCareOnlyTreatment

    var id: String { rawValue }
}

enum ContextualWalkthroughID: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case dashboard

    var id: String { rawValue }

    var tipIDs: [ContextualTipID] {
        switch self {
        case .dashboard:
            return [
                .firstDashboardScoreAndNextTest,
                .firstDashboardRecentTests,
                .firstDashboardNavigation
            ]
        }
    }
}

struct ContextualTipContent: Equatable {
    let id: ContextualTipID
    let title: String
    let body: String

    static let firstChemistryEntry = ContextualTipContent(
        id: .firstChemistryEntry,
        title: "Test your water",
        body: "Use your selected test method, then enter each result below."
    )

    static let firstPoolStateQuestions = ContextualTipContent(
        id: .firstPoolStateQuestions,
        title: "Tell us what you see",
        body: "These quick questions help Pool Side understand whether your water-test results match what’s happening in the pool."
    )

    static let firstTreatmentPlanOverview = ContextualTipContent(
        id: .firstTreatmentPlanOverview,
        title: "Here’s what to do next",
        body: "Pool Side has organized your recommendations in order. Complete the steps that apply, then use the Next Pool Test card to know when to test again."
    )

    static let firstTreatmentCompletion = ContextualTipContent(
        id: .firstTreatmentCompletion,
        title: "Mark completed treatments",
        body: "Mark a treatment complete only after you’ve actually added it. Pool Side uses that status to decide what should happen next."
    )

    static let firstTreatmentSkip = ContextualTipContent(
        id: .firstTreatmentSkip,
        title: "Skip a treatment",
        body: "Swipe a treatment to skip it if you’re not going to do it."
    )

    static let firstTreatmentReinstate = ContextualTipContent(
        id: .firstTreatmentReinstate,
        title: "Changed your mind?",
        body: "Swipe the skipped treatment the other way to put it back in the plan."
    )

    static let firstWatchlist = ContextualTipContent(
        id: .firstWatchlist,
        title: "Things to keep an eye on",
        body: "Watchlist items are not treatment steps. They’re conditions Pool Side wants you to monitor over time."
    )

    static let firstNextPoolTest = ContextualTipContent(
        id: .firstNextPoolTest,
        title: "Your next test",
        body: "This is when Pool Side recommends testing again. If notifications are enabled, you’ll be reminded at this time."
    )

    static func content(for id: ContextualTipID) -> ContextualTipContent {
        switch id {
        case .firstChemistryEntry: return .firstChemistryEntry
        case .firstPoolStateQuestions: return .firstPoolStateQuestions
        case .firstTreatmentPlanOverview: return .firstTreatmentPlanOverview
        case .firstTreatmentCompletion: return .firstTreatmentCompletion
        case .firstTreatmentSkip: return .firstTreatmentSkip
        case .firstTreatmentReinstate: return .firstTreatmentReinstate
        case .firstWatchlist: return .firstWatchlist
        case .firstNextPoolTest: return .firstNextPoolTest
        case .firstDashboardScoreAndNextTest:
            return ContextualTipContent(id: id, title: "Your pool at a glance", body: "Your score summarizes your pool’s current condition. Next Test shows when Pool Side recommends testing again. If notifications are enabled, you’ll be reminded then.")
        case .firstDashboardRecentTests:
            return ContextualTipContent(id: id, title: "Your recent tests", body: "Your latest test history lives here so Pool Side can use trends and treatment outcomes over time.")
        case .firstDashboardNavigation:
            return ContextualTipContent(id: id, title: "Everything you need", body: "Dashboard shows what needs attention now. Insights shows trends. Use + anytime you want to log a new test.")
        case .firstRecoveryTreatment:
            return ContextualTipContent(id: id, title: "Recovery treatment", body: "Pool Side uses recovery steps when the water needs corrective care before returning to routine maintenance.")
        case .firstAcidTreatment:
            return ContextualTipContent(id: id, title: "Acid treatment", body: "Acid lowers pH. Follow the product label and let it circulate before swimming.")
        case .firstChlorineTreatment:
            return ContextualTipContent(id: id, title: "Chlorine treatment", body: "Chlorine raises sanitizer so the pool can stay protected.")
        case .firstCYAAdjustment:
            return ContextualTipContent(id: id, title: "Stabilizer adjustment", body: "Stabilizer helps chlorine last longer in sunlight, but too much changes the chlorine target.")
        case .firstPoolCareOnlyTreatment:
            return ContextualTipContent(id: id, title: "Pool care item", body: "Some items protect the pool over time without necessarily blocking swimming today.")
        }
    }
}

struct ContextualEducationRules {
    static func isTipEligible(_ id: ContextualTipID, actionableTreatmentCount: Int = 0, skippedTreatmentCount: Int = 0, watchlistCount: Int = 0, hasNextPoolTest: Bool = false) -> Bool {
        switch id {
        case .firstTreatmentCompletion, .firstTreatmentSkip:
            return actionableTreatmentCount > 0
        case .firstTreatmentReinstate:
            return skippedTreatmentCount > 0
        case .firstWatchlist:
            return watchlistCount > 0
        case .firstNextPoolTest:
            return hasNextPoolTest
        default:
            return true
        }
    }
}

struct ContextualTipPresentation: Equatable {
    let showsCloseButton: Bool
    let primaryActionTitle: String

    static let standalone = ContextualTipPresentation(
        showsCloseButton: false,
        primaryActionTitle: "Got It"
    )

    static func dashboardWalkthrough(stepIndex: Int, stepCount: Int) -> ContextualTipPresentation {
        ContextualTipPresentation(
            showsCloseButton: true,
            primaryActionTitle: stepIndex == stepCount - 1 ? "Got It" : "Next"
        )
    }
}
