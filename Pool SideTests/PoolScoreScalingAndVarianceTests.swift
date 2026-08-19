import XCTest
import SwiftData
@testable import Pool_Side

/// Pool Score maintenance-health refinements: the TA test-strip variance discount no longer masks a
/// persistently elevated TA, scoring stays anchored to canonical ChemistryPolicy ranges, and a modest
/// combined scaling-tendency penalty adds context without gating swim readiness.
final class PoolScoreScalingAndVarianceTests: XCTestCase {

    private let engine = ChemistryEngine()
    // Default chlorine (cal-hypo) → hypochlorite sanitizer → TA ideal 80–100; config default method = strips.
    private let plaster = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster)

    /// Balanced, all-ideal-except-as-specified test. FC 3.5 @ CYA 40 is inside the 3–4 operating band.
    private func t(pH: Double, ta: Double, ch: Double, cya: Double = 40, fc: Double = 3.5,
                   method: TestMethod = .testStrips, date: Date = Date()) -> PoolTest {
        PoolTest(date: date, pH: pH, freeChlorine: fc, totalChlorine: fc, totalAlkalinity: ta,
                 calciumHardness: ch, cyanuricAcid: cya, testMethod: method,
                 visualIndicators: [VisualIndicator.crystalClear.rawValue])
    }

    // MARK: - 1. TA variance discount

    // Persistent elevated TA (170 → 170) on strips is NOT treated as measurement noise: the discount does
    // not apply, so the score is identical to having no prior reading (full TA penalty either way).
    func testPersistentHighTAIsNotTreatedAsStripNoise() {
        let now = Date()
        let cur = t(pH: 7.4, ta: 170, ch: 300, method: .testStrips, date: now)
        let prev = t(pH: 7.4, ta: 170, ch: 300, method: .testStrips, date: now.addingTimeInterval(-86_400))

        let withHistory = engine.overallScore(for: cur, previousTest: prev, recentHistory: [prev], config: plaster)
        let noHistory = engine.overallScore(for: cur, config: plaster)

        XCTAssertEqual(withHistory, noHistory,
                       "Two equal, well-elevated TA readings are persistence, not strip variance — no discount.")
        XCTAssertLessThan(withHistory, engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 300), config: plaster),
                          "Elevated TA still lowers the score.")
    }

    // A small, plausible strip fluctuation that lands within one strip increment of the ideal band may still
    // be treated as variance: the discount lifts the score relative to the no-history (undiscounted) case.
    func testNearBoundaryStripFluctuationMayStillBeDiscounted() {
        let now = Date()
        // TA 130 on strips is within one 40 ppm strip increment of the hypochlorite ideal upper (100).
        let cur = t(pH: 7.4, ta: 130, ch: 300, method: .testStrips, date: now)
        let prev = t(pH: 7.4, ta: 130, ch: 300, method: .testStrips, date: now.addingTimeInterval(-86_400))

        let withHistory = engine.overallScore(for: cur, previousTest: prev, recentHistory: [prev], config: plaster)
        let noHistory = engine.overallScore(for: cur, config: plaster)

        XCTAssertGreaterThan(withHistory, noHistory,
                             "A near-boundary strip reading is plausibly in-range noise and may be discounted.")
    }

    // The CURRENT TEST's method controls variance — a precise drop-kit test never inherits strip variance
    // just because the saved config default method is strips.
    func testActualTestMethodControlsVarianceNotConfigDefault() {
        XCTAssertEqual(plaster.testMethod, .testStrips, "Config default is strips (the source of the old bug).")
        let now = Date()

        // Drop-kit near-boundary reading: no discount regardless of history (config default is still strips).
        let dropCur = t(pH: 7.4, ta: 130, ch: 300, method: .liquidDropKit, date: now)
        let dropPrev = t(pH: 7.4, ta: 130, ch: 300, method: .liquidDropKit, date: now.addingTimeInterval(-86_400))
        XCTAssertEqual(engine.overallScore(for: dropCur, previousTest: dropPrev, recentHistory: [dropPrev], config: plaster),
                       engine.overallScore(for: dropCur, config: plaster),
                       "A drop-kit test does not inherit strip variance from the config default.")

        // The same values on strips DO get the variance treatment — proving the method is the deciding factor.
        let stripCur = t(pH: 7.4, ta: 130, ch: 300, method: .testStrips, date: now)
        let stripPrev = t(pH: 7.4, ta: 130, ch: 300, method: .testStrips, date: now.addingTimeInterval(-86_400))
        XCTAssertGreaterThan(engine.overallScore(for: stripCur, previousTest: stripPrev, recentHistory: [stripPrev], config: plaster),
                             engine.overallScore(for: stripCur, config: plaster))
    }

    // MARK: - 2. Canonical ChemistryPolicy ranges remain the scoring SSOT (plaster CH 200–400)

    func testScoreUsesPolicyPlasterCalciumRange() {
        let baseline = engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 300), config: plaster)
        // Endpoints of the policy ideal band are unpenalized…
        XCTAssertEqual(engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 200), config: plaster), baseline, "CH 200 (policy lower) is ideal.")
        XCTAssertEqual(engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 400), config: plaster), baseline, "CH 400 (policy upper) is ideal.")
        // …and just past the policy upper bound it is penalized.
        XCTAssertLessThan(engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 401), config: plaster), baseline, "CH 401 is above the policy ideal band.")
    }

    // MARK: - 3. Combined scaling-risk penalty

    // CH 380 on its own (balanced TA and pH) creates no penalty — it is inside the policy ideal band.
    func testUpperRangeCalciumAloneIsNotPenalized() {
        let baseline = engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 300), config: plaster)
        XCTAssertEqual(engine.overallScore(for: t(pH: 7.4, ta: 90, ch: 380), config: plaster), baseline,
                       "Upper-range but in-band CH is not penalized by itself.")
        // Even at the upper pH boundary, CH 380 with a balanced (ideal) TA is not penalized.
        XCTAssertEqual(engine.overallScore(for: t(pH: 7.6, ta: 90, ch: 380), config: plaster),
                       engine.overallScore(for: t(pH: 7.6, ta: 90, ch: 300), config: plaster),
                       "The combined penalty requires elevated TA; balanced TA means no scaling-tendency penalty.")
    }

    // Elevated TA + upper-range CH + upper-boundary pH produces a modest, non-dominant combined penalty.
    func testCombinedScalingTendencyProducesModestPenalty() {
        // No history → variance is irrelevant; isolate the combined penalty by moving CH out of the upper quarter.
        let combined = engine.overallScore(for: t(pH: 7.6, ta: 170, ch: 380), config: plaster)
        let noUpperCH = engine.overallScore(for: t(pH: 7.6, ta: 170, ch: 300), config: plaster)

        let delta = noUpperCH - combined
        XCTAssertEqual(delta, 4, "The combined scaling-tendency penalty is a modest, fixed 4 points.")
        XCTAssertLessThanOrEqual(delta, 6, "It stays within the minor context-penalty band (does not dominate).")
        XCTAssertGreaterThan(combined, 60, "A clear, balanced pool with a scaling tendency is not driven into a poor grade.")
    }

    // MARK: - Non-swim-gating

    @MainActor func testCombinedScalingPenaltyIsNotSwimGating() {
        let vm = PoolViewModel(); vm.saveConfig(plaster)
        let test = t(pH: 7.6, ta: 170, ch: 380) // triggers the combined penalty; all params swim-safe
        let assessment = vm.scoreAssessment(for: test, in: [test])
        XCTAssertGreaterThanOrEqual(assessment.score, 0)
        XCTAssertLessThanOrEqual(assessment.score, 100)
        XCTAssertNotEqual(vm.swimReadinessAssessment(for: test, in: [test]).state, .doNotSwim,
                          "The maintenance scaling penalty never blocks swimming (Swimability V2 owns readiness).")
    }
}
