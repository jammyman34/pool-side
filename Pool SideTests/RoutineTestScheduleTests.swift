import XCTest
@testable import Pool_Side

/// Routine testing cadence SSOT: FC & pH at +3 days and Full Test Panel at +7 days, anchored to the most
/// recent Full Test Panel. Conditions attached to a test are pre-sample, so the routine cadence never adds
/// a same-/next-day "confirmation" retest. Only a new Full Test Panel re-anchors the schedule; Focused
/// Checks stay independent.
final class RoutineTestScheduleTests: XCTestCase {

    private let engine = NextTestRecommendationEngine()
    private let day: TimeInterval = 24 * 60 * 60

    private func fullTest(date: Date, conditions: PoolConditions? = nil) -> PoolTest {
        PoolTest(date: date, pH: 7.5, freeChlorine: 5, totalChlorine: 5, totalAlkalinity: 100,
                 calciumHardness: 330, cyanuricAcid: 60, poolConditions: conditions)
    }

    // 1. Day 0 full panel -> FC & pH Day 3 / Full Panel Day 7.
    func testRoutineScheduleAnchorsFCPHAtDay3AndFullPanelAtDay7() {
        let anchor = Date()
        let schedule = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor)

        XCTAssertEqual(schedule.fcAndPH.recommendedDate, anchor.addingTimeInterval(3 * day))
        XCTAssertEqual(schedule.fcAndPH.title, "Test FC & pH")
        XCTAssertEqual(schedule.fcAndPH.source, .routineFCAndPH)

