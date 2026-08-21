import XCTest
import SwiftData
@testable import Pool_Side

/// Verifies that workflow reminders orphaned by plan regeneration / object removal are cancelled, while a
/// completed treatment schedules exactly one reminder for its current product and routine reminders survive.
/// Reuses `NotificationSchedulingSpy` from CheckVerificationLifecycleTests (same test target/module).
@MainActor
final class WorkflowNotificationReconciliationTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PoolTest.self, Treatment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeViewModel(spy: NotificationSchedulingSpy) -> PoolViewModel {
        let viewModel = PoolViewModel()
        viewModel.notificationSchedulerOverride = spy
        // Set in-memory only (never touches UserDefaults) so reminder gating is deterministic.
        viewModel.poolConfig = PoolConfiguration(volumeGallons: 15_000)
        return viewModel
    }

    private func makeTest(in context: ModelContext) -> PoolTest {
        let test = PoolTest(
            date: Date(), pH: 7.5, freeChlorine: 3.0, totalChlorine: 3.0,
            totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60
        )
        context.insert(test)
        return test
    }

    /// A Dry Acid pH correction that imposes a circulation wait but has NO dependent focused Check.
    private func makeDryAcid(on test: PoolTest) -> Treatment {
        let acid = Treatment(
            chemicalName: "Dry Acid (Sodium Bisulfate)",
            actionDescription: "Lower pH toward ~7.4",
            amount: 1.0,
            unit: "lb",
            productIdentifier: ChemicalProductID.dryAcid.rawValue,
            instructions: "Add dry acid, circulate.",
            urgency: .recommended,
            targetParameter: "pH",
            sortOrder: 1,
            effectDelayHours: 4,
            poolTest: test
        )
        test.treatments.append(acid)
        return acid
    }

    /// A completed chlorine treatment plus its dependent focused Check.
    private func makePlanWithCheck(in context: ModelContext) -> (PoolTest, Treatment, Treatment) {
        let test = makeTest(in: context)
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
        return (test, treatment, check)
    }

    private func waitID(for treatment: Treatment) -> String { "treatment-wait-\(treatment.id.uuidString)" }

    // Completing a Dry Acid treatment with a wait and no Check schedules exactly one wait reminder, for the
    // currently selected product, and no retest.
    func testCompletedDryAcidSchedulesExactlyOneWaitReminderAndNoRetest() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let test = makeTest(in: context)
        let acid = makeDryAcid(on: test)

        let outcome = await viewModel.completeTreatment(acid, in: [test], modelContext: context)

        guard case .waitCompleteScheduled = outcome else {
            return XCTFail("A wait-imposing treatment with no Check schedules a wait-complete reminder.")
        }
        XCTAssertEqual(spy.scheduledWaitCompleteTreatmentIDs, [acid.id], "Exactly one wait reminder, for this treatment.")
        XCTAssertEqual(spy.scheduledWaitCompleteNames, ["Dry Acid (Sodium Bisulfate)"], "Reminder references the current product.")
        XCTAssertEqual(spy.activeIdentifiers.filter { $0.hasPrefix("treatment-wait-") }, Set([waitID(for: acid)]))
        XCTAssertTrue(spy.scheduledCheckIDs.isEmpty, "No focused Check → no retest reminder.")
        XCTAssertTrue(spy.activeIdentifiers.filter { $0.hasPrefix("check-retest-") }.isEmpty)
    }

    // A stale Muriatic wait reminder from a prior generation does not survive completing the Dry Acid step.
    func testStaleMuriaticWaitReminderDoesNotSurvive() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let test = makeTest(in: context)
        let acid = makeDryAcid(on: test)

        let staleMuriatic = "treatment-wait-\(UUID().uuidString)"
        spy.seedActiveIdentifier(staleMuriatic)

        await viewModel.completeTreatment(acid, in: [test], modelContext: context)

        XCTAssertTrue(spy.didCancel(staleMuriatic), "The orphaned Muriatic wait reminder is cancelled.")
        XCTAssertFalse(spy.activeIdentifiers.contains(staleMuriatic))
        XCTAssertEqual(spy.activeIdentifiers.filter { $0.hasPrefix("treatment-wait-") }, Set([waitID(for: acid)]),
                       "Only the current Dry Acid wait reminder remains.")
    }

    // A treatment regenerated with a new UUID leaves its old wait reminder orphaned; reconciliation cancels it.
    func testRegeneratedTreatmentCancelsOldWaitReminder() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let test = makeTest(in: context)
        let acid = makeDryAcid(on: test)

        await viewModel.completeTreatment(acid, in: [test], modelContext: context)
        let oldWait = waitID(for: acid)
        XCTAssertTrue(spy.activeIdentifiers.contains(oldWait))

        // Simulate regeneration: the old treatment is deleted and replaced by a fresh one (new UUID).
        test.treatments.removeAll { $0.id == acid.id }
        context.delete(acid)
        _ = makeDryAcid(on: test)

        await viewModel.reconcileWorkflowNotifications(in: [test])

        XCTAssertTrue(spy.didCancel(oldWait), "The superseded treatment's wait reminder is cancelled.")
        XCTAssertFalse(spy.activeIdentifiers.contains(oldWait))
    }

    // A removed focused Check leaves its retest reminder orphaned; reconciliation cancels it.
    func testRemovedCheckCancelsOrphanRetestReminder() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let (test, treatment, check) = makePlanWithCheck(in: context)

        await viewModel.completeTreatment(treatment, in: [test], modelContext: context)
        let retestID = NotificationService.checkReminderIdentifier(for: check.id)
        XCTAssertTrue(spy.activeIdentifiers.contains(retestID), "Completing the parent schedules the Check's retest.")

        // Simulate regeneration removing the Check (a new plan would create one with a new UUID).
        test.treatments.removeAll { $0.id == check.id }
        context.delete(check)

        await viewModel.reconcileWorkflowNotifications(in: [test])

        XCTAssertTrue(spy.didCancel(retestID), "The orphaned Check retest reminder is cancelled.")
        XCTAssertFalse(spy.activeIdentifiers.contains(retestID))
    }

    // The routine next-test reminder is never a workflow family, so reconciliation always preserves it.
    func testRoutineNextTestReminderSurvivesReconciliation() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let test = makeTest(in: context)
        let acid = makeDryAcid(on: test)

        await viewModel.completeTreatment(acid, in: [test], modelContext: context)
        spy.seedActiveIdentifier(NotificationService.nextPoolTestIdentifier)
        spy.seedActiveIdentifier("treatment-wait-\(UUID().uuidString)") // an orphan to force cancellation work

        await viewModel.reconcileWorkflowNotifications(in: [test])

        XCTAssertTrue(spy.activeIdentifiers.contains(NotificationService.nextPoolTestIdentifier),
                      "Routine next-test reminder survives reconciliation.")
        XCTAssertFalse(spy.didCancel(NotificationService.nextPoolTestIdentifier))
    }

    // Reconciliation is idempotent: once orphans are cleared, a second pass cancels nothing further.
    func testReconciliationIsIdempotent() async throws {
        let context = try makeContext()
        let spy = NotificationSchedulingSpy()
        let viewModel = makeViewModel(spy: spy)
        let test = makeTest(in: context)
        let acid = makeDryAcid(on: test)

        await viewModel.completeTreatment(acid, in: [test], modelContext: context)
        spy.seedActiveIdentifier("treatment-wait-\(UUID().uuidString)")
        spy.seedActiveIdentifier("check-retest-\(UUID().uuidString)")

        await viewModel.reconcileWorkflowNotifications(in: [test])
        let cancelledAfterFirst = spy.cancelledIdentifiers.count
        XCTAssertGreaterThan(cancelledAfterFirst, 0, "The first pass clears the seeded orphans.")

        await viewModel.reconcileWorkflowNotifications(in: [test])

        XCTAssertEqual(spy.cancelledIdentifiers.count, cancelledAfterFirst,
                       "A second reconciliation cancels nothing new.")
        XCTAssertTrue(spy.activeIdentifiers.contains(waitID(for: acid)),
                      "The live Dry Acid wait reminder is preserved across both passes.")
    }
}
