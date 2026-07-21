import XCTest
@testable import Pool_Side

final class ContextualEducationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ContextualEducationStore!

    override func setUp() {
        super.setUp()
        suiteName = "PoolSide.ContextualEducationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = ContextualEducationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStandaloneTipStartsUnseenAndGotItMarksSeen() {
        XCTAssertFalse(store.hasSeen(.firstChemistryEntry))

        store.markSeen(.firstChemistryEntry)

        XCTAssertTrue(store.hasSeen(.firstChemistryEntry))
    }

    func testStandaloneTipHasNoCloseDismissalPath() {
        XCTAssertFalse(ContextualTipPresentation.standalone.showsCloseButton)
        XCTAssertEqual(ContextualTipPresentation.standalone.primaryActionTitle, "Got It")
    }

    func testDashboardWalkthroughCompletionMarksAllDashboardStepsSeen() {
        store.markSeen(.dashboard)

        XCTAssertTrue(store.hasSeen(.dashboard))
        XCTAssertTrue(store.hasSeen(.firstDashboardScoreAndNextTest))
        XCTAssertTrue(store.hasSeen(.firstDashboardRecentTests))
        XCTAssertTrue(store.hasSeen(.firstDashboardNavigation))
    }

    func testDashboardXDismissalMarksEntireWalkthroughSeen() {
        store.markSeen(.dashboard)

        XCTAssertTrue(store.hasSeen(.dashboard))
    }

    func testResetInfoTipsClearsAllSeenState() {
        store.markSeen(.firstChemistryEntry)
        store.markSeen(.firstWatchlist)

        store.resetAll()

        XCTAssertFalse(store.hasSeen(.firstChemistryEntry))
        XCTAssertFalse(store.hasSeen(.firstWatchlist))
    }

    func testResetDoesNotAlterPoolTestOrConfigurationData() {
        let config = PoolConfiguration(volumeGallons: 32_583)
        let test = PoolTest(pH: 7.6, freeChlorine: 4.5, totalChlorine: 5.0)
        store.markSeen(.firstChemistryEntry)

        store.resetAll()

        XCTAssertEqual(config.volumeGallons, 32_583)
        XCTAssertEqual(test.pH, 7.6)
        XCTAssertEqual(test.freeChlorine, 4.5)
    }

    func testWatchlistTipOnlyEligibleWhenWatchlistExists() {
        XCTAssertFalse(ContextualEducationRules.isTipEligible(.firstWatchlist, watchlistCount: 0))
        XCTAssertTrue(ContextualEducationRules.isTipEligible(.firstWatchlist, watchlistCount: 1))
    }

    func testTreatmentCompletionAndSkipTipsOnlyEligibleWhenActionableTreatmentExists() {
        XCTAssertFalse(ContextualEducationRules.isTipEligible(.firstTreatmentCompletion, actionableTreatmentCount: 0))
        XCTAssertFalse(ContextualEducationRules.isTipEligible(.firstTreatmentSkip, actionableTreatmentCount: 0))
        XCTAssertTrue(ContextualEducationRules.isTipEligible(.firstTreatmentCompletion, actionableTreatmentCount: 1))
        XCTAssertTrue(ContextualEducationRules.isTipEligible(.firstTreatmentSkip, actionableTreatmentCount: 1))
    }

    func testReinstateTipOnlyEligibleAfterSkippedTreatmentExists() {
        XCTAssertFalse(ContextualEducationRules.isTipEligible(.firstTreatmentReinstate, skippedTreatmentCount: 0))
        XCTAssertTrue(ContextualEducationRules.isTipEligible(.firstTreatmentReinstate, skippedTreatmentCount: 1))
    }

    func testNextPoolTestTipOnlyEligibleWhenNextPoolTestExists() {
        XCTAssertFalse(ContextualEducationRules.isTipEligible(.firstNextPoolTest, hasNextPoolTest: false))
        XCTAssertTrue(ContextualEducationRules.isTipEligible(.firstNextPoolTest, hasNextPoolTest: true))
    }

    func testFirstChemistryTipDoesNotRepeat() {
        store.markSeen(.firstChemistryEntry)

        XCTAssertTrue(store.hasSeen(.firstChemistryEntry))
    }

    func testFirstPoolStateTipDoesNotRepeat() {
        store.markSeen(.firstPoolStateQuestions)

        XCTAssertTrue(store.hasSeen(.firstPoolStateQuestions))
    }
}
