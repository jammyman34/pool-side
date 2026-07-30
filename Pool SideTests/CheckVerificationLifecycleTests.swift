import XCTest
import SwiftData
@testable import Pool_Side

/// Records the notification effects the verification lifecycle drives, so Check-owned notification
/// ownership and cancellation are deterministically verifiable without device authorization.
@MainActor
final class NotificationSchedulingSpy: PoolNotificationScheduling {
    var isAuthorized: Bool
    private(set) var scheduledCheckIDs: [UUID] = []
    private(set) var scheduledStepTreatmentIDs: [UUID] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func checkAuthorizationStatus() async {}

    func scheduleCheckReminder(checkID: UUID, parameters: [String], at date: Date) async -> String? {
        guard isAuthorized else { return nil }
        scheduledCheckIDs.append(checkID)
        return NotificationService.checkReminderIdentifier(for: checkID)
    }

    func scheduleTreatmentStepReminder(treatmentID: UUID, nextTreatmentName: String, afterMinutes: Int) async -> String? {
        guard isAuthorized else { return nil }
        scheduledStepTreatmentIDs.append(treatmentID)
        return "treatment-step-\(treatmentID.uuidString)"
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    private(set) var didCancelNextPoolTest = false
    func cancelNextPoolTestReminder() {
        didCancelNextPoolTest = true
    }

    private(set) var scheduledNextPoolTest = false
    func replaceNextPoolTestReminder(at date: Date, reason: String) async -> String? {
        scheduledNextPoolTest = true
        return NotificationService.nextPoolTestIdentifier
    }

    func resetNextPoolTestFlag() {
        scheduledNextPoolTest = false
        didCancelNextPoolTest = false
    }

    func cancelTreatmentReminder(for treatment: Treatment) {
        [
            treatment.reminderNotificationIdentifier,
            treatment.stepReminderNotificationIdentifier,
            treatment.retestReminderNotificationIdentifier,
            treatment.checkReminderNotificationIdentifier
        ]
        .compactMap { $0 }
        .forEach { cancelledIdentifiers.append($0) }
        treatment.reminderNotificationIdentifier = nil
        treatment.stepReminderNotificationIdentifier = nil
        treatment.retestReminderNotificationIdentifier = nil
        treatment.checkReminderNotificationIdentifier = nil
    }

    // Test helpers
    var didScheduleAnyCheck: Bool { !scheduledCheckIDs.isEmpty }
    func didCancel(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return cancelledIdentifiers.contains(identifier)
    }
}

@MainActor
final class CheckVerificationLifecycleTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PoolTest.self, Treatment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Builds a persisted test with one chlorine treatment and its dependent focused Check.
    private func makePlanWithCheck(in context: ModelContext) -> (PoolTest, Treatment, Treatment) {
        let test = PoolTest(
            date: Date(),
            pH: 7.4,
            freeChlorine: 1.0,
            totalChlorine: 1.0,
            totalAlkalinity: 100,
            calciumHardness: 350,
            cyanuricAcid: 60
        )
        let treatment = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Raise free chlorine toward 7 ppm",
            amount: 0.75,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .recommended,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        let check = TreatmentWorkflowEngine().makeCheckStep(after: treatment, sortOrder: 2)!
        test.treatments = [treatment, check]
        context.insert(test)
        return (test, treatment, check)
    }

    private func makeViewModel(spy: NotificationSchedulingSpy) -> PoolViewModel {
        let viewModel = PoolViewModel()
        viewModel.notificationSchedulerOverride = spy
        return viewModel
    }

