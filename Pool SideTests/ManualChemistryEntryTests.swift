import XCTest
import SwiftData
@testable import Pool_Side

/// Manual numeric entry in the test-log form must preserve the exact value the user typed and never
/// snap it to the slider/step increment. This exercises the shared quantization seam
/// (`ChemicalEntryQuantizer`) used by every manually editable chemistry field, then follows the
/// preserved value through persistence, recalculation, Pool Score, treatment generation, Swimability
/// V2, and the External Review export. Slider snapping and measurement-resolution behavior must be
/// unaffected.
final class ManualChemistryEntryTests: XCTestCase {

    private let engine = ChemistryEngine()
    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    // Field profiles mirror AddTestView's test-strip profiles for the fields under test.
    private let cyaRange: ClosedRange<Double> = 0...300
    private let cyaStep = 5.0
    private let taRange: ClosedRange<Double> = 0...240
    private let taStep = 5.0
    private let saltRange: ClosedRange<Double> = 1000...5000
    private let saltStep = 100.0
    private let phRange: ClosedRange<Double> = 6.2...8.4
    private let phStep = 0.1

    // MARK: - 1 & 2. CYA manual entry preserves exact values (the reported dogfood cases)

    func testCYAManual48StaysExactly48() {
        let value = ChemicalEntryQuantizer.manualEntryValue(48, range: cyaRange, decimalPlaces: 0)
        XCTAssertEqual(value, 48, "Manual CYA 48 must not snap to 50.")
    }

    func testCYAManual44StaysExactly44() {
        let value = ChemicalEntryQuantizer.manualEntryValue(44, range: cyaRange, decimalPlaces: 0)
        XCTAssertEqual(value, 44, "Manual CYA 44 must not snap to 45.")
    }

    // MARK: - 3. A manually entered non-CYA value also preserves exact input

