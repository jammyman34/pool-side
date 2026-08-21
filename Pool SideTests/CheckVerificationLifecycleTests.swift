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
    private(set) var scheduledWaitCompleteNames: [String] = []
    private(set) var cancelledIdentifiers: [String] = []
    private(set) var activeIdentifiers: Set<String> = []

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func checkAuthorizationStatus() async {}

    func scheduleCheckReminder(checkID: UUID, parameters: [String], at date: Date) async -> String? {
        guard isAuthorized else { return nil }
        let identifier = NotificationService.checkReminderIdentifier(for: checkID)
        scheduledCheckIDs.append(checkID)
        activeIdentifiers.insert(identifier)
        return identifier
    }

    func scheduleTreatmentStepReminder(treatmentID: UUID, nextTreatmentName: String, afterMinutes: Int) async -> String? {
        guard isAuthorized else { return nil }
        let identifier = "treatment-step-\(treatmentID.uuidString)"
        scheduledStepTreatmentIDs.append(treatmentID)
        activeIdentifiers.insert(identifier)
        return identifier
    }

    private(set) var scheduledWaitCompleteTreatmentIDs: [UUID] = []
    func scheduleWaitCompleteReminder(treatmentID: UUID, treatmentName: String, afterMinutes: Int) async -> String? {
        guard isAuthorized else { return nil }
        let identifier = "treatment-wait-\(treatmentID.uuidString)"
        scheduledWaitCompleteTreatmentIDs.append(treatmentID)
        scheduledWaitCompleteNames.append(treatmentName)
        activeIdentifiers.insert(identifier)
        return identifier
    }

    func reconcileWorkflowNotifications(keeping validIdentifiers: Set<String>) async {
        let orphans = activeIdentifiers.filter {
            NotificationService.isWorkflowNotification($0) && !validIdentifiers.contains($0)
        }
        for identifier in orphans { cancel(identifier: identifier) }
    }

    /// Test-only: represent an already-pending notification (e.g. a routine reminder or a stale orphan)
    /// so reconciliation behavior against real pending requests can be exercised deterministically.
    func seedActiveIdentifier(_ identifier: String) {
        activeIdentifiers.insert(identifier)
    }

    func cancel(identifier: String) {
        cancelledIdentifiers.append(identifier)
        activeIdentifiers.remove(identifier)
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

    private(set) var didCancelNextFCPHTest = false
    func cancelNextFCPHTestReminder() {
        didCancelNextFCPHTest = true
    }

    private(set) var scheduledNextFCPHTest = false
    func replaceNextFCPHTestReminder(at date: Date, reason: String) async -> String? {
        scheduledNextFCPHTest = true
        return NotificationService.nextFCPHTestIdentifier
    }

    func resetNextPoolTestFlag() {
        scheduledNextPoolTest = false
        didCancelNextPoolTest = false
        scheduledNextFCPHTest = false
        didCancelNextFCPHTest = false
    }

    func cancelTreatmentReminder(for treatment: Treatment) {
        [
            treatment.reminderNotificationIdentifier,
            treatment.stepReminderNotificationIdentifier,
            treatment.retestReminderNotificationIdentifier,
            treatment.checkReminderNotificationIdentifier
        ]
        .compactMap { $0 }
        .forEach {
            cancelledIdentifiers.append($0)
            activeIdentifiers.remove($0)
        }
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
final class CheckVerificationLifecycleTests: ConfigIsolatedTestCase {

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
            actionDescription: "Raise free chlorine toward 3 ppm",
            amount: 0.5,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .needsAttention,
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
        let firstIdentifier = check.checkReminderNotificationIdentifier
        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)

        XCTAssertEqual(spy.scheduledCheckIDs, [check.id, check.id])
        XCTAssertTrue(spy.didCancel(firstIdentifier), "Re-completing cancels the prior Check reminder before scheduling the current one.")
        XCTAssertEqual(spy.activeIdentifiers, Set([NotificationService.checkReminderIdentifier(for: check.id)]))
        XCTAssertTrue(spy.scheduledWaitCompleteTreatmentIDs.isEmpty)
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

        // Fresh, no-history plaster pool: pH is high enough to block swimming (verification required).
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_100_000), pH: 8.2,
                            freeChlorine: 8, totalChlorine: 8, totalAlkalinity: 100,
                            calciumHardness: 350, cyanuricAcid: 60)
        context.insert(test)
        await viewModel.generateRecommendations(for: test, recentTests: [], modelContext: context)

        // Stage 1: pH 8.2 blocks swimming, so the acid correction generates a dependent verification Check.
        let acid1 = try XCTUnwrap(pendingPHAcid(on: test, viewModel: viewModel), "pH 8.2 must generate an acid correction.")
        await viewModel.completeTreatment(acid1, in: [test], modelContext: context)
        let check1 = try XCTUnwrap(viewModel.dependentCheck(for: acid1), "Completing the acid creates a pH Check.")

        // Measure 7.9 — still blocks swimming, so a NEW correction (with its own Check) is generated.
        try await viewModel.saveFocusedCheck(check1, values: ["pH": 7.9], for: test, allTests: [test], modelContext: context)
        XCTAssertEqual(test.pH, 7.9)
        let acid2 = try XCTUnwrap(pendingPHAcid(on: test, viewModel: viewModel), "pH 7.9 must re-treat from measured evidence.")
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
            actionDescription: "Raise free chlorine toward 3 ppm",
            amount: 0.5,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .needsAttention,
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

    // A focused Check is completed ONLY by the user's measured result. Logging a full pool test — even a
    // fresh one, dated after the Check's due time, that measures the Check's parameter — never completes it,
    // never becomes its verification evidence, and never cancels its reminder. (Full-test supersession was
    // removed: logging a full test does not prove the user performed the treatment's follow-up measurement.)
    func testFullTestNeverAutoCompletesPendingCheck() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        _ = makeViewModel(spy: spy)
        let parentCompletedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let (_, _, check) = makeCompletedPlanWithScheduledCheck(parentCompletedAt: parentCompletedAt, in: context)
        let identifier = check.checkReminderNotificationIdentifier

        // A fresh full test measuring every parameter, dated two hours after the Check became due.
        _ = makeFullTest(date: parentCompletedAt.addingTimeInterval(2 * 3600), in: context)

        XCTAssertFalse(check.isCompleted, "Logging a full test must never complete a pending Check.")
        XCTAssertNil(check.checkResultTestID, "A full test never becomes a Check's verification evidence.")
        XCTAssertNotNil(check.checkReminderNotificationIdentifier, "The Check's reminder stays scheduled.")
        XCTAssertFalse(spy.didCancel(identifier), "Logging a full test does not cancel the Check reminder.")
    }

    // MARK: - Focused-Check / routine full-test coordination

    // NOTE: Routine full testing no longer defers around outstanding focused Checks. Routine cadence is
    // owned by `NextTestRecommendationEngine.routineSchedule(...)` (FC & pH +3d, Full Panel +7d), anchored
    // to the most recent Full Test Panel and independent of Checks (see RoutineTestScheduleTests). The
    // former `recommendation(...)`/`coordinatingWithOutstandingChecks(...)` deferral path has been retired,
    // so its three unit tests were removed with it. Check-owned reminder recomputation is still covered by
    // `testSavingCheckRecomputesRoutineNextTestReminder` below.

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