    // §1 / §22 — Completing a treatment schedules exactly one Check-OWNED verification notification,
    // whose identifier is stored on the Check (not the parent treatment), and no treatment-owned retest.
    func testCompletingTreatmentSchedulesCheckOwnedNotification() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)

        XCTAssertTrue(treatment.isCompleted)
        XCTAssertEqual(spy.scheduledCheckIDs, [check.id], "The Check owns the one verification notification.")
        XCTAssertEqual(check.checkReminderNotificationIdentifier, NotificationService.checkReminderIdentifier(for: check.id))
        XCTAssertNil(treatment.retestReminderNotificationIdentifier, "Treatment-owned retest notifications are removed.")
        XCTAssertNil(treatment.stepReminderNotificationIdentifier, "No next-step reminder when the only successor is the Check.")
        XCTAssertTrue(spy.scheduledStepTreatmentIDs.isEmpty)
    }

    // §4 / §22 — Completing the focused Check cancels its own verification notification.
    func testCompletingCheckCancelsItsNotification() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        let checkIdentifier = check.checkReminderNotificationIdentifier
        XCTAssertNotNil(checkIdentifier)

        try await viewModel.saveFocusedCheck(
            check,
            values: ["freeChlorine": 7.0],
            for: test,
            allTests: [test],
            modelContext: context
        )

        XCTAssertTrue(check.isCompleted)
        XCTAssertTrue(spy.didCancel(checkIdentifier), "Completing the Check cancels its verification reminder.")
        XCTAssertNil(check.checkReminderNotificationIdentifier)
    }

    // §5 — Skipping the parent treatment cascades: the dependent Check is skipped and its notification cancelled.
    func testSkippingParentCascadeSkipsCheckAndCancelsNotification() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        let checkIdentifier = check.checkReminderNotificationIdentifier

        viewModel.skipTreatment(treatment)

        XCTAssertTrue(treatment.isSkipped)
        XCTAssertTrue(check.isSkipped, "A skipped treatment's Check must never become actionable.")
        XCTAssertTrue(spy.didCancel(checkIdentifier))
        XCTAssertNil(check.checkReminderNotificationIdentifier)
    }

    // §5 — Restoring the parent un-skips the dependent Check (which is not yet due).
    func testRestoringParentUnskipsCheck() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        viewModel.skipTreatment(treatment)
        XCTAssertTrue(check.isSkipped)

        viewModel.restoreTreatment(treatment)

        XCTAssertFalse(treatment.isSkipped)
        XCTAssertFalse(check.isSkipped, "Restoring the parent restores its dependent Check.")
    }

    // Reverting a completed treatment invalidates its Check's due-time notification.
    func testMarkingTreatmentIncompleteCancelsCheckNotification() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        let checkIdentifier = check.checkReminderNotificationIdentifier

        viewModel.markTreatmentIncomplete(treatment)

        XCTAssertFalse(treatment.isCompleted)
        XCTAssertTrue(spy.didCancel(checkIdentifier))
        XCTAssertNil(check.checkReminderNotificationIdentifier)
    }

    // §7 / §8 — Recording ideal evidence via the Check regenerates from measured state and carries
    // NO stored theoretical remainder: no pending chemical treatment for the now-ideal parameter.
    func testIdealCheckEvidenceLeavesNoRemainderTreatment() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)

        try await viewModel.saveFocusedCheck(
            check,
            values: ["freeChlorine": 8.0, "combinedChlorine": 0.0],
            for: test,
            allTests: [test],
            modelContext: context
        )

        XCTAssertEqual(test.freeChlorine, 8.0, "Measured evidence is applied to the parameter.")
        let pendingChlorine = test.treatments.filter {
            !$0.isCompleted && !$0.isSkipped && !$0.isFocusedCheckStep
                && $0.targetParameter == "freeChlorine" && $0.amount > 0
        }
        XCTAssertTrue(pendingChlorine.isEmpty, "Ideal measured FC leaves no carried-forward chlorine treatment.")
    }

    // §8 — Real two-stage pH verification lifecycle: 7.8 → treat → Check 7.7 → re-treat → Check 7.4 → stop.
    // Proves each stage re-treats from freshly MEASURED evidence and that reaching ideal leaves no
    // carried-forward "remainder" pH treatment.
    private func pendingPHAcid(on test: PoolTest, viewModel: PoolViewModel) -> Treatment? {
        test.treatments.first {
            !$0.isCompleted && !$0.isSkipped && !$0.isFocusedCheckStep
                && $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0
        }
    }

    func testTwoStagePHVerificationLifecycleCarriesNoRemainder() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        viewModel.saveConfig(PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false))

        // Fresh, no-history plaster pool: only pH is out of the operating range.
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_100_000), pH: 7.8,
                            freeChlorine: 8, totalChlorine: 8, totalAlkalinity: 100,
                            calciumHardness: 350, cyanuricAcid: 60)
        context.insert(test)
        await viewModel.generateRecommendations(for: test, recentTests: [], modelContext: context)

        // Stage 1: 7.8 generates a Recommended acid correction with a dependent Check.
        let acid1 = try XCTUnwrap(pendingPHAcid(on: test, viewModel: viewModel), "pH 7.8 must generate an acid correction.")
        XCTAssertEqual(acid1.urgency, .recommended)
        await viewModel.completeTreatment(acid1, in: [test], modelContext: context)
        let check1 = try XCTUnwrap(viewModel.dependentCheck(for: acid1), "Completing the acid creates a pH Check.")

        // Measure 7.7 — still above the operating range, so a NEW correction is generated from evidence.
        try await viewModel.saveFocusedCheck(check1, values: ["pH": 7.7], for: test, allTests: [test], modelContext: context)
        XCTAssertEqual(test.pH, 7.7)
        let acid2 = try XCTUnwrap(pendingPHAcid(on: test, viewModel: viewModel), "pH 7.7 must re-treat from measured evidence.")
        XCTAssertNotEqual(acid2.id, acid1.id, "The re-treatment is a fresh step, not the completed one.")

        // Stage 2: complete the second acid, then measure 7.4 (ideal) — the workflow stops, no remainder.
        await viewModel.completeTreatment(acid2, in: [test], modelContext: context)
        let check2 = try XCTUnwrap(viewModel.dependentCheck(for: acid2))
        try await viewModel.saveFocusedCheck(check2, values: ["pH": 7.4], for: test, allTests: [test], modelContext: context)

        XCTAssertEqual(test.pH, 7.4)
        XCTAssertNil(pendingPHAcid(on: test, viewModel: viewModel),
                     "Reaching the ideal pH leaves no carried-forward remainder correction.")
    }

    // MARK: - Full-test supersession (§11–12 / §21)

    /// Builds a persisted, already-completed chlorine treatment with a pending Check whose verification
    /// notification is considered scheduled. Check due time = parentCompletedAt + 1 hour.
    private func makeCompletedPlanWithScheduledCheck(
        parentCompletedAt: Date,
        in context: ModelContext
    ) -> (PoolTest, Treatment, Treatment) {
        let test = PoolTest(
            date: parentCompletedAt.addingTimeInterval(-3600),
            pH: 7.4, freeChlorine: 1.0, totalChlorine: 1.0,
            totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60
        )
        let parent = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Raise free chlorine toward 7 ppm",
            amount: 0.75,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .recommended,
            isCompleted: true,
            completedAt: parentCompletedAt,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        check.checkReminderNotificationIdentifier = NotificationService.checkReminderIdentifier(for: check.id)
        test.treatments = [parent, check]
        context.insert(test)
        return (test, parent, check)
    }

    private func makeFullTest(date: Date, in context: ModelContext) -> PoolTest {
        let test = PoolTest(
            date: date, pH: 7.4, freeChlorine: 7.0, totalChlorine: 7.0,
            totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60
        )
        context.insert(test)
        return test
    }

    // §11 — A due full test with no intervening treatment supersedes the Check and cancels its reminder.
    func testDueFullTestSupersedesPendingCheck() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let parentCompletedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let (old, _, check) = makeCompletedPlanWithScheduledCheck(parentCompletedAt: parentCompletedAt, in: context)
        let identifier = check.checkReminderNotificationIdentifier

        let fresh = makeFullTest(date: parentCompletedAt.addingTimeInterval(2 * 3600), in: context)
        viewModel.resolveChecksSatisfiedByFullTest(fresh, allTests: [old, fresh], modelContext: context)

        XCTAssertTrue(check.isCompleted, "A due full test verifies the pending Check.")
        XCTAssertEqual(check.checkResultTestID, fresh.id)
        XCTAssertTrue(spy.didCancel(identifier))
        XCTAssertNil(check.checkReminderNotificationIdentifier)
    }

    // §12 — A full test logged before the Check is due does NOT verify.
    func testFullTestBeforeCheckDueDoesNotSupersede() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let parentCompletedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let (old, _, check) = makeCompletedPlanWithScheduledCheck(parentCompletedAt: parentCompletedAt, in: context)
        let identifier = check.checkReminderNotificationIdentifier

        // 30 minutes after completion — before the 1-hour due time.
        let early = makeFullTest(date: parentCompletedAt.addingTimeInterval(1800), in: context)
        viewModel.resolveChecksSatisfiedByFullTest(early, allTests: [old, early], modelContext: context)

        XCTAssertFalse(check.isCompleted, "A full test before the Check is due must not verify it.")
        XCTAssertFalse(spy.didCancel(identifier), "The Check reminder remains scheduled.")
        XCTAssertNotNil(check.checkReminderNotificationIdentifier)
    }

    // §11 — An intervening treatment affecting the same parameter blocks supersession.
    func testInterveningTreatmentBlocksSupersession() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let parentCompletedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let (old, _, check) = makeCompletedPlanWithScheduledCheck(parentCompletedAt: parentCompletedAt, in: context)

        // A second chlorine dose completed AFTER the parent but BEFORE the fresh test.
        let intervening = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Additional chlorine",
            amount: 0.5,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .recommended,
            isCompleted: true,
            completedAt: parentCompletedAt.addingTimeInterval(3000),
            targetParameter: "freeChlorine",
            sortOrder: 3,
            effectDelayHours: 1,
            poolTest: old
        )
        old.treatments.append(intervening)

        let fresh = makeFullTest(date: parentCompletedAt.addingTimeInterval(2 * 3600), in: context)
        viewModel.resolveChecksSatisfiedByFullTest(fresh, allTests: [old, fresh], modelContext: context)

        XCTAssertFalse(check.isCompleted, "An intervening same-parameter treatment blocks clean verification.")
        XCTAssertNotNil(check.checkReminderNotificationIdentifier)
    }

    // §11 — A full test older than the parent's completion cannot verify.
    func testFullTestBeforeParentCompletionDoesNotSupersede() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let parentCompletedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let (old, _, check) = makeCompletedPlanWithScheduledCheck(parentCompletedAt: parentCompletedAt, in: context)

        let stale = makeFullTest(date: parentCompletedAt.addingTimeInterval(-60), in: context)
        viewModel.resolveChecksSatisfiedByFullTest(stale, allTests: [old, stale], modelContext: context)

        XCTAssertFalse(check.isCompleted)
        XCTAssertNotNil(check.checkReminderNotificationIdentifier)
    }

    // MARK: - Focused-Check / routine full-test coordination (§13–18)

    private func pendingPHTreatment(on test: PoolTest) -> Treatment {
        Treatment(
            chemicalName: "Muriatic Acid",
            actionDescription: "Lower pH toward ~7.4",
            amount: 20,
            unit: "fl oz",
            instructions: "Add conservative dose, circulate, then retest.",
            urgency: .recommended,
            targetParameter: "pH",
            sortOrder: 1,
            effectDelayHours: 4,
            poolTest: test
        )
    }

    // §13/§14 (Test 1) — With an outstanding Check due AFTER the base routine date, the routine full test
    // is not blindly retained; it is re-anchored to after the Check's due time using the engine's cadence.
    func testRoutineFullTestDefersWhenCheckDueLaterThanRoutine() {
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_100_000), pH: 7.8,
                            freeChlorine: 6, totalChlorine: 6, totalAlkalinity: 100,
                            calciumHardness: 350, cyanuricAcid: 60)
        let pending = pendingPHTreatment(on: test)
        let checkDue = test.date.addingTimeInterval(30 * 3600) // later than the 24h routine follow-up

        let rec = NextTestRecommendationEngine().recommendation(
            for: test, treatmentSteps: [pending], watchlist: [], recentHistory: [],
            config: PoolConfiguration(), outstandingCheckDueDates: [checkDue]
        )

        // Base routine would be test.date + 24h; because the Check is due later (30h), the routine test is
        // re-anchored to checkDue + the same 24h cadence — never left on the stale earlier timestamp.
        XCTAssertEqual(rec.recommendedDate, checkDue.addingTimeInterval(24 * 3600))
        XCTAssertTrue(rec.body.localizedCaseInsensitiveContains("focused re-test"))
    }

    // §13 — When the routine full test is independently due later than the Check, it is left untouched
    // (the Check is handled by its own owned notification / supersession).
    func testRoutineFullTestUnchangedWhenAlreadyLaterThanCheck() {
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_100_000), pH: 7.8,
                            freeChlorine: 6, totalChlorine: 6, totalAlkalinity: 100,
                            calciumHardness: 350, cyanuricAcid: 60)
        let pending = pendingPHTreatment(on: test)
        let checkDue = test.date.addingTimeInterval(2 * 3600) // earlier than the 24h routine follow-up

        let rec = NextTestRecommendationEngine().recommendation(
            for: test, treatmentSteps: [pending], watchlist: [], recentHistory: [],
            config: PoolConfiguration(), outstandingCheckDueDates: [checkDue]
        )

        XCTAssertEqual(rec.recommendedDate, test.date.addingTimeInterval(24 * 3600),
                       "A routine test already due after the Check is not deferred.")
    }

    // §17 (Test 6) — With multiple outstanding Checks, routine testing is anchored past the LAST one, so no
    // routine full test is inserted between them.
    func testRoutineFullTestAnchorsPastLatestOfMultipleChecks() {
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_100_000), pH: 7.8,
                            freeChlorine: 6, totalChlorine: 6, totalAlkalinity: 100,
                            calciumHardness: 350, cyanuricAcid: 60)
        let pending = pendingPHTreatment(on: test)
        let firstDue = test.date.addingTimeInterval(26 * 3600)
        let lastDue = test.date.addingTimeInterval(40 * 3600)

        let rec = NextTestRecommendationEngine().recommendation(
            for: test, treatmentSteps: [pending], watchlist: [], recentHistory: [],
            config: PoolConfiguration(), outstandingCheckDueDates: [firstDue, lastDue]
        )

        XCTAssertEqual(rec.recommendedDate, lastDue.addingTimeInterval(24 * 3600),
                       "Routine testing anchors past the latest outstanding Check.")
    }

    // §16 / item 2C (Test 5) — Saving a focused Check recomputes the routine Next Full Pool Test reminder
    // from the new evidence rather than silently retaining the previous routine schedule.
    func testSavingCheckRecomputesRoutineNextTestReminder() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        spy.resetNextPoolTestFlag()

        try await viewModel.saveFocusedCheck(
            check, values: ["freeChlorine": 8.0, "combinedChlorine": 0.0],
            for: test, allTests: [test], modelContext: context
        )

        XCTAssertTrue(spy.scheduledNextPoolTest || spy.didCancelNextPoolTest,
                      "Completing a Check recomputes (schedules or cancels) the routine next-test reminder.")
    }

    // §20 — Persistence: the Check-owned identifier survives a fresh ModelContext over the same store.
    func testCheckNotificationIdentifierPersistsAcrossContexts() async throws {
        let container = try ModelContainer(
            for: PoolTest.self, Treatment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)
        let checkID = check.id

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        try context.save()

        let freshContext = ModelContext(container)
        let reloaded = try freshContext.fetch(FetchDescriptor<Treatment>())
            .first { $0.id == checkID }
        XCTAssertEqual(
            reloaded?.checkReminderNotificationIdentifier,
            NotificationService.checkReminderIdentifier(for: checkID),
            "The Check-owned notification identifier is durable across relaunch."
        )
    }
}
