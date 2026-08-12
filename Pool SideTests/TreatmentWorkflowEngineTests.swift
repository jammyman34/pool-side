import XCTest
@testable import Pool_Side

final class TreatmentWorkflowEngineTests: XCTestCase {
    func testOptionalChlorineCreatesOptionalFocusedCheckWithoutChangingRoutineNextPoolTest() {
        let testDate = Date(timeIntervalSince1970: 1_800_100_000)
        let test = PoolTest(
            date: testDate,
            pH: 7.6,
            freeChlorine: 2.5,
            totalChlorine: 2.5,
            totalAlkalinity: 160,
            calciumHardness: 350,
            cyanuricAcid: 60,
            waterClarityAssessment: .clear,
            visibleAlgaeAssessment: .absent
        )
        let treatment = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Maintenance top-off toward 3 ppm",
            amount: 0.1,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .optional,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        test.treatments = [treatment]

        let check = TreatmentWorkflowEngine().makeCheckStep(after: treatment, sortOrder: 2)
        XCTAssertEqual(check?.chemicalName, "Check FC & CC")
        XCTAssertEqual(check?.checkParameters, ["freeChlorine", "combinedChlorine"])
        XCTAssertEqual(check?.urgency, .optional)
        XCTAssertEqual(check?.workflowStepKind, .focusedCheck)

        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [treatment, check].compactMap { $0 },
            watchlist: [],
            recentHistory: [],
            config: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false, chlorinePreference: .liquidChlorine12_5)
        )
        XCTAssertEqual(recommendation.title, "Next full pool test")
        XCTAssertEqual(recommendation.source.rawValue, "treatmentPlan")
        XCTAssertNotNil(recommendation.recommendedDate)
    }

    func testLowFCCheckWaitActivatesFromTreatmentCompletionTime() {
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let test = PoolTest(date: completedAt.addingTimeInterval(-600), freeChlorine: 1.5, totalChlorine: 1.5, cyanuricAcid: 60)
        let treatment = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Raise free chlorine toward 3 ppm",
            amount: 0.5,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .needsAttention,
            isCompleted: true,
            completedAt: completedAt,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        let check = TreatmentWorkflowEngine().makeCheckStep(after: treatment, sortOrder: 2)!
        test.treatments = [treatment, check]

        let engine = TreatmentWorkflowEngine()
        XCTAssertEqual(engine.availableDate(for: check, in: test.treatments), completedAt.addingTimeInterval(3600))
        XCTAssertEqual(engine.state(for: check, in: test.treatments, evaluationDate: completedAt.addingTimeInterval(1800)), .waiting(availableAt: completedAt.addingTimeInterval(3600)))
        XCTAssertEqual(engine.state(for: check, in: test.treatments, evaluationDate: completedAt.addingTimeInterval(3700)), .current)
    }

    func testFocusedCheckEvidenceDatesOnlyUpdateMeasuredParameters() {
        let originalDate = Date(timeIntervalSince1970: 1_800_100_000)
        let measuredAt = originalDate.addingTimeInterval(3600)
        let test = PoolTest(
            date: originalDate,
            pH: 7.6,
            freeChlorine: 4.0,
            totalChlorine: 4.0,
            totalAlkalinity: 160,
            calciumHardness: 350,
            cyanuricAcid: 60
        )

        test.freeChlorine = 6.5
        test.totalChlorine = 6.5
        test.freeChlorineMeasuredAt = measuredAt
        test.totalChlorineMeasuredAt = measuredAt

        XCTAssertEqual(test.evidenceDate(for: "freeChlorine"), measuredAt)
        XCTAssertEqual(test.evidenceDate(for: "combinedChlorine"), measuredAt)
        XCTAssertEqual(test.evidenceDate(for: "pH"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "totalAlkalinity"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "calciumHardness"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "cyanuricAcid"), originalDate)
    }
}
