import XCTest
@testable import Pool_Side

/// Downstream integration for a real routine FC & pH test: swim-readiness freshness (mixed-age), the
/// treatment-completion gate, schedule satisfaction/anchoring, fresh-vs-stale treatment generation, and
/// verification copy.
final class FCAndPHIntegrationTests: ConfigIsolatedTestCase {

    private let engine = ChemistryEngine()
    private var config: PoolConfiguration { ChemistryTestFixtures.config() } // dry acid + liquid chlorine 12.5%

    private let aug18 = Date(timeIntervalSince1970: 1_800_000_000)
    private var aug23: Date { aug18.addingTimeInterval(5 * 86_400) }
    private var aug25: Date { aug18.addingTimeInterval(7 * 86_400) }
    private var evalAug23: Date { aug23.addingTimeInterval(2 * 3_600) }

    private func fullTest(date: Date, ta: Double = 170, pH: Double = 7.5, fc: Double = 3, cya: Double = 48) -> PoolTest {
        let t = PoolTest(date: date, pH: pH, freeChlorine: fc, totalChlorine: fc,
                         totalAlkalinity: ta, calciumHardness: 340, cyanuricAcid: cya,
                         testMethod: .liquidDropKit,
                         waterClarityAssessment: .clear, visibleAlgaeAssessment: .absent)
        t.routineTestScope = .fullPanel
        return t
    }

    /// FC & pH routine test: fresh FC/pH, TA/CH/CYA carried forward (older evidence) from `source`.
    private func fcAndPHTest(date: Date, fc: Double, pH: Double, source: PoolTest) -> PoolTest {
        let t = PoolTest(date: date, pH: pH, freeChlorine: fc, totalChlorine: fc,
                         totalAlkalinity: source.totalAlkalinity, calciumHardness: source.calciumHardness,
                         cyanuricAcid: source.cyanuricAcid, testMethod: .liquidDropKit,
                         waterClarityAssessment: .clear, visibleAlgaeAssessment: .absent)
        t.routineTestScope = .fcAndPH
        t.applyFCAndPHCarryForward(from: source)
        return t
    }

    private func request(_ test: PoolTest, history: [PoolTest]) -> AIRecommendationRequest {
        AIRecommendationRequest(currentTest: test, recentHistory: history, poolConfig: config)
    }

