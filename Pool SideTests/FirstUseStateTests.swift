import XCTest
@testable import Pool_Side

final class FirstUseStateTests: XCTestCase {
    func testIncompletePoolSetupSelectsWelcomeFlow() {
        let config = PoolConfiguration(volumeGallons: 0)

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: false,
            configuration: config,
            savedTestCount: 0
        )

        XCTAssertEqual(state, .welcome)
    }

    func testStartedIncompletePoolSetupSelectsSetupFlow() {
        let config = PoolConfiguration(volumeGallons: 0)

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: false,
            configuration: config,
            savedTestCount: 0,
            hasStartedSetup: true
        )

        XCTAssertEqual(state, .poolSetup)
    }

    func testCompleteSetupWithZeroTestsSelectsFirstTestDashboard() {
        let config = completeConfiguration()

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: true,
            configuration: config,
            savedTestCount: 0
        )

        XCTAssertEqual(state, .firstTestEmptyDashboard)
    }

    func testOneOrMoreTestsSelectsNormalDashboard() {
        let config = completeConfiguration()

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: true,
            configuration: config,
            savedTestCount: 1
        )

        XCTAssertEqual(state, .normalDashboard)
    }

    func testExistingUsersWithTestsBypassOnboardingEvenWhenSetupFlagIsIncomplete() {
        let config = PoolConfiguration(volumeGallons: 0)

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: false,
            configuration: config,
            savedTestCount: 3,
            hasStartedSetup: false
        )

        XCTAssertEqual(state, .normalDashboard)
    }

    func testRemovingGraduationAnimationDoesNotAffectFirstUseStateSelection() {
        let config = completeConfiguration()

        let state = FirstUseStateResolver.resolve(
            isConfigurationPersisted: true,
            configuration: config,
            savedTestCount: 1,
            firstTestFlowInProgress: false,
            firstTestTreatmentPlanDisplayed: true
        )

        XCTAssertEqual(state, .normalDashboard)
    }

    func testDeclinedNotificationPermissionDoesNotBlockSetupCompletion() {
        let config = PoolConfiguration(
            volumeGallons: 16000,
            enableNextPoolTestReminders: false,
            enableTreatmentStepReminders: false
        )

        XCTAssertTrue(FirstUseStateResolver.isSetupComplete(config, isPersisted: true))
    }

    private func completeConfiguration() -> PoolConfiguration {
        PoolConfiguration(volumeGallons: 18000)
    }
}
