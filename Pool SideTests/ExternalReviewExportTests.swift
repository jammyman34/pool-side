import XCTest
@testable import Pool_Side

final class ExternalReviewExportTests: XCTestCase {
    func testExternalReviewExportIncludesProductDoseTimingTrendAndSuppressionDetailsWithoutRawIdentifiers() throws {
        let engine = ChemistryEngine()
        var config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid)
        config.setSaltwater(true)
        let test = ChemistryTestFixtures.currentPool()
        let history = ChemistryTestFixtures.pHDriftHistory()
        let acidTemplate = try XCTUnwrap(engine.validatedTreatments(for: test, config: config, recentHistory: history).first {
            $0.targetParameter == "pH" && $0.amount > 0
        })
        let acidTreatment = acidTemplate.toTreatment(linkedTo: test)
        let substituted = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: acidTreatment,
            test: test,
            productID: .muriaticAcid31,
            config: config
        )).toTreatment(linkedTo: test)
        let watchlist = Treatment(
            chemicalName: "Wait for Acid Treatment",
            actionDescription: "A recent acid treatment is still in its wait/retest window, so another acid dose is being withheld.",
            amount: 0,
            unit: "",
            instructions: "Wait before adding more acid.",
            urgency: .advisory,
            targetParameter: "pH"
        )

        let export = ExternalReviewExportBuilder.treatmentAuditSection(
            config: config,
            test: test,
            treatments: [substituted, watchlist],
            recentHistory: history,
            routineNextTestTiming: "Tomorrow"
        )

        XCTAssertTrue(export.contains("Preferred chlorine: Salt Chlorine Generator"))
        XCTAssertTrue(export.contains("Global preference: Dry Acid (Sodium Bisulfate)"))
        XCTAssertTrue(export.contains("Treatment product: Muriatic Acid (31.45%)"))
        XCTAssertTrue(export.contains("Product concentration: 31.45% hydrochloric acid"))
        XCTAssertTrue(export.contains("Differs from global preference: Yes"))
        XCTAssertTrue(export.contains("Calculated dose before safety cap"))
        XCTAssertTrue(export.contains("Final recommended dose"))
        XCTAssertTrue(export.contains("Safety cap applied"))
        XCTAssertTrue(export.contains("Salt-system behavior"))
        XCTAssertTrue(export.contains("pH has gradually risen"))
        XCTAssertTrue(export.contains("Time since last completed acid treatment: none found"))
        XCTAssertTrue(export.contains("Treatment verification classification"))
        XCTAssertTrue(export.contains("Treatment verification timing"))
        XCTAssertTrue(export.contains("Recommended next routine test timing: Tomorrow"))
        XCTAssertTrue(export.contains("Suppressed treatment reasons"))
        XCTAssertFalse(export.contains("muriatic_acid"), "External export should not expose raw implementation identifiers.")
        XCTAssertFalse(export.contains("dry_acid"), "External export should not expose raw implementation identifiers.")
    }
}
