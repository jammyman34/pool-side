import XCTest
import SwiftData
@testable import Pool_Side

/// Locks the focused-Check closure UX: after a Check is saved, the outcome is derived from the POST-check
/// reassessment (ChemistryPolicy + regenerated plan + Swimability V2), never from a hard-coded View range.
final class FocusedCheckOutcomeTests: XCTestCase {

    private let evaluator = FocusedCheckOutcomeEvaluator()

    private func test(pH: Double = 7.4, fc: Double = 6, cc: Double = 0, cya: Double = 60,
                      method: TestMethod = .liquidDropKit, sample: TaylorSampleSize? = .tenMl) -> PoolTest {
        let t = PoolTest(date: Date(), pH: pH, freeChlorine: fc, totalChlorine: fc + cc,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: cya, testMethod: method)
        t.taylorSampleSize = sample
        return t
    }

    private func followUp(target: String, on test: PoolTest) -> Treatment {
        Treatment(
            chemicalName: target == "pH" ? "Muriatic Acid" : "Liquid Chlorine 12.5%",
            actionDescription: "", amount: 20, unit: "fl oz", instructions: "",
            urgency: .recommended, targetParameter: target, sortOrder: 1, effectDelayHours: 4, poolTest: test
        )
    }

    // A. pH 7.8 → 7.6 resolves with no follow-up.
    func testResolvedOutcomeWhenBackInOperatingRangeAndNoFollowUp() {
        let post = test(pH: 7.6)
        let outcome = evaluator.outcome(parameter: "pH", priorValue: 7.8, measuredValue: 7.6,
                                        postCheckTest: post, postCheckTreatments: [], config: PoolConfiguration())
        XCTAssertEqual(outcome.kind, .resolved)
        XCTAssertTrue(outcome.inOperatingRange)
        XCTAssertFalse(outcome.hasFollowUpTreatment)
        XCTAssertFalse(outcome.blocksSwimming)
    }

    // B. pH 7.8 → 7.7, still high, a fresh correction was generated → improved.
    func testImprovedButMoreCorrectionNeeded() {
        let post = test(pH: 7.7)
        let outcome = evaluator.outcome(parameter: "pH", priorValue: 7.8, measuredValue: 7.7,
                                        postCheckTest: post, postCheckTreatments: [followUp(target: "pH", on: post)],
                                        config: PoolConfiguration())
        XCTAssertEqual(outcome.kind, .improvedMoreCorrectionNeeded)
        XCTAssertFalse(outcome.inOperatingRange)
        XCTAssertTrue(outcome.hasFollowUpTreatment)
    }

    // C. pH 7.8 → 7.8 (no observable change) with a recomputed action → still out of range, not "improved".
    func testNoMeaningfulChangeIsStillOutOfRange() {
        let post = test(pH: 7.8)
        let outcome = evaluator.outcome(parameter: "pH", priorValue: 7.8, measuredValue: 7.8,
                                        postCheckTest: post, postCheckTreatments: [followUp(target: "pH", on: post)],
                                        config: PoolConfiguration())
        XCTAssertEqual(outcome.kind, .stillOutOfRange)
    }

    // D. High-pH correction overshoots to a low value → moved past the range (no false success).
    func testCrossingToOppositeSideIsMovedPastRange() {
        let post = test(pH: 6.9)
        let outcome = evaluator.outcome(parameter: "pH", priorValue: 7.8, measuredValue: 6.9,
                                        postCheckTest: post, postCheckTreatments: [followUp(target: "pH", on: post)],
                                        config: PoolConfiguration())
        XCTAssertEqual(outcome.kind, .movedPastRange)
        XCTAssertFalse(outcome.inOperatingRange)
    }

