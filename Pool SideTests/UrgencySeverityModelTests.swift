import XCTest
import SwiftUI
@testable import Pool_Side

/// The canonical three-level urgency model (Act Now / Needs Attention / Recommended) derived from
/// ChemistryPolicy action state + severity, plus the single status-color mapping and severity-aware Pool
/// Score wording. These are policy-derived, never hard-coded to any specific pool.
final class UrgencySeverityModelTests: XCTestCase {

    private func ctx(cya: Double = 40,
                     surface: SurfaceType = .plaster,
                     salt: Bool = false,
                     sample: TaylorSampleSize? = .tenMl) -> ChemistryPolicyContext {
        ChemistryPolicyContext.make(
            config: PoolConfiguration(volumeGallons: 20_000, surfaceType: surface, isSaltwater: salt),
            cyanuricAcid: cya, pH: 7.4, totalAlkalinity: 90,
            hasScalingEvidence: false, chlorineSampleSize: sample
        )
    }

    private func statusUrgency(_ p: ChemistryParameter, _ value: Double, _ context: ChemistryPolicyContext) -> TreatmentUrgency? {
        ChemistryPolicy.classify(p, value: value, context: context).statusUrgency
    }

    // MARK: - pH severity bands (< 6.8 / 6.8–7.0 / 7.0–7.8 / 7.8–8.0 / > 8.0)

    func testPHSeverityBands() {
        let c = ctx()
        XCTAssertEqual(statusUrgency(.pH, 6.5, c), .immediate,      "< 6.8 is Act Now")
        XCTAssertEqual(statusUrgency(.pH, 6.9, c), .needsAttention, "6.8–7.0 is Needs Attention")
        XCTAssertEqual(statusUrgency(.pH, 7.0, c), .recommended,    "7.0 swim-safe, below operating range")
        XCTAssertNil(statusUrgency(.pH, 7.4, c),                    "ideal")
        XCTAssertEqual(statusUrgency(.pH, 7.7, c), .recommended,    "swim-safe optimization")
        XCTAssertEqual(statusUrgency(.pH, 7.9, c), .needsAttention, "7.8–8.0 is Needs Attention")
        XCTAssertEqual(statusUrgency(.pH, 8.1, c), .immediate,      "> 8.0 is Act Now")
    }

    // MARK: - FC severity (severe / below-readiness / recommended / ideal / above-ceiling / severe-high)

    func testFreeChlorineSeverityBands() {
        let c = ctx(cya: 40)   // readiness 3.0, operating ~4.5–6.5, ceiling 10, severe-high 15
        XCTAssertEqual(statusUrgency(.freeChlorine, 1.0, c), .immediate,      "below half the readiness minimum")
        XCTAssertEqual(statusUrgency(.freeChlorine, 2.0, c), .needsAttention, "below readiness, not severe")
        XCTAssertEqual(statusUrgency(.freeChlorine, 3.5, c), .recommended,    "readiness–operating target")
        XCTAssertNil(statusUrgency(.freeChlorine, 5.0, c),                    "operating range = ideal")
        XCTAssertEqual(statusUrgency(.freeChlorine, 8.0, c), .recommended,    "above target below ceiling = informational")
        XCTAssertEqual(statusUrgency(.freeChlorine, 12.0, c), .needsAttention, "above re-entry ceiling, not severe")
        XCTAssertEqual(statusUrgency(.freeChlorine, 16.0, c), .immediate,      "above severe-high threshold (15)")
    }

    func testSevereHighThresholdIsFifteenNotShockLevel() {
        // Explicit resolver: max(15, reentryCeiling), independent of shock level.
        XCTAssertEqual(FreeChlorinePolicy.severeHighThreshold(cyanuricAcid: 40), 15)
    }

    // MARK: - CC severity (≤0.5 / 0.5–1.0 / >1.0)

    func testCombinedChlorineSeverityBands() {
        let c = ctx()
        XCTAssertEqual(statusUrgency(.combinedChlorine, 0.5, c), .recommended,    "≤ 0.5 acceptable")
        XCTAssertEqual(statusUrgency(.combinedChlorine, 0.6, c), .needsAttention, "0.5–1.0 Needs Attention")
        XCTAssertEqual(statusUrgency(.combinedChlorine, 1.5, c), .immediate,      "> 1.0 Act Now")
    }

    // MARK: - Non-swim extremes escalate to Act Now (equipment/surface protection)

    func testNonSwimExtremesAreActNow() {
        XCTAssertEqual(statusUrgency(.calciumHardness, 100, ctx(surface: .plaster)), .immediate, "CH extreme low")
        XCTAssertNil(statusUrgency(.calciumHardness, 300, ctx(surface: .plaster)),               "CH ideal")
        XCTAssertEqual(statusUrgency(.totalAlkalinity, 50, ctx()), .immediate,                    "TA extreme low")
        XCTAssertEqual(statusUrgency(.cyanuricAcid, 100, ctx()), .immediate,                      "CYA extreme high")
    }

    // MARK: - Canonical color mapping (reuses existing semantic status colors)

    func testUrgencyStatusColorMapping() {
        XCTAssertEqual(PoolColor.urgencyStatusColor(.immediate), PoolColor.statusCritical)
        XCTAssertEqual(PoolColor.urgencyStatusColor(.needsAttention), PoolColor.statusOffRange)
        XCTAssertEqual(PoolColor.urgencyStatusColor(.recommended), PoolColor.statusSlight)
    }

    // MARK: - Pool Score wording consumes the same canonical severity

    func testScoreDriverWordingReflectsSeverity() {
        let config = PoolConfiguration(volumeGallons: 20_000, surfaceType: .plaster, isSaltwater: false)
        let engine = ChemistryEngine()

        // FC below readiness (moderate) → "below swim-readiness minimum", never "critically low".
        let moderate = PoolTest(date: Date(), pH: 7.4, freeChlorine: 2.0, totalChlorine: 2.0,
                                totalAlkalinity: 90, calciumHardness: 300, cyanuricAcid: 40, testMethod: .liquidDropKit)
        let moderateDrivers = engine.scoreAssessment(for: moderate, config: config).drivers
        XCTAssertTrue(moderateDrivers.contains { $0.contains("FC") && $0.contains("below swim-readiness minimum") },
                      "Moderate low FC reads 'below swim-readiness minimum'. Drivers: \(moderateDrivers)")
        XCTAssertFalse(moderateDrivers.contains { $0.contains("FC") && $0.contains("critically low") },
                       "Moderate low FC must not read 'critically low'.")

        // FC severely low → "critically low".
        let severe = PoolTest(date: Date(), pH: 7.4, freeChlorine: 1.0, totalChlorine: 1.0,
                              totalAlkalinity: 90, calciumHardness: 300, cyanuricAcid: 40, testMethod: .liquidDropKit)
        let severeDrivers = engine.scoreAssessment(for: severe, config: config).drivers
        XCTAssertTrue(severeDrivers.contains { $0.contains("FC") && $0.contains("critically low") },
                      "Severely low FC reads 'critically low'. Drivers: \(severeDrivers)")
    }
}
