import Foundation

/// Resolves the first-use shell state from durable app data plus transient flow state.
struct FirstUseStateResolver {
    enum State: Equatable {
        case welcome
        case poolSetup
        case firstTestEmptyDashboard
        case firstTestInProgress
        case firstTestCompletedTreatmentPlan
        case normalDashboard
    }

    static func resolve(
        isConfigurationPersisted: Bool,
        configuration: PoolConfiguration,
        savedTestCount: Int,
        hasStartedSetup: Bool = false,
        firstTestFlowInProgress: Bool = false,
        firstTestTreatmentPlanDisplayed: Bool = false
    ) -> State {
        if savedTestCount > 0 {
            return .normalDashboard
        }

        guard isSetupComplete(configuration, isPersisted: isConfigurationPersisted) else {
            return hasStartedSetup ? .poolSetup : .welcome
        }

        if firstTestTreatmentPlanDisplayed {
            return .firstTestCompletedTreatmentPlan
        }

        if firstTestFlowInProgress {
            return .firstTestInProgress
        }

        return .firstTestEmptyDashboard
    }

    static func isSetupComplete(_ configuration: PoolConfiguration, isPersisted: Bool) -> Bool {
        isPersisted && configuration.volumeGallons > 0
    }
}
