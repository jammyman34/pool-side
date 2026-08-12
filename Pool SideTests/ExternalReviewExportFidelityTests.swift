import XCTest
import SwiftData
@testable import Pool_Side

/// Verifies the External Review Export faithfully mirrors the production authorities: treatments vs
/// focused Checks are separated, verification is canonical (ChemistryPolicy/V2), staged effects don't
/// overclaim, Swimability V2 is represented, and product-preference changes reprice unfinished steps.
final class ExternalReviewExportFidelityTests: XCTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func test(pH: Double = 7.8, fc: Double = 3.0, cc: Double = 0.0, cya: Double = 60) -> PoolTest {
        PoolTest(date: Date(), pH: pH, freeChlorine: fc, totalChlorine: fc + cc,
                 totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: cya, testMethod: .liquidDropKit,
                 waterClarityAssessment: .clear, visibleAlgaeAssessment: .absent)
    }

    private func acid(on t: PoolTest, capped: Bool = false) -> Treatment {
        Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH toward ~7.4",
                  amount: capped ? 1.5 : 1.0, unit: capped ? "qt" : "gal",
                  productIdentifier: ChemicalProductID.muriaticAcid31.rawValue,
                  globalPreferenceIdentifier: ChemicalProductID.muriaticAcid31.rawValue,
                  calculatedDoseBeforeCap: capped ? 1.0 : 0, calculatedDoseBeforeCapUnit: capped ? "gal" : "",
                  wasDoseCapped: capped, instructions: "Add acid.", urgency: .recommended,
                  targetParameter: "pH", sortOrder: 1, expectedEffectParameter: "pH",
                  expectedDelta: -0.4, effectDelayHours: 4, poolTest: t)
    }

    private func chlorine(on t: PoolTest, delta: Double = 3.1) -> Treatment {
        Treatment(chemicalName: "Liquid Chlorine 12.5%", actionDescription: "Raise FC",
                  amount: 0.75, unit: "gal", productIdentifier: ChemicalProductID.liquidChlorine12_5.rawValue,
                  globalPreferenceIdentifier: ChemicalProductID.liquidChlorine12_5.rawValue,
                  wasDoseCapped: false, instructions: "Add chlorine.", urgency: .recommended,
                  targetParameter: "freeChlorine", sortOrder: 1, expectedEffectParameter: "freeChlorine",
                  expectedDelta: delta, effectDelayHours: 1, poolTest: t)
    }

    private func check(after parent: Treatment, on t: PoolTest) -> Treatment {
        let c = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: parent.sortOrder + 1)!
        t.treatments.append(c)
        return c
    }

    // A. Pending chemical treatment appears in Treatment Actions, not Focused Checks.
    func testChemicalTreatmentInActionsNotChecks() {
        let t = test(); let a = acid(on: t); t.treatments = [a]
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: [a], test: t, config: config)
        let checks = ExternalReviewExportBuilder.focusedChecksSection(allTreatments: [a], test: t, recentHistory: [], config: config)
        XCTAssertTrue(actions.contains("Muriatic Acid"))
        XCTAssertTrue(checks.contains("No focused Checks"))
    }

    // B. Pending focused Check appears only in Focused Checks.
    func testFocusedCheckOnlyInChecksSection() {
        let t = test(); let a = acid(on: t); t.treatments = [a]
        let c = check(after: a, on: t)
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: t.treatments, test: t, config: config)
        let checks = ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config)
        XCTAssertFalse(actions.contains(c.chemicalName), "A Check must not appear as a treatment action.")
        XCTAssertTrue(checks.contains(c.chemicalName))
    }

    // C. Completed focused Check appears once with result/outcome.
    func testCompletedCheckShowsResult() {
        let t = test(pH: 7.6); let a = acid(on: t); a.isCompleted = true; t.treatments = [a]
        let c = check(after: a, on: t)
        c.isCompleted = true; c.completedAt = Date(); c.checkResultTestID = t.id
        let checks = ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config)
        XCTAssertTrue(checks.contains("(completed"))
        XCTAssertTrue(checks.contains("Measured result"))
        XCTAssertTrue(checks.contains("returned to operating range"))
    }

    // D. Check has no product/dose/expected-effect fields anywhere.
    func testCheckHasNoProductOrDoseFields() {
        let t = test(); let a = acid(on: t); t.treatments = [a]
        let c = check(after: a, on: t)
        let checks = ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config)
        for banned in ["Selected product", "Product concentration", "Global preference", "Total calculated correction", "Expected response", "+0.0", "Soda Ash"] {
            XCTAssertFalse(checks.contains(banned), "Check block must not contain \(banned)")
        }
        // And the product audit must exclude checks entirely.
        let audit = ExternalReviewExportBuilder.treatmentAuditSection(config: config, test: t, treatments: t.treatments, recentHistory: [], routineNextTestTiming: "Tomorrow")
        XCTAssertFalse(audit.contains(c.chemicalName), "Product audit must not list a Check.")
    }

    // E. Low FC below readiness minimum → Required verification.
    func testLowFCBelowReadinessRequiresVerification() {
        let t = test(fc: 1.5, cya: 60) // readiness minimum 2.0 → below → swim-blocking
        let cl = chlorine(on: t); t.treatments = [cl]
        XCTAssertEqual(ExportVerificationRequirement.resolve(for: cl, test: t, config: config), .required)
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: [cl], test: t, config: config)
        XCTAssertTrue(actions.contains("Verification requirement: Required"))
    }

    // F. FC maintenance top-off (above readiness, below 3 ppm target) → discretionary.
    func testFCMaintenanceIsDiscretionary() {
        let t = test(fc: 2.5, cya: 60) // ≥ readiness 2.0, < target 3.0 → not swim-blocking
        let cl = chlorine(on: t, delta: 0.5); t.treatments = [cl]
        XCTAssertEqual(ExportVerificationRequirement.resolve(for: cl, test: t, config: config), .discretionary)
    }

    // G. CC above threshold → required FC/CC verification.
    func testHighCCRequiresVerification() {
        let t = test(fc: 6.0, cc: 1.0, cya: 60) // FC fine but CC > 0.5 blocks
        let cl = chlorine(on: t); t.treatments = [cl]
        XCTAssertEqual(ExportVerificationRequirement.resolve(for: cl, test: t, config: config), .required)
    }

    // H. V2 section reflects the assessment state and gates.
    func testSwimReadinessSectionMirrorsAssessment() {
        let gate = SwimReadinessGateResult(identifier: .sanitizerAdequacy, state: .fail,
                                           reason: "FC below readiness minimum", blocksSwimming: true, requiresTesting: true)
        let assessment = SwimabilityV2Assessment(
            state: .doNotSwim, evidenceType: .observed, confidence: .high,
            gateResults: [gate], invalidationReasons: [], testingRequired: true, summary: "Sanitizer too low to swim.")
        let section = ExternalReviewExportBuilder.swimReadinessSection(assessment)
        XCTAssertTrue(section.contains("V2 state: doNotSwim"))
        XCTAssertTrue(section.contains("Swimming blocked: Yes"))
        XCTAssertTrue(section.contains("Testing required: Yes"))
        XCTAssertTrue(section.contains("sanitizerAdequacy"))
        XCTAssertTrue(section.contains("Sanitizer too low to swim."))
    }

    // I. Neither actions nor checks are labeled "Routine next test".
    func testNoRoutineNextTestLabelOnStepsOrChecks() {
        let t = test(); let a = acid(on: t); t.treatments = [a]
        _ = check(after: a, on: t)
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: t.treatments, test: t, config: config)
        let checks = ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config)
        XCTAssertFalse(actions.contains("Routine next test"))
        XCTAssertFalse(checks.contains("Routine next test"))
    }

    // J. Capped acid: current dose + total correction, no full theoretical delta, recalculation language.
    func testCappedAcidDoesNotClaimFullDelta() {
        let t = test(); let a = acid(on: t, capped: true); t.treatments = [a]
        let actions = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: [a], test: t, config: config)
        XCTAssertTrue(actions.contains("Current application: 1.5 qt"))
        XCTAssertTrue(actions.contains("Total calculated correction: 1 gal"))
        XCTAssertTrue(actions.contains("recalculated from the new measurement"))
        XCTAssertFalse(actions.contains("pH -0.4"), "Must not claim the full theoretical delta for the staged dose.")
    }

    // K. Uncapped liquid chlorine expected effect reflects the current application.
    func testUncappedChlorineShowsDoseDerivedEffect() {
        let t = test(fc: 3.0); let cl = chlorine(on: t, delta: 3.1); t.treatments = [cl]
        let text = ExternalReviewExportBuilder.expectedResponseText(for: cl)
        XCTAssertTrue(text.contains("FC +3.1"))
    }

    // L. Checks excluded from suppression/deferral output.
    func testChecksExcludedFromDeferrals() {
        let t = test(); let a = acid(on: t); t.treatments = [a]
        let c = check(after: a, on: t)
        let deferrals = ExternalReviewExportBuilder.engineDeferralsSection(allTreatments: t.treatments)
        XCTAssertFalse(deferrals.contains(c.chemicalName))
    }

    // M. Engine deferral output matches actual repeat-suppression state.
    func testEngineDeferralReflectsWaitWindow() {
        let t = test()
        let completedAcid = Treatment(chemicalName: "Muriatic Acid", actionDescription: "", amount: 1, unit: "gal",
                                      instructions: "", urgency: .recommended, isCompleted: true, completedAt: Date(),
                                      targetParameter: "pH", expectedEffectParameter: "pH",
                                      doNotRepeatBefore: Date().addingTimeInterval(6 * 3600), poolTest: t)
        t.treatments = [completedAcid]
        let deferrals = ExternalReviewExportBuilder.engineDeferralsSection(allTreatments: t.treatments)
        XCTAssertTrue(deferrals.contains("wait/retest window"))
        // With no wait window, it reports none.
        let none = ExternalReviewExportBuilder.engineDeferralsSection(allTreatments: [acid(on: test())])
        XCTAssertTrue(none.contains("No active engine repeat-suppression"))
    }

    // Q. Prior-test completed/skipped step summary wording.
    func testRecentHistoryStepSummary() {
        let t = test()
        let done = Treatment(chemicalName: "Muriatic Acid", actionDescription: "", amount: 1, unit: "gal",
                             instructions: "", urgency: .recommended, isCompleted: true, completedAt: Date(),
                             targetParameter: "pH", poolTest: t)
        t.treatments = [done]
        XCTAssertTrue(ExternalReviewExportBuilder.completedOrSkippedStepsSummary(for: t).contains("Muriatic Acid (treatment, completed)"))
        // A prior test with no completed/skipped steps → none.
        XCTAssertEqual(ExternalReviewExportBuilder.completedOrSkippedStepsSummary(for: test()), "none")
    }

    // S. No "remaining/leftover/finish previous correction" wording.
    func testNoLeftoverDoseWording() {
        let t = test(); let a = acid(on: t, capped: true); t.treatments = [a]; _ = check(after: a, on: t)
        let combined = ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: t.treatments, test: t, config: config)
            + ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config)
            + ExternalReviewExportBuilder.expectedResponseText(for: a)
        for banned in ["remaining dose", "leftover", "finish the previous", "finish previous"] {
            XCTAssertFalse(combined.localizedCaseInsensitiveContains(banned), "Must not contain \(banned)")
        }
    }

    func testFC15ExportUsesCorrectedSafetyFloorTargetAndRequiredCheck() {
        let t = test(pH: 7.5, fc: 1.5, cya: 50)
        let export = generatedFCExport(for: t)

        XCTAssertTrue(export.contains("V2 state: doNotSwim"))
        XCTAssertTrue(export.contains("sanitizerAdequacy: fail"))
        XCTAssertTrue(export.contains("swim-readiness minimum of 2 ppm"))
        XCTAssertTrue(export.contains("Urgency: Needs Attention"))
        XCTAssertTrue(export.contains("Expected response: Approximately FC +1.5"))
        XCTAssertTrue(export.contains("Verification requirement: Required"))
        XCTAssertTrue(export.contains("Check FC & CC"))
        XCTAssertFalse(export.contains("CYA-adjusted"))
        XCTAssertFalse(export.contains("toward 7"))
    }

    func testFC25ExportUsesRecommendedTopOffWithoutRequiredCheck() {
        let t = test(pH: 7.5, fc: 2.5, cya: 50)
        let export = generatedFCExport(for: t)

        XCTAssertTrue(export.contains("V2 state: readyToSwim"))
        XCTAssertTrue(export.contains("Failed gates: none"))
        XCTAssertTrue(export.contains("Urgency: Recommended"))
        XCTAssertTrue(export.contains("Maintenance top-off toward 3 ppm"))
        XCTAssertTrue(export.contains("Expected response: Approximately FC +0.5"))
        XCTAssertTrue(export.contains("Verification requirement: Discretionary"))
        XCTAssertTrue(export.contains("No focused Checks in the active workflow."))
        XCTAssertFalse(export.contains("CYA-adjusted"))
        XCTAssertFalse(export.contains("toward 7"))
    }

    func testFC35ExportHasNoChlorineTreatmentOrCheck() {
        let t = test(pH: 7.5, fc: 3.5, cya: 50)
        let export = generatedFCExport(for: t)

        XCTAssertTrue(export.contains("V2 state: readyToSwim"))
        XCTAssertTrue(export.contains("Failed gates: none"))
        XCTAssertTrue(export.contains("No actionable treatment steps."))
        XCTAssertTrue(export.contains("No focused Checks in the active workflow."))
        XCTAssertFalse(export.contains("Title: Liquid Chlorine"))
        XCTAssertFalse(export.contains("CYA-adjusted"))
    }

    // MARK: - Preference repricing (§9) — production

    @MainActor
    private func makeVM(pHDecreaser: PHDecreaserPreference) -> PoolViewModel {
        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false,
                                        pHDecreaserPreference: pHDecreaser))
        return vm
    }

    @MainActor
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    // N. Pending preference change reprices the unfinished treatment and dose.
    @MainActor
    func testPreferenceChangeRepricesUnfinishedTreatment() throws {
        let ctx = try context()
        let vm = makeVM(pHDecreaser: .dryAcid)
        let t = test()
        let a = acid(on: t); t.treatments = [a]
        ctx.insert(t)

        let originalAmount = a.amount
        let didChange = vm.repriceUnfinishedTreatmentsForPreferenceChange(in: [t], modelContext: ctx)

        XCTAssertTrue(didChange)
        XCTAssertEqual(a.productIdentifier, ChemicalProductID.dryAcid.rawValue)
        XCTAssertEqual(a.globalPreferenceIdentifier, ChemicalProductID.dryAcid.rawValue)
        XCTAssertTrue(a.chemicalName.localizedCaseInsensitiveContains("dry acid"))
        XCTAssertNotEqual(a.amount, originalAmount, "Dose is recalculated for the new product.")
    }

    // O. Completed history remains unchanged after preference change.
    @MainActor
    func testPreferenceChangePreservesCompletedHistory() throws {
        let ctx = try context()
        let vm = makeVM(pHDecreaser: .dryAcid)
        let t = test()
        let a = acid(on: t); a.isCompleted = true; a.completedAt = Date(); t.treatments = [a]
        ctx.insert(t)

        vm.repriceUnfinishedTreatmentsForPreferenceChange(in: [t], modelContext: ctx)
        XCTAssertEqual(a.productIdentifier, ChemicalProductID.muriaticAcid31.rawValue, "Completed history must not be rewritten.")
    }

    // P. No active treatment → preference change creates nothing.
    @MainActor
    func testPreferenceChangeWithNoActiveTreatmentCreatesNothing() throws {
        let ctx = try context()
        let vm = makeVM(pHDecreaser: .dryAcid)
        let t = test(); ctx.insert(t)
        let didChange = vm.repriceUnfinishedTreatmentsForPreferenceChange(in: [t], modelContext: ctx)
        XCTAssertFalse(didChange)
        XCTAssertTrue(t.treatments.isEmpty)
    }

    private func generatedFCExport(for t: PoolTest) -> String {
        let templates = ChemistryEngine().validatedTreatments(for: t, config: config, recentHistory: [])
        let treatments = templates.map { $0.toTreatment(linkedTo: t) }
        t.treatments = treatments
        let workflowEngine = TreatmentWorkflowEngine()
        for treatment in treatments where workflowEngine.requiresFocusedCheck(for: treatment, config: config) {
            if let check = workflowEngine.makeCheckStep(after: treatment, sortOrder: treatment.sortOrder + 1) {
                t.treatments.append(check)
            }
        }
        let request = AIRecommendationRequest(currentTest: t, recentHistory: [], poolConfig: config)
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: Date())
        return [
            ExternalReviewExportBuilder.swimReadinessSection(assessment),
            ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: t.treatments, test: t, config: config),
            ExternalReviewExportBuilder.focusedChecksSection(allTreatments: t.treatments, test: t, recentHistory: [], config: config),
            ExternalReviewExportBuilder.treatmentAuditSection(config: config, test: t, treatments: t.treatments, recentHistory: [], routineNextTestTiming: "Tomorrow")
        ].joined(separator: "\n")
    }
}