    func testNonCYAManualEntryPreservesExactInput() {
        // TA (step 5) — an off-step whole number must survive.
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(92, range: taRange, decimalPlaces: 0), 92)
        // Salt (step 100) — an off-step value must survive.
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(3150, range: saltRange, decimalPlaces: 0), 3150)
        // pH (step 0.1, one decimal place) — an in-precision value must survive.
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(7.3, range: phRange, decimalPlaces: 1), 7.3, accuracy: 1e-9)
    }

    func testManualEntryStillClampsToRangeAndDisplayPrecision() {
        // Min/max validation is preserved.
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(999, range: cyaRange, decimalPlaces: 0), 300)
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(-5, range: cyaRange, decimalPlaces: 0), 0)
        // Rounding is only to the field's display precision, never to the slider step.
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(48.4, range: cyaRange, decimalPlaces: 0), 48)
        XCTAssertEqual(ChemicalEntryQuantizer.manualEntryValue(7.46, range: phRange, decimalPlaces: 1), 7.5, accuracy: 1e-9)
    }

    // MARK: - 4. Slider behavior still snaps exactly as before

    func testSliderSnappingUnchanged() {
        // The slider path still snaps to the nearest step, exactly as before this fix.
        XCTAssertEqual(ChemicalEntryQuantizer.snappedSliderValue(48, range: cyaRange, step: cyaStep, decimalPlaces: 0), 50)
        XCTAssertEqual(ChemicalEntryQuantizer.snappedSliderValue(44, range: cyaRange, step: cyaStep, decimalPlaces: 0), 45)
        XCTAssertEqual(ChemicalEntryQuantizer.snappedSliderValue(92, range: taRange, step: taStep, decimalPlaces: 0), 90)
        XCTAssertEqual(ChemicalEntryQuantizer.snappedSliderValue(3150, range: saltRange, step: saltStep, decimalPlaces: 0), 3200)
    }

    // MARK: - 5. Save/reopen preserves exact manual values (persistence round-trip)

    func testSaveAndReopenPreservesExactManualValues() throws {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        let cya = ChemicalEntryQuantizer.manualEntryValue(48, range: cyaRange, decimalPlaces: 0)
        let ta = ChemicalEntryQuantizer.manualEntryValue(92, range: taRange, decimalPlaces: 0)
        let id = UUID()
        let saved = PoolTest(id: id, date: Date(), pH: 7.3, freeChlorine: 3, totalChlorine: 3,
                             totalAlkalinity: ta, calciumHardness: 350, cyanuricAcid: cya,
                             testMethod: .testStrips)
        context.insert(saved)
        try context.save()

        // Reopen via a fresh fetch from the same store.
        let refetched = try context.fetch(FetchDescriptor<PoolTest>(
            predicate: #Predicate { $0.id == id }
        )).first
        XCTAssertNotNil(refetched)
        XCTAssertEqual(refetched?.cyanuricAcid, 48)
        XCTAssertEqual(refetched?.totalAlkalinity, 92)
        XCTAssertEqual(refetched?.pH ?? 0, 7.3, accuracy: 1e-9)
    }

    // MARK: - 6. Recalculate receives the exact stored value (not a snapped one)

    func testRecalculateReceivesExactStoredValue() {
        let t = poolTest(cya: 48)
        let readings = engine.allReadings(for: t, config: config)
        let cyaReading = readings.first { $0.key == "cyanuricAcid" }
        XCTAssertNotNil(cyaReading)
        XCTAssertEqual(cyaReading?.value, 48, "The engine must recalculate against the exact stored CYA, not a snapped value.")
        // Source evidence is never mutated by recalculation.
        XCTAssertEqual(t.cyanuricAcid, 48)
    }

    // MARK: - 7. Pool Score / treatment generation / Swimability consume a non-snapped value safely

    func testDownstreamConsumersAcceptNonSnappedValueWithoutMutating() {
        let t = poolTest(cya: 48)

        // Pool Score authority.
        let score = engine.overallScore(for: t, config: config)
        XCTAssertTrue((0...100).contains(score))
        _ = engine.scoreAssessment(for: t, config: config)

        // Treatment generation.
        _ = engine.validatedTreatments(for: t, config: config, recentHistory: [])

        // Swimability V2.
        let request = AIRecommendationRequest(currentTest: t, recentHistory: [], poolConfig: config)
        _ = SwimabilityV2Engine().assess(request: request, evaluationDate: Date())

        // None of these consumers rewrite the stored source measurement.
        XCTAssertEqual(t.cyanuricAcid, 48)
    }

    // MARK: - 8. External Review Export prints the exact stored value

    func testExternalReviewExportPrintsExactStoredValue() {
        // A completed focused CYA check whose result test carries the exact manual value.
        let resultTest = poolTest(cya: 48)
        let check = Treatment(chemicalName: "Check CYA", actionDescription: "", amount: 0, unit: "",
                              instructions: "", urgency: .recommended, isCompleted: true,
                              targetParameter: "cyanuricAcid", sortOrder: 1)
        check.workflowStepKind = .focusedCheck
        check.checkParameters = ["cyanuricAcid"]
        check.checkResultTestID = resultTest.id
        resultTest.treatments = [check]

        let export = ExternalReviewExportBuilder.treatmentAuditSection(
            config: config, test: resultTest, treatments: resultTest.treatments,
            recentHistory: [], routineNextTestTiming: "Tomorrow"
        )
        XCTAssertTrue(export.contains("result: 48"),
                      "Export must print the exact stored CYA value (48), not a snapped one. Got:\n\(export)")
        XCTAssertFalse(export.contains("result: 50"))
    }

    // MARK: - 9. Measurement-resolution still applies without rewriting the source measurement

    func testMeasurementResolutionAppliesAsDerivedInterpretationOnly() {
        // The stored value stays exact (source evidence)...
        let t = poolTest(cya: 48)
        XCTAssertEqual(t.cyanuricAcid, 48)

        // ...while measurement resolution still treats 48 and 50 as indistinguishable for a liquid-drop
        // kit (CYA increment = 10). Resolution is a derived interpretation, applied by consumers; it does
        // not rewrite the stored measurement.
        let resolution = MeasurementResolution(testMethod: .liquidDropKit, chlorineSampleSize: nil)
        XCTAssertEqual(resolution.increment(for: .cyanuricAcid), 10, accuracy: 1e-9)
        XCTAssertTrue(resolution.indistinguishable(48, 50, for: .cyanuricAcid))
        // And two clearly different readings remain distinguishable.
        XCTAssertFalse(resolution.indistinguishable(48, 70, for: .cyanuricAcid))
    }

    // MARK: - Helpers

    private func poolTest(cya: Double) -> PoolTest {
        PoolTest(date: Date(), pH: 7.4, freeChlorine: 3, totalChlorine: 3,
                 totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: cya,
                 testMethod: .liquidDropKit,
                 visualIndicators: [VisualIndicator.crystalClear.rawValue])
    }
}
