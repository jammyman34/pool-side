import XCTest
import SwiftData
@testable import Pool_Side

/// Covers the three-part dogfooding cleanup: "Why This Plan" Check contamination, product-label-first
/// application guidance, and focused-Check completion/skip interaction.
final class DogfoodCleanupTests: ConfigIsolatedTestCase {

    private let engine = ChemistryEngine()
    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func test(pH: Double = 7.8, fc: Double = 6, cc: Double = 0, ta: Double = 100, ch: Double = 350, cya: Double = 60) -> PoolTest {
        PoolTest(date: Date(), pH: pH, freeChlorine: fc, totalChlorine: fc + cc,
                 totalAlkalinity: ta, calciumHardness: ch, cyanuricAcid: cya, testMethod: .liquidDropKit)
    }

    private func acid(on t: PoolTest) -> Treatment {
        Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH toward ~7.4", amount: 20, unit: "fl oz",
                  instructions: "", urgency: .recommended, targetParameter: "pH", sortOrder: 1,
                  expectedEffectParameter: "pH", expectedDelta: -0.4, effectDelayHours: 4, poolTest: t)
    }

    private func check(after parent: Treatment, on t: PoolTest) -> Treatment {
        let c = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: parent.sortOrder + 1)!
        t.treatments.append(c)
        return c
    }

    // MARK: - Part 1: Why This Plan Check contamination

    // A. A plan containing only a focused Check does not generate chemical-treatment narrative.
    func testWhyPlanWithOnlyCheckHasNoChemicalNarrative() {
        let t = test(); let a = acid(on: t); a.isCompleted = true
        let c = check(after: a, on: t) // pending check, no pending chemical action

        let summary = WhyThisPlanNarrative.summaryLines(treatmentActions: [], focusedChecks: [c], test: t,
                                                        chlorineDemandScore: 0, hasPoolConditions: true)
        let outcomes = WhyThisPlanNarrative.expectedOutcomes(treatmentActions: [], focusedChecks: [c], test: t)

        XCTAssertTrue(summary.joined().localizedCaseInsensitiveContains("focused Check is pending"))
        XCTAssertFalse(summary.joined().contains("Check FC"))
        XCTAssertFalse(outcomes.joined().localizedCaseInsensitiveContains("Adding"), "A Check must not produce a chemical 'Adding …' outcome.")
    }

    // B. A chemical treatment followed by a focused Check uses the treatment as the summary source.
    func testWhyPlanUsesChemicalActionNotCheck() {
        let t = test(); let a = acid(on: t); let c = check(after: a, on: t)
        let summary = WhyThisPlanNarrative.summaryLines(treatmentActions: [a], focusedChecks: [c], test: t,
                                                        chlorineDemandScore: 0, hasPoolConditions: true)
        let outcomes = WhyThisPlanNarrative.expectedOutcomes(treatmentActions: [a], focusedChecks: [c], test: t)
        XCTAssertTrue(summary.contains(a.actionDescription))
        XCTAssertTrue(outcomes.joined().contains("Muriatic Acid"))
    }

    // C. A completed focused Check appears only in verification copy, not as a treatment action.
    func testCompletedCheckIsNotATreatmentAction() {
        let t = test(); let a = acid(on: t); a.isCompleted = true
        let c = check(after: a, on: t); c.isCompleted = true
        let summary = WhyThisPlanNarrative.summaryLines(treatmentActions: [], focusedChecks: [c], test: t,
                                                        chlorineDemandScore: 0, hasPoolConditions: true)
        XCTAssertTrue(summary.joined().localizedCaseInsensitiveContains("does not need an added treatment"))
        XCTAssertFalse(summary.joined().localizedCaseInsensitiveContains("Adding"))
    }

    // D. A check whose targetParameter is "freeChlorine" does not trigger chlorine acid/chlorine narrative.
    func testCheckDoesNotTriggerChlorineDetection() {
        let t = test(fc: 3.0)
        // A raw FC check has targetParameter "freeChlorine" and amount 0 — must not be read as a chlorine action.
        let fcCheck = Treatment(chemicalName: "Check FC & CC", actionDescription: "", amount: 0, unit: "",
                                instructions: "", urgency: .recommended, targetParameter: "freeChlorine", poolTest: t)
        fcCheck.workflowStepKind = .focusedCheck
        let outcomes = WhyThisPlanNarrative.expectedOutcomes(treatmentActions: [], focusedChecks: [fcCheck], test: t)
        XCTAssertFalse(outcomes.joined().localizedCaseInsensitiveContains("raise FC"))
    }

    // MARK: - Part 2: Product-label-first application guidance

    private func generatedTreatment(target: String, config: PoolConfiguration, test t: PoolTest) throws -> TreatmentTemplate {
        try XCTUnwrap(engine.validatedTreatments(for: t, config: config, recentHistory: [])
            .first { $0.targetParameter == target && $0.amount > 0 })
    }

    // A. Dry acid does not universally require pre-dissolving; defers to label.
    func testDryAcidDefersToLabel() throws {
        let cfg = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false, pHDecreaserPreference: .dryAcid)
        let acidTemplate = try generatedTreatment(target: "pH", config: cfg, test: test(pH: 7.9, ta: 100))
        XCTAssertTrue(acidTemplate.instructions.contains("Follow the product label"))
        XCTAssertFalse(acidTemplate.instructions.localizedCaseInsensitiveContains("pre-dissolve"))
        XCTAssertFalse(acidTemplate.instructions.localizedCaseInsensitiveContains("bucket"))
    }

    // B. Calcium chloride defers to the product label and does not universally pre-mix.
    func testCalciumDefersToLabel() throws {
        let calcium = try generatedTreatment(target: "calciumHardness", config: config, test: test(ch: 100))
        XCTAssertTrue(calcium.instructions.localizedCaseInsensitiveContains("product label"))
        XCTAssertFalse(calcium.instructions.localizedCaseInsensitiveContains("pre-dissolve"))
    }

    // C. Muriatic acid defers to the product label (no "deep end" handling directive).
    func testMuriaticAcidDefersToLabel() throws {
        let acidTemplate = try generatedTreatment(target: "pH", config: config, test: test(pH: 7.9, ta: 100))
        XCTAssertTrue(acidTemplate.instructions.contains("Follow the product label"))
        XCTAssertFalse(acidTemplate.instructions.localizedCaseInsensitiveContains("deep end"))
    }

    // D. Chlorine products defer to their labels for physical application (workflow timing retained).
    func testChlorineDefersToLabelButKeepsTiming() throws {
        let chlorine = try generatedTreatment(target: "freeChlorine", config: config, test: test(fc: 1.0))
        XCTAssertTrue(chlorine.instructions.contains("Follow the product label"))
        XCTAssertTrue(chlorine.instructions.localizedCaseInsensitiveContains("minute"), "Pool Side circulation/retest timing is retained.")
    }

    // E. Pool Side still gives the correct focused-Check timing after removing physical instructions.
    func testFocusedCheckTimingRetained() throws {
        let t = test(pH: 7.9, ta: 100)
        let a = try generatedTreatment(target: "pH", config: config, test: t).toTreatment(linkedTo: t)
        let descriptor = try XCTUnwrap(TreatmentWorkflowEngine().checkDescriptor(for: a))
        XCTAssertTrue(descriptor.timingText.contains("4 hours"))
    }

    // F. No generated chemical treatment loses its dose, sequence, wait, or verification guidance.
    func testGeneratedTreatmentRetainsDoseAndVerification() throws {
        let acidTemplate = try generatedTreatment(target: "pH", config: config, test: test(pH: 7.9, ta: 100))
        XCTAssertGreaterThan(acidTemplate.amount, 0)
        XCTAssertLessThan(acidTemplate.expectedDelta, 0)
        XCTAssertTrue(acidTemplate.instructions.localizedCaseInsensitiveContains("retest pH"))
    }

    // G. The export separates label-owned application guidance from Pool Side-owned verification timing.
    func testExportSeparatesLabelFromVerification() throws {
        let t = test(pH: 7.9, ta: 100)
        let a = try generatedTreatment(target: "pH", config: config, test: t).toTreatment(linkedTo: t)
        t.treatments = [a]
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: [a], test: t, config: config)
        XCTAssertTrue(actions.contains("Verification requirement:"))
        XCTAssertFalse(actions.localizedCaseInsensitiveContains("pre-dissolve"))
    }

    // MARK: - Part 3 & 4: focused-Check completion + skip interaction

    @MainActor private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor private func makeVM() -> PoolViewModel {
        let vm = PoolViewModel()
        vm.saveConfig(config)
        return vm
    }

    // Part 3 A + D: completing the parent (and scheduling the Check reminder) does not complete the Check.
    @MainActor func testCompletingParentDoesNotCompleteCheck() async throws {
        let ctx = try makeContext()
        let vm = makeVM()
        let t = test(); let a = acid(on: t); let c = check(after: a, on: t); ctx.insert(t)
        await vm.completeTreatment(a, in: [t], modelContext: ctx)
        XCTAssertTrue(a.isCompleted)
        XCTAssertFalse(c.isCompleted, "Completing the parent (and scheduling the Check reminder) must not complete the Check.")
    }

    // Part 3: the generic completion path refuses to complete a Check (checkbox-without-result guard).
    @MainActor func testGenericCompletionCannotCompleteCheck() async throws {
        let ctx = try makeContext()
        let vm = makeVM()
        let t = test(); let a = acid(on: t); a.isCompleted = true; let c = check(after: a, on: t); ctx.insert(t)
        await vm.completeTreatment(c, in: [t], modelContext: ctx)
        XCTAssertFalse(c.isCompleted, "A Check can never be completed via the generic treatment-completion path.")
    }

    // Part 3: focused Checks never appear in the completable pending-treatments list.
    @MainActor func testPendingTreatmentsExcludeChecks() throws {
        let vm = makeVM()
        let t = test(); let a = acid(on: t); a.isCompleted = true; _ = check(after: a, on: t)
        XCTAssertFalse(vm.pendingTreatments(from: [t]).contains { $0.isFocusedCheckStep })
    }

    // Part 3 B + C: the Check becoming due / time advancing past due does not complete it.
    func testDueDoesNotCompleteCheck() {
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let t = test(); let a = acid(on: t); a.isCompleted = true; a.completedAt = completedAt
        let c = check(after: a, on: t)
        let engine = TreatmentWorkflowEngine()
        // Well past the pH Check's 4h due time.
        let state = engine.state(for: c, in: t.treatments, evaluationDate: completedAt.addingTimeInterval(10 * 3600))
        XCTAssertEqual(state, .current)
        XCTAssertFalse(c.isCompleted, "Reaching/ passing the due time must not complete the Check.")
    }

    // Part 3 E: relaunch (fresh context over the same store) preserves incomplete Check state.
    @MainActor func testRelaunchPreservesIncompleteCheck() async throws {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let vm = makeVM()
        let t = test(); let a = acid(on: t); let c = check(after: a, on: t); let checkID = c.id
        ctx.insert(t)
        await vm.completeTreatment(a, in: [t], modelContext: ctx)
        try ctx.save()

        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(FetchDescriptor<Treatment>()).first { $0.id == checkID }
        XCTAssertEqual(reloaded?.isCompleted, false)
    }

    // Part 3 G + H: only saving valid results (or a qualifying full test) completes the Check.
    @MainActor func testSavingResultsCompletesCheck() async throws {
        let ctx = try makeContext()
        let vm = makeVM()
        // pH 8.2 blocks swimming, so the acid correction generates a verification Check to complete.
        let pool = PoolTest(date: Date(), pH: 8.2, freeChlorine: 8, totalChlorine: 8,
                            totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
        ctx.insert(pool)
        await vm.generateRecommendations(for: pool, recentTests: [], modelContext: ctx)
        let acidStep = try XCTUnwrap(pool.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acidStep, in: [pool], modelContext: ctx)
        let c = try XCTUnwrap(vm.dependentCheck(for: acidStep))
        XCTAssertFalse(c.isCompleted)
        try await vm.saveFocusedCheck(c, values: ["pH": 7.5], for: pool, allTests: [pool], modelContext: ctx)
        XCTAssertTrue(c.isCompleted)
    }

    // Part 4 A + E + H: skipping a Check uses the shared action model, never completes it, and never
    // satisfies verification.
    @MainActor func testSkippingCheckDoesNotCompleteOrVerify() throws {
        let vm = makeVM()
        let t = test(); let a = acid(on: t); a.isCompleted = true; let c = check(after: a, on: t)
        vm.skipTreatment(c)
        XCTAssertTrue(c.isSkipped)
        XCTAssertFalse(c.isCompleted, "Skipping must never complete a Check.")
        XCTAssertNil(c.checkResultTestID, "A skipped Check never becomes verification evidence.")
    }

    // Part 4 C + D: a skipped Check can be restored and returns to an incomplete pending/ready state.
    @MainActor func testRestoringSkippedCheck() throws {
        let vm = makeVM()
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let t = test(); let a = acid(on: t); a.isCompleted = true; a.completedAt = completedAt
        let c = check(after: a, on: t)
        vm.skipTreatment(c)
        vm.restoreTreatment(c)
        XCTAssertFalse(c.isSkipped)
        XCTAssertFalse(c.isCompleted)
        let state = TreatmentWorkflowEngine().state(for: c, in: t.treatments, evaluationDate: completedAt.addingTimeInterval(10 * 3600))
        XCTAssertEqual(state, .current, "Restored Check returns to the correct ready state based on parent completion + timing.")
    }
}
