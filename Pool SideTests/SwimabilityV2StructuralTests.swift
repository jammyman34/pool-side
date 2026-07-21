import XCTest
@testable import Pool_Side

final class SwimabilityV2StructuralTests: XCTestCase {
    func testAssessmentDerivedGateCollectionsAndBlockingState() {
        let failed = SwimReadinessGateResult(
            identifier: .sanitizerAdequacy,
            state: .fail,
            reason: "Sanitizer gate failed.",
            blocksSwimming: true,
            requiresTesting: true
        )
        let unknown = SwimReadinessGateResult(
            identifier: .waterClarity,
            state: .unknown,
            reason: "Water clarity was not recorded.",
            blocksSwimming: true,
            requiresTesting: false
        )
        let passed = SwimReadinessGateResult(
            identifier: .pH,
            state: .pass,
            reason: "pH gate passed.",
            blocksSwimming: false,
            requiresTesting: false
        )

        let assessment = SwimabilityV2Assessment(
            state: .testBeforeSwimming,
            evidenceType: .observed,
            confidence: .low,
            gateResults: [failed, unknown, passed],
            invalidationReasons: ["conflicting recent readings"],
            testingRequired: true,
            summary: "Structural test assessment."
        )

        XCTAssertEqual(assessment.failedGates, [failed])
        XCTAssertEqual(assessment.unknownGates, [unknown])
        XCTAssertTrue(assessment.swimmingBlocked)
    }

    func testPlaceholderEngineReturnsExplicitUnimplementedAssessment() {
        let request = AIRecommendationRequest(
            currentTest: PoolTest(),
            recentHistory: [],
            poolConfig: PoolConfiguration()
        )

        let assessment = SwimabilityV2Engine().assess(request: request)

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(assessment.evidenceType, .unknown)
        XCTAssertEqual(assessment.confidence, .insufficient)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertTrue(assessment.summary.contains("not implemented yet"))
    }

    func testComparisonFormatterContainsCoreFields() {
        let failedGate = SwimReadinessGateResult(
            identifier: .combinedChlorine,
            state: .fail,
            reason: "Combined chlorine gate failed.",
            blocksSwimming: true,
            requiresTesting: true
        )
        let unknownGate = SwimReadinessGateResult(
            identifier: .productReentry,
            state: .unknown,
            reason: "Product label timing is unknown.",
            blocksSwimming: true,
            requiresTesting: false
        )
        let assessment = SwimabilityV2Assessment(
            state: .doNotSwim,
            evidenceType: .unknown,
            confidence: .insufficient,
            gateResults: [failedGate, unknownGate],
            invalidationReasons: [],
            testingRequired: true,
            summary: "Formatter test assessment."
        )
        let comparison = SwimabilityV2Comparison(
            existingStatus: "Needs Attention",
            existingScore: 62,
            v2Assessment: assessment,
            meaningfulDifferences: ["v2 blocks swimming"],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let output = comparison.developerDescription

        XCTAssertTrue(output.contains("Current status: Needs Attention"))
        XCTAssertTrue(output.contains("Current score: 62"))
        XCTAssertTrue(output.contains("V2 state: doNotSwim"))
        XCTAssertTrue(output.contains("V2 evidence type: unknown"))
        XCTAssertTrue(output.contains("V2 confidence: insufficient"))
        XCTAssertTrue(output.contains("Failed gates: combinedChlorine"))
        XCTAssertTrue(output.contains("Unknown gates: productReentry"))
        XCTAssertTrue(output.contains("Testing required: yes"))
        XCTAssertTrue(output.contains("Differences: v2 blocks swimming"))
    }
}