    // E. pH resolved but another swim gate fails — must NOT claim the pool is ready.
    func testResolvedParameterDoesNotClaimPoolReadyWhenV2SaysDoNotSwim() {
        let resolved = FocusedCheckParameterOutcome(parameter: "pH", displayName: "pH", measuredValue: 7.6,
                                                    kind: .resolved, inOperatingRange: true, blocksSwimming: false,
                                                    hasFollowUpTreatment: false, operatingRangeText: "7.2–7.6")
        let result = FocusedCheckResult(parameterOutcomes: [resolved], swimState: .doNotSwim)
        XCTAssertTrue(result.title.localizedCaseInsensitiveContains("in range"))
        XCTAssertTrue(result.nextAction.localizedCaseInsensitiveContains("not recommended"))
        XCTAssertFalse(result.nextAction.localizedCaseInsensitiveContains("ready for swimming"))
    }

    // F. pH 7.7 still recommends a correction, but if V2 says ready, do not imply swimming is blocked.
    func testStillHighButSwimReadyDoesNotImplyBlocked() {
        let outcome = FocusedCheckParameterOutcome(parameter: "pH", displayName: "pH", measuredValue: 7.7,
                                                   kind: .improvedMoreCorrectionNeeded, inOperatingRange: false,
                                                   blocksSwimming: false, hasFollowUpTreatment: true,
                                                   operatingRangeText: "7.2–7.6")
        let result = FocusedCheckResult(parameterOutcomes: [outcome], swimState: .readyToSwim)
        XCTAssertFalse(result.anyBlocksSwimming)
        XCTAssertTrue(result.nextAction.localizedCaseInsensitiveContains("ready for swimming"))
    }

    // G. FC/CC multi-parameter Check: FC resolved, CC still high → mixed result, not "all in range".
    func testMultiParameterCheckMixedResult() {
        let post = test(fc: 7.0, cc: 1.0)
        let chlorine = followUp(target: "freeChlorine", on: post)
        let fcOutcome = evaluator.outcome(parameter: "freeChlorine", priorValue: 5.0, measuredValue: 7.0,
                                          postCheckTest: post, postCheckTreatments: [chlorine], config: PoolConfiguration())
        let ccOutcome = evaluator.outcome(parameter: "combinedChlorine", priorValue: 1.5, measuredValue: 1.0,
                                          postCheckTest: post, postCheckTreatments: [chlorine], config: PoolConfiguration())
        let result = FocusedCheckResult(parameterOutcomes: [fcOutcome, ccOutcome], swimState: nil)

        XCTAssertEqual(fcOutcome.kind, .resolved, "FC is in its operating range.")
        XCTAssertNotEqual(ccOutcome.kind, .resolved, "CC is still elevated.")
        XCTAssertFalse(result.allResolved, "A mixed result must not claim everything is in range.")
    }

    // H. Changes below the method's measurement resolution are not described as improvement.
    func testSubResolutionChangeIsNotImprovement() {
        let config = PoolConfiguration()
        // FAS-DPD 10 mL resolves 0.5 ppm. Prior 5.0 → 5.2 is unobservable; 5.0 → 5.6 is observable.
        let unobservablePost = test(fc: 5.2, sample: .tenMl)
        let observablePost = test(fc: 5.6, sample: .tenMl)
        let chlorineU = followUp(target: "freeChlorine", on: unobservablePost)
        let chlorineO = followUp(target: "freeChlorine", on: observablePost)

        let unobservable = evaluator.outcome(parameter: "freeChlorine", priorValue: 5.0, measuredValue: 5.2,
                                             postCheckTest: unobservablePost, postCheckTreatments: [chlorineU], config: config)
        let observable = evaluator.outcome(parameter: "freeChlorine", priorValue: 5.0, measuredValue: 5.6,
                                           postCheckTest: observablePost, postCheckTreatments: [chlorineO], config: config)

        XCTAssertEqual(unobservable.kind, .stillOutOfRange, "A 0.2 ppm change is below FAS-DPD resolution.")
        XCTAssertEqual(observable.kind, .improvedMoreCorrectionNeeded, "A 0.6 ppm change is observable improvement.")
    }

    // MARK: - Integration through the ViewModel (real regeneration)