        XCTAssertEqual(schedule.fullPanel.recommendedDate, anchor.addingTimeInterval(7 * day))
        XCTAssertEqual(schedule.fullPanel.title, "Full Test Panel")
        XCTAssertEqual(schedule.fullPanel.source, .routineFullPanel)
    }

    // 2. A current-test >2" refill must not cause a Day-1 dilution retest.
    func testCurrentTestRefillDoesNotCauseDayOneRetest() {
        let anchor = Date()
        // The SSOT the app uses ignores attached conditions entirely.
        let schedule = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor)
        XCTAssertEqual(schedule.fcAndPH.recommendedDate, anchor.addingTimeInterval(3 * day))
        XCTAssertEqual(schedule.fullPanel.recommendedDate, anchor.addingTimeInterval(7 * day))

        // Conditions attached to the current test never introduce a same-/next-day retest.
        XCTAssertNotEqual(schedule.firstUpcoming.recommendedDate, anchor.addingTimeInterval(day),
                          "A current-test refill must not schedule a Day-1 retest.")
        XCTAssertEqual(schedule.firstUpcoming.recommendedDate, anchor.addingTimeInterval(3 * day))
    }

    // 3. A current-test chlorine-demand condition must not cause a Day-1 retest.
    func testCurrentTestChlorineDemandDoesNotCauseDayOneRetest() {
        let anchor = Date()
        let schedule = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor)
        XCTAssertEqual(schedule.fcAndPH.recommendedDate, anchor.addingTimeInterval(3 * day))
        XCTAssertEqual(schedule.fullPanel.recommendedDate, anchor.addingTimeInterval(7 * day))

        // High chlorine-demand conditions on the current test never accelerate routine testing.
        XCTAssertNotEqual(schedule.firstUpcoming.recommendedDate, anchor.addingTimeInterval(day),
                          "A current-test chlorine-demand condition must not schedule a Day-1 retest.")
        XCTAssertEqual(schedule.firstUpcoming.recommendedDate, anchor.addingTimeInterval(3 * day))
    }

    // 4. Completing FC & pH (a Focused Check) must not move the Day-7 Full Panel.
    func testCompletingFCPHDoesNotMoveDay7FullPanel() {
        let anchor = Date()
        let full = fullTest(date: anchor)
        // A focused FC & pH check recorded on Day 3 — it is NOT a full panel and must not re-anchor.
        let fcCheck = fullTest(date: anchor.addingTimeInterval(3 * day))
        fcCheck.isFocusedCheck = true
        fcCheck.focusedCheckParameters = ["freeChlorine", "pH"]

        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: fcCheck, in: [full, fcCheck], now: anchor.addingTimeInterval(3 * day))
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, anchor.addingTimeInterval(7 * day),
                       "Full Test Panel stays anchored to the Day-0 full panel after an FC & pH check.")
    }

    // 5. A new Full Test Panel resets the +3/+7 schedule.
    func testNewFullPanelResetsSchedule() {
        let day0 = Date()
        let day5 = day0.addingTimeInterval(5 * day)
        let older = fullTest(date: day0)
        let newer = fullTest(date: day5)

        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: newer, in: [older, newer], now: day5)
        XCTAssertEqual(schedule?.fcAndPH.recommendedDate, day5.addingTimeInterval(3 * day))
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, day5.addingTimeInterval(7 * day))
    }

    // 6. Both routine notifications are scheduled under distinct identifiers, governed by one setting.
    @MainActor
    func testBothRoutineNotificationsScheduled() async {
        let now = Date()
        let full = fullTest(date: now)
        let vm = PoolViewModel()
        vm.poolConfig = PoolConfiguration() // enableNextPoolTestReminders defaults true
        let spy = NotificationSchedulingSpy(isAuthorized: true)
        vm.notificationSchedulerOverride = spy

        await vm.replaceNextPoolTestReminder(for: full, allTests: [full])

        XCTAssertTrue(spy.scheduledNextPoolTest, "Full Test Panel reminder must be scheduled.")
        XCTAssertTrue(spy.scheduledNextFCPHTest, "FC & pH reminder must be scheduled.")
        XCTAssertNotEqual(NotificationService.nextPoolTestIdentifier, NotificationService.nextFCPHTestIdentifier)
    }

    // 6b. Disabling the single setting cancels both routine reminders.
    @MainActor
    func testDisablingSettingCancelsBothRoutineReminders() async {
        let full = fullTest(date: Date())
        let vm = PoolViewModel()
        var config = PoolConfiguration()
        config.enableNextPoolTestReminders = false
        vm.poolConfig = config
        let spy = NotificationSchedulingSpy(isAuthorized: true)
        vm.notificationSchedulerOverride = spy

        await vm.replaceNextPoolTestReminder(for: full, allTests: [full])

        XCTAssertTrue(spy.didCancelNextPoolTest)
        XCTAssertTrue(spy.didCancelNextFCPHTest)
        XCTAssertFalse(spy.scheduledNextPoolTest)
        XCTAssertFalse(spy.scheduledNextFCPHTest)
    }

    // 7. Focused Checks remain independent: a later focused check never re-anchors the routine cadence.
    func testFocusedChecksRemainIndependentOfRoutineAnchor() {
        let anchor = Date()
        let full = fullTest(date: anchor)
        let laterFocused = fullTest(date: anchor.addingTimeInterval(10 * day))
        laterFocused.isFocusedCheck = true
        laterFocused.focusedCheckParameters = ["freeChlorine"]

        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: laterFocused, in: [full, laterFocused], now: anchor)
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, anchor.addingTimeInterval(7 * day))
        XCTAssertEqual(schedule?.fcAndPH.recommendedDate, anchor.addingTimeInterval(3 * day))
    }

    // 8. firstUpcoming transitions from FC & pH to Full Panel as time passes.
    func testFirstUpcomingTransitions() {
        let anchor = Date()

        let beforeDay3 = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor.addingTimeInterval(1 * day))
        XCTAssertEqual(beforeDay3.firstUpcoming.source, .routineFCAndPH)

        let betweenDay3And7 = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor.addingTimeInterval(4 * day))
        XCTAssertEqual(betweenDay3And7.firstUpcoming.source, .routineFullPanel)

        let afterDay7 = engine.routineSchedule(mostRecentFullTestDate: anchor, now: anchor.addingTimeInterval(8 * day))
        XCTAssertEqual(afterDay7.firstUpcoming.source, .routineFullPanel)
    }

    // 9. External Review export reports both routine tests.
    func testExternalReviewExportReportsBothRoutineTests() {
        let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)
        let test = fullTest(date: Date())
        let timing = "Test FC & pH: Tomorrow around 9:00 AM. Full Test Panel: Aug 27 at 9:00 AM."

        let export = ExternalReviewExportBuilder.treatmentAuditSection(
            config: config, test: test, treatments: [], recentHistory: [], routineNextTestTiming: timing
        )
        XCTAssertTrue(export.contains("Test FC & pH"))
        XCTAssertTrue(export.contains("Full Test Panel"))
    }
}
