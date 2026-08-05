import XCTest
import SwiftData
@testable import Pool_Side

/// Locks the Dashboard Active/Completed workflow presentation: state derivation, ordering, single-row
/// guarantee, evolving score, and accessibility — all from canonical workflow/score sources.
@MainActor
final class DashboardWorkflowTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PoolTest.self, Treatment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeViewModel() -> PoolViewModel {
        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false))
        return vm
    }

    private func poolTest(_ date: Date, pH: Double = 7.8) -> PoolTest {
        PoolTest(date: date, pH: pH, freeChlorine: 6, totalChlorine: 6,
                 totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
    }

    private func pendingTreatment(on test: PoolTest, target: String = "pH", order: Int = 1) -> Treatment {
        Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20, unit: "fl oz",
                  instructions: "", urgency: .recommended, targetParameter: target, sortOrder: order,
                  effectDelayHours: 4, poolTest: test)
    }

    private func completedTreatment(on test: PoolTest, at completedAt: Date, target: String = "pH") -> Treatment {
        Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20, unit: "fl oz",
                  instructions: "", urgency: .recommended, isCompleted: true, completedAt: completedAt,
                  targetParameter: target, sortOrder: 1, effectDelayHours: 4, poolTest: test)
    }

    // A. New test with incomplete treatment → Active / Treatment Needed / no score.
    func testIncompleteTreatmentIsActiveTreatmentNeeded() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date())
        let treatment = pendingTreatment(on: test)
        test.treatments = [treatment]
        context.insert(test)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        XCTAssertEqual(active.count, 1)
        XCTAssertTrue(completed.isEmpty)
        XCTAssertEqual(active.first?.state, .treatmentNeeded)
        XCTAssertNil(active.first?.finalScore)
    }

    // B. All treatments complete, Check pending → Active / Awaiting Pool Check / no score.
    func testCompletedTreatmentWithPendingCheckIsAwaitingPoolCheck() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date())
        let parent = completedTreatment(on: test, at: Date())
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        test.treatments = [parent, check]
        context.insert(test)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        XCTAssertEqual(active.first?.state, .awaitingPoolCheck)
        XCTAssertNil(active.first?.finalScore)
        XCTAssertTrue(completed.isEmpty)
    }

    // C. Check not yet due → still Awaiting; next-action uses the Check due time and is not actionable.
    func testCheckNotYetDueUsesCheckDueTimeForOrdering() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let test = poolTest(completedAt.addingTimeInterval(-3600))
        let parent = completedTreatment(on: test, at: completedAt)
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        test.treatments = [parent, check]
        context.insert(test)

        let due = TreatmentWorkflowEngine().availableDate(for: check, in: test.treatments)!
        // Evaluate 30 min after completion — before the pH Check's 4h due time.
        let (active, _) = vm.dashboardWorkflows(from: [test], evaluationDate: completedAt.addingTimeInterval(1800))
        XCTAssertEqual(active.first?.state, .awaitingPoolCheck)
        XCTAssertEqual(active.first?.nextActionDate, due)
        XCTAssertEqual(active.first?.isActionable, false)
    }

    // D. Overdue check sorts ahead of a future check.
    func testOverdueActionSortsBeforeFutureAction() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let now = Date(timeIntervalSince1970: 1_800_200_000)

        // Overdue check: parent completed long ago → due in the past.
        let overdueTest = poolTest(now.addingTimeInterval(-100_000))
        let overdueParent = completedTreatment(on: overdueTest, at: now.addingTimeInterval(-50_000))
        let overdueCheck = TreatmentWorkflowEngine().makeCheckStep(after: overdueParent, sortOrder: 2)!
        overdueTest.treatments = [overdueParent, overdueCheck]

        // Future check: parent completed just now → due 4h from now.
        let futureTest = poolTest(now.addingTimeInterval(-60))
        let futureParent = completedTreatment(on: futureTest, at: now)
        let futureCheck = TreatmentWorkflowEngine().makeCheckStep(after: futureParent, sortOrder: 2)!
        futureTest.treatments = [futureParent, futureCheck]

        context.insert(overdueTest); context.insert(futureTest)

        let (active, _) = vm.dashboardWorkflows(from: [futureTest, overdueTest], evaluationDate: now)
        XCTAssertEqual(active.count, 2)
        XCTAssertEqual(active.first?.rootTestID, overdueTest.id, "Overdue action must sort first.")
        XCTAssertEqual(active.last?.rootTestID, futureTest.id)
    }

    // E. Multiple incomplete treatments → one row for the root test, state Treatment Needed.
    func testMultipleIncompleteTreatmentsProduceSingleActiveRow() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date())
        test.treatments = [pendingTreatment(on: test, target: "pH", order: 1),
                           pendingTreatment(on: test, target: "totalAlkalinity", order: 2)]
        context.insert(test)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.state, .treatmentNeeded)
        XCTAssertTrue(completed.isEmpty)
    }

    // F. Completing a treatment (no new evidence) does not change the score.
    func testTreatmentCompletionAloneDoesNotChangeScore() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date(), pH: 7.8)
        let treatment = pendingTreatment(on: test)
        test.treatments = [treatment]
        context.insert(test)

        let before = vm.overallScore(for: test)
        await_completeTreatment(vm, treatment, test, context)
        let after = vm.overallScore(for: test)
        XCTAssertEqual(before, after, "Marking a treatment complete must not change the evidence-based score.")
    }

    private func await_completeTreatment(_ vm: PoolViewModel, _ t: Treatment, _ test: PoolTest, _ ctx: ModelContext) {
        let exp = expectation(description: "complete")
        Task { await vm.completeTreatment(t, in: [test], modelContext: ctx); exp.fulfill() }
        wait(for: [exp], timeout: 5)
    }

    // G. A focused Check updates the score from mixed-age evidence, changing only the checked parameter.
    func testFocusedCheckUpdatesScoreFromMeasuredEvidenceOnly() async throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date(), pH: 8.2)  // blocks swimming → acid generates a verification Check
        context.insert(test)
        await vm.generateRecommendations(for: test, recentTests: [], modelContext: context)
        let acid = try XCTUnwrap(test.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [test], modelContext: context)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))

        let taBefore = test.totalAlkalinity
        let scoreBefore = vm.overallScore(for: test)
        try await vm.saveFocusedCheck(check, values: ["pH": 7.6], for: test, allTests: [test], modelContext: context)

        XCTAssertEqual(test.pH, 7.6, "Only the checked parameter is updated.")
        XCTAssertEqual(test.totalAlkalinity, taBefore, "Unmeasured parameters keep prior evidence.")
        XCTAssertNotEqual(vm.overallScore(for: test), scoreBefore, "Score recalculates from new measured evidence.")
    }

    // H. A Check that generates another treatment returns the workflow to Treatment Needed (Active, no score).
    func testCheckGeneratingTreatmentReturnsToTreatmentNeeded() async throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date(), pH: 8.2)  // blocks swimming → acid generates a verification Check
        context.insert(test)
        await vm.generateRecommendations(for: test, recentTests: [], modelContext: context)
        let acid = try XCTUnwrap(test.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [test], modelContext: context)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))
        try await vm.saveFocusedCheck(check, values: ["pH": 7.7], for: test, allTests: [test], modelContext: context)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        XCTAssertEqual(active.first?.state, .treatmentNeeded)
        XCTAssertNil(active.first?.finalScore)
        XCTAssertTrue(completed.isEmpty)
    }

    // I + J. Final Check resolves the workflow → Completed, with the final evidence-based score (not initial).
    func testFinalCheckMovesToCompletedWithFinalEvidenceScore() async throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date(), pH: 8.2)  // blocks swimming → acid generates a verification Check
        context.insert(test)
        await vm.generateRecommendations(for: test, recentTests: [], modelContext: context)
        let initialScore = vm.overallScore(for: test)
        let acid = try XCTUnwrap(test.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [test], modelContext: context)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))
        try await vm.saveFocusedCheck(check, values: ["pH": 7.4], for: test, allTests: [test], modelContext: context)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        XCTAssertTrue(active.isEmpty)
        XCTAssertEqual(completed.count, 1)
        let finalScore = try XCTUnwrap(completed.first?.finalScore)
        XCTAssertEqual(finalScore, vm.overallScore(for: test))
        XCTAssertNotEqual(finalScore, initialScore, "Completed row uses final evidence, not the pre-treatment score.")
        XCTAssertNotNil(completed.first?.finalGrade)
    }

    // K. A later full test never completes a pending Check → the root workflow stays Active until the user
    //    completes the Check themselves. (Full-test supersession was removed.)
    func testLaterFullTestLeavesRootWorkflowActive() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let root = poolTest(completedAt.addingTimeInterval(-3600))
        let parent = completedTreatment(on: root, at: completedAt)
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        root.treatments = [parent, check]
        context.insert(root)

        // A later full test at +5h measures pH but must NOT complete the pending Check.
        let fresh = poolTest(completedAt.addingTimeInterval(5 * 3600), pH: 7.4)
        context.insert(fresh)

        let (active, completed) = vm.dashboardWorkflows(from: [fresh, root])
        XCTAssertTrue(active.contains { $0.rootTestID == root.id }, "The pending Check keeps the workflow Active.")
        XCTAssertFalse(completed.contains { $0.rootTestID == root.id })
    }

    // L. Skipping the parent (which cascades to the Check) completes the workflow; restoring reactivates it.
    func testParentSkipCompletesWorkflowAndRestoreReactivates() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date())
        let parent = pendingTreatment(on: test)
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        test.treatments = [parent, check]
        context.insert(test)

        vm.skipTreatment(parent)
        XCTAssertEqual(vm.dashboardWorkflows(from: [test]).completed.first?.rootTestID, test.id)

        vm.restoreTreatment(parent)
        XCTAssertEqual(vm.dashboardWorkflows(from: [test]).active.first?.state, .treatmentNeeded)
    }

    // M. Sections with zero items are represented as empty collections.
    func testEmptySectionsAreEmpty() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let activeOnly = poolTest(Date())
        activeOnly.treatments = [pendingTreatment(on: activeOnly)]
        context.insert(activeOnly)

        let (active, completed) = vm.dashboardWorkflows(from: [activeOnly])
        XCTAssertFalse(active.isEmpty)
        XCTAssertTrue(completed.isEmpty)
    }

    // N. Active ordering: earliest next required action first (available treatment before future check).
    func testActiveOrderingPrefersEarliestAction() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let now = Date(timeIntervalSince1970: 1_800_300_000)

        let treatmentTest = poolTest(now.addingTimeInterval(-10_000))
        treatmentTest.treatments = [pendingTreatment(on: treatmentTest)]

        let futureCheckTest = poolTest(now.addingTimeInterval(-60))
        let fp = completedTreatment(on: futureCheckTest, at: now)
        let fc = TreatmentWorkflowEngine().makeCheckStep(after: fp, sortOrder: 2)!
        futureCheckTest.treatments = [fp, fc]

        context.insert(treatmentTest); context.insert(futureCheckTest)

        let (active, _) = vm.dashboardWorkflows(from: [futureCheckTest, treatmentTest], evaluationDate: now)
        XCTAssertEqual(active.first?.rootTestID, treatmentTest.id, "Available treatment sorts before a future Check.")
    }

    // O. The root test appears in exactly one section.
    func testRootTestAppearsInExactlyOneSection() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let test = poolTest(Date())
        let parent = pendingTreatment(on: test)
        let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
        test.treatments = [parent, check]
        context.insert(test)

        let (active, completed) = vm.dashboardWorkflows(from: [test])
        let occurrences = (active + completed).filter { $0.rootTestID == test.id }.count
        XCTAssertEqual(occurrences, 1)
    }

    // P. Accessibility labels include date/time and either state or final score/grade.
    func testAccessibilityLabels() throws {
        let context = try makeContext()
        let vm = makeViewModel()
        let activeTest = poolTest(Date())
        activeTest.treatments = [pendingTreatment(on: activeTest)]
        let completedTest = poolTest(Date().addingTimeInterval(-86_400), pH: 7.4)
        context.insert(activeTest); context.insert(completedTest)

        let (active, completed) = vm.dashboardWorkflows(from: [activeTest, completedTest])
        XCTAssertTrue(active.first!.accessibilityLabel.localizedCaseInsensitiveContains("Treatment needed"))
        let completedLabel = try XCTUnwrap(completed.first?.accessibilityLabel)
        XCTAssertTrue(completedLabel.localizedCaseInsensitiveContains("Score"))
    }
}