    // 1. Fresh FC/pH refreshes swim-readiness freshness despite an older Full Panel.
    func testFreshnessUsesFreshChlorineAndPHNotCarriedForwardEvidence() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2.0, pH: 7.6, source: source)
        let assessment = SwimabilityV2Engine().assess(request: request(fc, history: [source]), evaluationDate: evalAug23)
        XCTAssertFalse(assessment.failedGates.contains { $0.identifier == .testFreshness },
                       "Fresh Aug 23 FC/pH must satisfy the readiness freshness gate.")
    }

    // 2. FC 2.0 + pH 7.6, clear/no-algae, no treatments -> swim-ready.
    func testSwimReadyWithAdequateFCAndPH() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2.0, pH: 7.6, source: source)
        let assessment = SwimabilityV2Engine().assess(request: request(fc, history: [source]), evaluationDate: evalAug23)
        XCTAssertEqual(assessment.state, .readyToSwim, "failed: \(assessment.failedGates.map(\.identifier.rawValue))")
        XCTAssertFalse(assessment.swimmingBlocked)
    }

    // 3. Recommended/discretionary treatments do not fail the treatment-completion gate.
    func testDiscretionaryTreatmentsDoNotBlockSwimming() {
        let source = fullTest(date: aug18)
        let t = fcAndPHTest(date: aug23, fc: 3, pH: 7.6, source: source) // swim-safe pH
        let acidTA = Treatment(chemicalName: "Dry Acid (Sodium Bisulfate)", actionDescription: "Optimize TA",
                               amount: 2, unit: "lbs", instructions: "", urgency: .recommended,
                               targetParameter: "totalAlkalinity", sortOrder: 1,
                               expectedEffectParameter: "totalAlkalinity", expectedDelta: -20, effectDelayHours: 4,
                               poolTest: t)
        let topOff = Treatment(chemicalName: "Liquid Chlorine 12.5%", actionDescription: "Maintenance top-off toward 3 ppm",
                               amount: 0.1, unit: "gal", instructions: "", urgency: .recommended,
                               targetParameter: "freeChlorine", sortOrder: 2,
                               expectedEffectParameter: "freeChlorine", expectedDelta: 1, effectDelayHours: 1,
                               poolTest: t)
        let ctx = V2TreatmentClassifier().classify(treatments: [acidTA, topOff], evaluationDate: aug23)
        XCTAssertFalse(ctx.classifications.contains { $0.blocksCurrentSwimability },
                       "Recommended optimization must not swim-block a swim-safe pool.")
        XCTAssertEqual(ctx.classifications.first { $0.targetParameter == "totalAlkalinity" }?.category, .poolCare)
        XCTAssertEqual(ctx.classifications.first { $0.targetParameter == "freeChlorine" }?.category, .poolCare)
    }

    // 4. An overdue scheduled FC+pH is satisfied by a later fcAndPH test (no longer upcoming).
    func testFCAndPHTestSatisfiesScheduledQuickCheck() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2, pH: 7.6, source: source)
        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: fc, in: [source, fc], now: evalAug23)
        XCTAssertTrue(schedule?.fcAndPHSatisfied == true)
        XCTAssertEqual(schedule?.firstUpcoming.source, .routineFullPanel)
        XCTAssertEqual(vm.firstUpcomingRoutineScope(for: fc, in: [source, fc], now: evalAug23), .fullPanel)
    }

    // 5. The Full Test Panel stays anchored to the prior full test and does not move.
    func testFullPanelStaysAnchoredToPriorFullTest() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2, pH: 7.6, source: source)
        let vm = PoolViewModel()
        let withFC = vm.nextTestSchedule(for: fc, in: [source, fc], now: evalAug23)
        let withoutFC = vm.nextTestSchedule(for: source, in: [source], now: evalAug23)
        XCTAssertEqual(withFC?.fullPanel.recommendedDate, aug25)
        XCTAssertEqual(withFC?.fullPanel.recommendedDate, withoutFC?.fullPanel.recommendedDate,
                       "An fcAndPH test must not move the Full Test Panel anchor.")
    }

    // 6. Carried-forward TA does not generate a fresh TA treatment in fcAndPH mode.
    func testCarriedForwardTADoesNotGenerateTATreatment() {
        // TA 190 @ pH 7.6, FC 6, CYA 50 reliably generates a TA treatment on a full test.
        let source = fullTest(date: aug18, ta: 190, pH: 7.6, fc: 6, cya: 50)
        let fullControl = fullTest(date: aug23, ta: 190, pH: 7.6, fc: 6, cya: 50)
        let fc = fcAndPHTest(date: aug23, fc: 3, pH: 7.6, source: source)

        let fullTreatments = engine.validatedTreatments(for: fullControl, config: config)
        let fcTreatments = engine.validatedTreatments(for: fc, config: config, recentHistory: [source])

        XCTAssertTrue(fullTreatments.contains { $0.targetParameter == "totalAlkalinity" && $0.amount > 0 },
                      "Control: a full test with high TA generates a TA treatment.")
        XCTAssertFalse(fcTreatments.contains { $0.targetParameter == "totalAlkalinity" && $0.amount > 0 },
                       "Stale carried-forward TA must not generate a fresh TA treatment.")
    }

    // 7. Fresh FC can still generate its chlorine treatment.
    func testFreshLowFCStillGeneratesChlorineTreatment() {
        let source = fullTest(date: aug18, ta: 100)
        let fc = fcAndPHTest(date: aug23, fc: 1.0, pH: 7.5, source: source) // fresh FC below minimum
        let treatments = engine.validatedTreatments(for: fc, config: config, recentHistory: [source])
        XCTAssertTrue(treatments.contains { $0.targetParameter == "freeChlorine" && $0.amount > 0 },
                      "Fresh low FC must still generate a chlorine treatment.")
    }

    // 8. Fresh pH can still generate a pH treatment when policy warrants.
    func testFreshHighPHStillGeneratesPHTreatment() {
        let source = fullTest(date: aug18, ta: 100)
        let fc = fcAndPHTest(date: aug23, fc: 3, pH: 8.0, source: source) // fresh high pH
        let treatments = engine.validatedTreatments(for: fc, config: config, recentHistory: [source])
        XCTAssertTrue(treatments.contains { $0.targetParameter == "pH" && $0.amount > 0 },
                      "Fresh high pH must still generate a pH treatment.")
    }

    // 9. Carried-forward chemistry remains available with its ORIGINAL measuredAt.
    func testCarriedForwardChemistryKeepsOriginalEvidence() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2, pH: 7.6, source: source)
        XCTAssertEqual(fc.totalAlkalinity, 170)
        XCTAssertEqual(fc.calciumHardness, 340)
        XCTAssertEqual(fc.cyanuricAcid, 48)
        XCTAssertEqual(fc.evidenceDate(for: "totalAlkalinity"), aug18)
        XCTAssertEqual(fc.evidenceDate(for: "freeChlorine"), aug23)
    }

    // 10. No focused Check -> no focused-Check copy (discretionary retest instead).
    func testExpectedResponseCopyConditionsOnFocusedCheckExistence() {
        let t = PoolTest(date: aug23, pH: 8.0, testMethod: .liquidDropKit)
        let acid = Treatment(chemicalName: "Dry Acid (Sodium Bisulfate)", actionDescription: "Lower pH",
                             amount: 1, unit: "lbs", instructions: "", urgency: .recommended,
                             targetParameter: "pH", sortOrder: 1, expectedEffectParameter: "pH",
                             expectedDelta: -0.3, effectDelayHours: 4, poolTest: t)
        t.treatments = [acid]

        let noCheckCopy = ExternalReviewExportBuilder.expectedResponseText(for: acid)
        XCTAssertFalse(noCheckCopy.contains("focused Check"), "No Check must not reference a focused Check.")
        XCTAssertTrue(noCheckCopy.contains("Retest"))

        let check = Treatment(chemicalName: "Check pH", actionDescription: "", amount: 0, unit: "",
                              instructions: "", urgency: .recommended, targetParameter: "pH", sortOrder: 2,
                              poolTest: t)
        check.workflowStepKind = .focusedCheck
        check.parentTreatmentID = acid.id
        t.treatments = [acid, check]
        let withCheckCopy = ExternalReviewExportBuilder.expectedResponseText(for: acid)
        XCTAssertTrue(withCheckCopy.contains("focused Check"), "A real Check should be referenced when present.")
    }

    // 11. Segmented-control test-type icons.
    func testRoutineScopeIcons() {
        XCTAssertEqual(RoutineTestScope.fcAndPH.iconName, "drop.fill")
        XCTAssertEqual(RoutineTestScope.fullPanel.iconName, "testtube.2")
    }

    // 12. Export omits a satisfied FC & pH quick check but keeps the upcoming Full Test Panel.
    func testSatisfiedFCAndPHOmittedFromExport() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2, pH: 7.6, source: source)
        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: fc, in: [source, fc], now: evalAug23)
        XCTAssertTrue(schedule?.fcAndPHSatisfied == true)

        let line = ExternalReviewExportBuilder.routineTimingLine(schedule: schedule) { _ in "DATE" }
        XCTAssertFalse(line.contains("Test FC & pH"),
                       "A satisfied FC & pH quick check must not appear in the export: \(line)")
        XCTAssertTrue(line.contains("Full Test Panel"),
                      "The upcoming Full Test Panel must remain in the export: \(line)")
    }

    // 13. While both routine tests are still upcoming, the export reports both.
    func testBothRoutineEventsExportWhenPending() {
        let source = fullTest(date: aug18)
        let vm = PoolViewModel()
        // One day after the anchor, the +3d FC & pH quick check is still upcoming alongside the Full Panel.
        let schedule = vm.nextTestSchedule(for: source, in: [source], now: aug18.addingTimeInterval(86_400))
        XCTAssertEqual(schedule?.firstUpcoming.source, .routineFCAndPH)

        let line = ExternalReviewExportBuilder.routineTimingLine(schedule: schedule) { _ in "DATE" }
        XCTAssertTrue(line.contains("Test FC & pH"), "Both routine tests pending: FC & pH must export: \(line)")
        XCTAssertTrue(line.contains("Full Test Panel"), "Both routine tests pending: Full Panel must export: \(line)")
    }

    // 14. Swim-readiness evidence type and its explanation agree for observed FC & pH evidence.
    func testEvidenceTypeAndExplanationAgreeForObservedFCAndPH() {
        let source = fullTest(date: aug18)
        let fc = fcAndPHTest(date: aug23, fc: 2.0, pH: 7.6, source: source)
        let assessment = SwimabilityV2Engine().assess(request: request(fc, history: [source]), evaluationDate: evalAug23)
        XCTAssertEqual(assessment.evidenceType, .observed)
        XCTAssertTrue(assessment.summary.contains(assessment.evidenceType.rawValue),
                      "Explanation must name the reported evidence type: \(assessment.summary)")
        XCTAssertFalse(assessment.summary.contains("predicted"),
                       "Observed evidence must not describe itself as predicted: \(assessment.summary)")
    }
}