    @MainActor
    private func makeViewModel() -> (PoolViewModel, ModelContext) {
        let container = try! ModelContainer(for: PoolTest.self, Treatment.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false))
        return (vm, ModelContext(container))
    }

    // A (integration) + I: real pH 7.8 → treat → Check 7.6 → resolved, no follow-up, explicit success copy.
    @MainActor
    func testRealPHResolvedFlowProducesExplicitSuccessOutcome() async throws {
        let (vm, context) = makeViewModel()
        let poolTest = PoolTest(date: Date(), pH: 7.8, freeChlorine: 8, totalChlorine: 8,
                                totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60,
                                testMethod: .liquidDropKit)
        context.insert(poolTest)
        await vm.generateRecommendations(for: poolTest, recentTests: [], modelContext: context)
        let acid = try XCTUnwrap(poolTest.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [poolTest], modelContext: context)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))

        let result = try await vm.saveFocusedCheck(check, values: ["pH": 7.6], for: poolTest,
                                                   allTests: [poolTest], modelContext: context)

        XCTAssertTrue(result.allResolved)
        XCTAssertFalse(result.hasFollowUpTreatment)
        XCTAssertTrue(result.title.localizedCaseInsensitiveContains("in range"))
        XCTAssertTrue(result.interpretation.localizedCaseInsensitiveContains("7.6"))
    }

    // B (integration) + I: real pH 7.8 → treat → Check 7.7 → follow-up generated, copy says fresh calculation.
    @MainActor
    func testRealPHImprovedFlowReferencesFreshRecalculationNotRemainder() async throws {
        let (vm, context) = makeViewModel()
        let poolTest = PoolTest(date: Date(), pH: 7.8, freeChlorine: 8, totalChlorine: 8,
                                totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60,
                                testMethod: .liquidDropKit)
        context.insert(poolTest)
        await vm.generateRecommendations(for: poolTest, recentTests: [], modelContext: context)
        let acid = try XCTUnwrap(poolTest.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [poolTest], modelContext: context)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))

        let result = try await vm.saveFocusedCheck(check, values: ["pH": 7.7], for: poolTest,
                                                   allTests: [poolTest], modelContext: context)

        XCTAssertTrue(result.hasFollowUpTreatment)
        XCTAssertEqual(result.primaryOutcome?.kind, .improvedMoreCorrectionNeeded)
        XCTAssertTrue(result.nextAction.localizedCaseInsensitiveContains("fresh calculation"))
        // Must never frame the recomputed correction as a remainder to finish.
        XCTAssertFalse(result.nextAction.localizedCaseInsensitiveContains("remaining dose"))
        XCTAssertFalse(result.nextAction.localizedCaseInsensitiveContains("add the rest"))
        XCTAssertFalse(result.nextAction.localizedCaseInsensitiveContains("you still have"))
    }

    // J. External-review export exposes the interpreted outcome of a completed Check.
    func testExternalReviewExportIncludesCompletedCheckOutcome() {
        let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)
        let poolTest = PoolTest(date: Date(), pH: 7.6, freeChlorine: 8, totalChlorine: 8,
                                totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
        let acid = Treatment(chemicalName: "Muriatic Acid", actionDescription: "", amount: 20, unit: "fl oz",
                             instructions: "", urgency: .recommended, isCompleted: true, completedAt: Date(),
                             targetParameter: "pH", sortOrder: 1, effectDelayHours: 4, poolTest: poolTest)
        let check = TreatmentWorkflowEngine().makeCheckStep(after: acid, sortOrder: 2)!
        check.isCompleted = true
        check.checkResultTestID = poolTest.id
        poolTest.treatments = [acid, check]

        let export = ExternalReviewExportBuilder.treatmentAuditSection(
            config: config, test: poolTest, treatments: [acid], recentHistory: [], routineNextTestTiming: "in 3 days"
        )

        XCTAssertTrue(export.contains("pH result: 7.6"))
        XCTAssertTrue(export.localizedCaseInsensitiveContains("returned to operating range"))
        XCTAssertTrue(export.localizedCaseInsensitiveContains("Further pH correction: none"))
    }
}
