import XCTest
import SwiftData
@testable import Pool_Side

/// Increment 2 — one canonical, ChemistryPolicy-aligned Pool Score authority; score never decides
/// swim readiness (that is Swimability V2).
final class PoolScoreAuthorityTests: ConfigIsolatedTestCase {

    private let engine = ChemistryEngine()
    private let hypochlorite = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)
    private var acidic: PoolConfiguration {
        PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false, chlorinePreference: .tablets)
    }

    /// All-ideal baseline (hypochlorite): FC 5 (CYA 40), pH 7.4, TA 90, CH 300, CYA 40.
    private func test(ph: Double = 7.4, fc: Double = 5, cc: Double = 0,
                      ta: Double = 90, ch: Double = 300, cya: Double = 40, salt: Double? = nil) -> PoolTest {
        let t = PoolTest(date: Date(), pH: ph, freeChlorine: fc, totalChlorine: fc + cc,
                         totalAlkalinity: ta, calciumHardness: ch, cyanuricAcid: cya, testMethod: .liquidDropKit,
                         visualIndicators: [VisualIndicator.crystalClear.rawValue])
        t.saltLevel = salt
        return t
    }

    private func ctx(_ config: PoolConfiguration, _ t: PoolTest) -> ChemistryPolicyContext {
        .make(config: config, cyanuricAcid: t.cyanuricAcid, pH: t.pH, totalAlkalinity: t.totalAlkalinity,
              hasScalingEvidence: false, chlorineSampleSize: t.taylorSampleSize)
    }

    // A. Same state scored through every public score API returns the same result.
    @MainActor func testAllScoreAPIsAgree() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let t = test(ta: 110) // a non-ideal case to make agreement meaningful
        let engineScore = engine.overallScore(for: t, config: hypochlorite)
        let assessment = engine.scoreAssessment(for: t, config: hypochlorite)
        XCTAssertEqual(engineScore, assessment.score)
        XCTAssertEqual(vm.overallScore(for: t), engineScore)
        XCTAssertEqual(vm.scoreAssessment(for: t, in: [t]).score, engineScore)
        XCTAssertEqual(vm.scoreGrade(engineScore), assessment.grade)
    }

    // B. Hypochlorite TA 100 is canonical ideal and unpenalized.
    func testHypochloriteTA100IsIdeal() {
        let t100 = test(ta: 100), t90 = test(ta: 90)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 100, context: ctx(hypochlorite, t100)).actionState, .ideal)
        XCTAssertEqual(engine.overallScore(for: t100, config: hypochlorite),
                       engine.overallScore(for: t90, config: hypochlorite),
                       "TA 100 (hypochlorite ideal) scores the same as TA 90.")
    }

    // C. Hypochlorite TA 110 is recommendedHigh and lowers the score consistently.
    func testHypochloriteTA110IsRecommendedHighAndScores() {
        let t110 = test(ta: 110), t100 = test(ta: 100)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 110, context: ctx(hypochlorite, t110)).actionState, .recommendedHigh)
        XCTAssertLessThan(engine.overallScore(for: t110, config: hypochlorite),
                          engine.overallScore(for: t100, config: hypochlorite))
        XCTAssertTrue(engine.scoreAssessment(for: t110, config: hypochlorite).drivers.contains("TA above operating range"))
    }

    // D. Acidic-sanitizer TA 110 resolves to its sanitizer-aware ideal (100–120) and is unpenalized.
    func testAcidicSanitizerTA110IsIdeal() {
        let cfg = acidic
        let t110 = test(ta: 110), t105 = test(ta: 105)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 110, context: ctx(cfg, t110)).actionState, .ideal)
        XCTAssertEqual(engine.overallScore(for: t110, config: cfg), engine.overallScore(for: t105, config: cfg))
    }

    // E. pH 7.7: outside operating range, lowers score, but V2 need not block.
    @MainActor func testPH77ScoresMaintenanceButV2MayBeReady() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let t77 = test(ph: 7.7), t74 = test(ph: 7.4)
        XCTAssertNotEqual(ChemistryPolicy.classify(.pH, value: 7.7, context: ctx(hypochlorite, t77)).actionState, .ideal)
        XCTAssertLessThan(engine.overallScore(for: t77, config: hypochlorite), engine.overallScore(for: t74, config: hypochlorite))
        XCTAssertNotEqual(vm.swimReadinessAssessment(for: t77, in: [t77]).state, .doNotSwim, "pH 7.7 is within the swim range.")
    }

    // F. FC above readiness minimum but below treatment target: maintenance penalty, V2 does not block.
    @MainActor func testFCAtReadinessMaintenanceButV2NotBlocking() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let atReadiness = test(fc: 2.5, cya: 40)
        XCTAssertEqual(ChemistryPolicy.classify(.freeChlorine, value: 2.5, context: ctx(hypochlorite, atReadiness)).actionState, .recommendedLow)
        XCTAssertLessThan(engine.overallScore(for: atReadiness, config: hypochlorite), engine.overallScore(for: test(fc: 5), config: hypochlorite))
        XCTAssertNotEqual(vm.swimReadinessAssessment(for: atReadiness, in: [atReadiness]).state, .doNotSwim)
    }

    // G. FC below readiness minimum: stronger score penalty and V2 blocks.
    @MainActor func testFCBelowReadinessStrongerPenaltyAndV2Blocks() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let below = test(fc: 1.0, cya: 40)
        let atReadiness = test(fc: 2.5, cya: 40)
        XCTAssertTrue(ChemistryPolicy.classify(.freeChlorine, value: 1.0, context: ctx(hypochlorite, below)).blocksSwimming)
        XCTAssertLessThan(engine.overallScore(for: below, config: hypochlorite), engine.overallScore(for: atReadiness, config: hypochlorite))
        XCTAssertTrue(vm.swimReadinessAssessment(for: below, in: [below]).swimmingBlocked)
    }

    // H. CH / CYA / salt canonical bands align with ChemistryPolicy.
    func testPoolCareBandsAlignWithPolicy() {
        let plaster = hypochlorite
        XCTAssertEqual(ChemistryPolicy.classify(.calciumHardness, value: 300, context: ctx(plaster, test(ch: 300))).actionState, .ideal)
        XCTAssertEqual(ChemistryPolicy.classify(.cyanuricAcid, value: 40, context: ctx(plaster, test(cya: 40))).actionState, .ideal)
        // CH 220 is ideal per policy (200–400) and therefore unpenalized like CH 300.
        XCTAssertEqual(engine.overallScore(for: test(ch: 220), config: plaster), engine.overallScore(for: test(ch: 300), config: plaster))
    }

    // I. Treatment completion alone does not change the score (no new evidence).
    func testTreatmentCompletionDoesNotChangeScore() {
        let t = test(ph: 7.9)
        let before = engine.overallScore(for: t, config: hypochlorite)
        let treatment = Treatment(chemicalName: "Muriatic Acid", actionDescription: "", amount: 20, unit: "fl oz",
                                  instructions: "", urgency: .recommended, targetParameter: "pH", poolTest: t)
        treatment.isCompleted = true; treatment.completedAt = Date()
        XCTAssertEqual(engine.overallScore(for: t, config: hypochlorite), before)
    }

    // J. A focused Check updates only the measured parameter's contribution.
    @MainActor func testFocusedCheckUpdatesOnlyMeasuredParameter() async throws {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let mc = ModelContext(container)
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let t = PoolTest(date: Date(), pH: 7.9, freeChlorine: 5, totalChlorine: 5, totalAlkalinity: 90,
                         calciumHardness: 300, cyanuricAcid: 40, testMethod: .liquidDropKit)
        mc.insert(t)
        await vm.generateRecommendations(for: t, recentTests: [], modelContext: mc)
        let acid = try XCTUnwrap(t.treatments.first { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })
        await vm.completeTreatment(acid, in: [t], modelContext: mc)
        let check = try XCTUnwrap(vm.dependentCheck(for: acid))
        let taBefore = t.totalAlkalinity
        let scoreBefore = vm.overallScore(for: t)
        try await vm.saveFocusedCheck(check, values: ["pH": 7.4], for: t, allTests: [t], modelContext: mc)
        XCTAssertEqual(t.pH, 7.4)
        XCTAssertEqual(t.totalAlkalinity, taBefore, "Only the checked parameter changes.")
        XCTAssertGreaterThan(vm.overallScore(for: t), scoreBefore, "pH back in range improves the score.")
    }

    // K. Dashboard, completed-row, and export score all use the same canonical value.
    @MainActor func testDashboardCompletedAndExportScoreMatch() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let t = test(ta: 110) // completed workflow (no pending steps)
        let workflows = vm.dashboardWorkflows(from: [t])
        let completed = workflows.completed.first { $0.rootTestID == t.id }
        XCTAssertEqual(completed?.finalScore, vm.overallScore(for: t))
        XCTAssertEqual(vm.scoreAssessment(for: t, in: [t]).score, vm.overallScore(for: t))
    }

    // L. Two configurations do not leak through PoolConfiguration.current.
    @MainActor func testNoGlobalConfigLeakBetweenPools() {
        // CH 175 is below plaster's ideal (200–400) but within vinyl's ideal (150–300).
        let t = test(ch: 175)
        let plasterCfg = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster)
        let vinylCfg = PoolConfiguration(volumeGallons: 32_583, surfaceType: .vinyl)
        XCTAssertLessThan(engine.overallScore(for: t, config: plasterCfg), engine.overallScore(for: t, config: vinylCfg))

        PoolConfiguration.current = plasterCfg
        let vm = PoolViewModel(); vm.saveConfig(vinylCfg)
        XCTAssertEqual(vm.overallScore(for: t), engine.overallScore(for: t, config: vinylCfg),
                       "ViewModel score uses its own config, not the global PoolConfiguration.current.")
    }

    // M. Historical score reconstruction is deterministic.
    func testScoreReconstructionDeterministic() {
        let t = test(ta: 130, cya: 70)
        XCTAssertEqual(engine.overallScore(for: t, config: hypochlorite), engine.overallScore(for: t, config: hypochlorite))
    }

    // N. Score driver text names the actual canonical parameter states.
    func testScoreDriversAreCanonical() {
        let drivers = engine.scoreAssessment(for: test(ph: 7.7, cya: 100), config: hypochlorite).drivers
        XCTAssertTrue(drivers.contains { $0.contains("pH") && $0.contains("above operating range") })
        XCTAssertTrue(drivers.contains { $0.contains("CYA") })
    }

    // O. Pool Score is independent of swim readiness (no readiness claim in the assessment).
    @MainActor func testScoreDoesNotClaimReadiness() {
        let vm = PoolViewModel(); vm.saveConfig(hypochlorite)
        let blocked = test(fc: 0.5, cya: 40) // FC critically low → V2 blocks
        XCTAssertTrue(vm.swimReadinessAssessment(for: blocked, in: [blocked]).swimmingBlocked)
        // Score is still a computed 0–100 maintenance value, independent of the readiness decision.
        let assessment = vm.scoreAssessment(for: blocked, in: [blocked])
        XCTAssertGreaterThanOrEqual(assessment.score, 0)
        XCTAssertLessThanOrEqual(assessment.score, 100)
    }
}
