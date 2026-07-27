import XCTest
@testable import Pool_Side

final class SwimabilityV2StructuralTests: XCTestCase {
    private let evaluationDate = Date(timeIntervalSince1970: 1_800_003_600)

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

    func testBalancedObservedPoolIsReadyToSwim() {
        let assessment = assess(test: makeReadyTest(freeChlorine: 5.0, totalChlorine: 5.0, cyanuricAcid: 60))

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .observed)
        XCTAssertEqual(assessment.confidence, .high)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .pass)
    }

    func testFCBelowCYAAdjustedMinimumFailsSanitizerGate() {
        let assessment = assess(test: makeReadyTest(freeChlorine: 4.0, totalChlorine: 4.0, cyanuricAcid: 60))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
    }

    func testFCBelowPreferredTargetButAboveMinimumDoesNotFailSwimability() {
        let assessment = assess(test: makeReadyTest(freeChlorine: 4.6, totalChlorine: 4.6, cyanuricAcid: 60))

        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .pass)
        XCTAssertEqual(assessment.state, .readyToSwim)
    }

    func testCloudyWaterBlocksObservedReadiness() {
        let assessment = assess(test: makeReadyTest(waterClarityAssessment: .cloudy))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .fail)
    }

    func testVisibleAlgaeBlocksObservedReadiness() {
        let assessment = assess(test: makeReadyTest(visibleAlgaeAssessment: .present))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .fail)
    }

    func testMultipleRecoverySignalsArePreservedAsFailedGates() {
        let assessment = assess(test: makeReadyTest(
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            cyanuricAcid: 60,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        ))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .fail)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .fail)
    }

    func testMissingClarityPreventsReadiness() {
        let assessment = assess(test: makeReadyTest(waterClarityAssessment: .notRecorded, visibleAlgaeAssessment: .absent))

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .unknown)
    }

    func testMissingAlgaeResponsePreventsReadiness() {
        let assessment = assess(test: makeReadyTest(waterClarityAssessment: .clear, visibleAlgaeAssessment: .notRecorded))

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .unknown)
    }

    func testCannotTellVisualResponsesRequireMoreInformation() {
        let assessment = assess(test: makeReadyTest(waterClarityAssessment: .cannotTell, visibleAlgaeAssessment: .cannotTell))

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .unknown)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .unknown)
    }

    func testMissingFCRequiresTestingBeforeSwimming() {
        let assessment = assess(test: makeReadyTest(freeChlorine: .nan, totalChlorine: 5.0))

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .unknown)
    }

    func testMissingPHRequiresTestingBeforeSwimming() {
        let assessment = assess(test: makeReadyTest(pH: .nan))

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
        XCTAssertEqual(gateState(.pH, in: assessment), .unknown)
    }

    func testPHOutsideReadinessRangeBlocksObservedReadiness() {
        let assessment = assess(test: makeReadyTest(pH: 8.1))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.pH, in: assessment), .fail)
    }

    func testMissingCYARequiresTestingBeforeSwimming() {
        let assessment = assess(test: makeReadyTest(cyanuricAcid: .nan))

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .unknown)
    }

    func testStaleTestDoesNotProduceReadyToSwim() {
        let staleDate = evaluationDate.addingTimeInterval(-9 * 60 * 60)
        let assessment = assess(test: makeReadyTest(date: staleDate))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.testFreshness, in: assessment), .fail)
        XCTAssertTrue(assessment.testingRequired)
    }

    func testPendingTreatmentPreventsReadyBecauseSwimBlockingClassificationIsUnknown() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Unknown Immediate Product",
            targetParameter: "unknownProduct",
            urgency: .immediate
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(gateState(.treatmentCompletion, in: assessment), .unknown)
        XCTAssertEqual(gateState(.circulation, in: assessment), .unknown)
        XCTAssertEqual(gateState(.productReentry, in: assessment), .unknown)
    }

    func testNoPendingTreatmentPassesTreatmentCompletionGate() {
        let assessment = assess(test: makeReadyTest())

        XCTAssertEqual(gateState(.treatmentCompletion, in: assessment), .pass)
    }

    func testLowConfidenceCanNeverReturnReadyToSwim() {
        let assessment = assess(test: makeReadyTest(testMethod: .testStrips))

        XCTAssertEqual(assessment.confidence, .low)
        XCTAssertNotEqual(assessment.state, .readyToSwim)
    }

    func testDogfoodTest5RecoveryScenarioIsDoNotSwim() {
        let assessment = assess(test: makeReadyTest(
            pH: 7.5,
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            cyanuricAcid: 60,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        ))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .fail)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .fail)
    }

    func testStableMaintenanceScenarioCanBeReadyDespitePoolCareImperfections() {
        let assessment = assess(test: makeReadyTest(
            pH: 7.6,
            freeChlorine: 5.0,
            totalChlorine: 5.0,
            totalAlkalinity: 170,
            calciumHardness: 330,
            cyanuricAcid: 60
        ))

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .pass)
        XCTAssertEqual(gateState(.pH, in: assessment), .pass)
    }

    func testOptionalMaintenanceChlorineNotCompletedDoesNotBlockReadyPool() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .optional
        ))

        let assessment = assess(test: test)
        let classification = assessment.treatmentAwareContext?.classifications.first

        XCTAssertEqual(classification?.category, .poolCare)
        XCTAssertEqual(classification?.completionState, .plannedTreatment)
        XCTAssertFalse(classification?.blocksCurrentSwimability ?? true)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .observed)
        XCTAssertEqual(assessment.predictionConfidence, .medium)
    }

    func testOptionalMaintenanceChlorineCompletedInsideWaitDoesNotBlockReadyPool() {
        let test = makeReadyTest()
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .optional,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-30 * 60),
            minutesBeforeNext: 60
        )
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = assessment.treatmentAwareContext?.classifications.first

        XCTAssertEqual(classification?.category, .poolCare)
        XCTAssertEqual(classification?.completionState, .noActiveTreatment)
        XCTAssertFalse(classification?.blocksCurrentSwimability ?? true)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .predicted)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
        XCTAssertFalse(assessment.swimmingBlocked)
    }

    func testRoutineChlorineCompletedWithElapsedWaitCanReturnPredictedReady() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .optional,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-2 * 60 * 60),
            minutesBeforeNext: 60
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .predicted)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
    }

    func testRecoveryChlorineNotCompletedWithHardBlockersRemainsDoNotSwim() {
        let test = makeReadyTest(
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        test.treatments.append(makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Recovery chlorine for algae.",
            targetParameter: "freeChlorine",
            urgency: .immediate
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(assessment.treatmentAwareContext?.verificationRequired, true)
    }

    func testRecoveryChlorineCompletedDoesNotBecomeReadyFromElapsedTimeAlone() {
        let test = makeReadyTest(
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        test.treatments.append(makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Recovery chlorine for algae.",
            targetParameter: "freeChlorine",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-2 * 60 * 60),
            minutesBeforeNext: 60
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertNotEqual(assessment.state, .readyToSwim)
    }

    func testAcidOnlyCompletedWithKnownActiveWaitPredictsReadyAroundTime() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            targetParameter: "pH",
            urgency: .recommended,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.2
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .expectedReadyAroundTime)
        XCTAssertEqual(assessment.earliestPredictedReadyTime, evaluationDate.addingTimeInterval(3 * 60 * 60))
    }

    func testAcidWithRequiredVerificationReturnsTestBeforeSwimming() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-5 * 60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.5
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
    }

    func testHighPHWithPlannedAcidTreatmentRemainsDoNotSwim() {
        let test = makeReadyTest(pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = assessment.treatmentAwareContext?.classifications.first

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.pH, in: assessment), .fail)
        XCTAssertEqual(classification?.completionState, .plannedTreatment)
    }

    func testHighPHAcidCompletedInsideWaitRemainsDoNotSwimAndWaiting() {
        let test = makeReadyTest(pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = assessment.treatmentAwareContext?.classifications.first

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.pH, in: assessment), .fail)
        XCTAssertEqual(classification?.completionState, .completedWaiting)
        XCTAssertEqual(gateState(.productReentry, in: assessment), .fail)
    }

    func testHighPHAcidWaitExpiredRequiresPostTreatmentPHVerification() {
        let test = makeReadyTest(pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-5 * 60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = assessment.treatmentAwareContext?.classifications.first

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
        XCTAssertEqual(gateState(.pH, in: assessment), .fail)
        XCTAssertEqual(classification?.completionState, .completedVerificationRequired)
        XCTAssertTrue(classification?.verificationRequiredBeforeSwimming ?? false)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
    }

    @MainActor
    func testJumpAheadBeyondHighPHAcidWaitRequiresPostTreatmentPHVerification() throws {
        let actualDate = evaluationDate
        let test = makeReadyTest(date: actualDate.addingTimeInterval(-60 * 60), pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: actualDate.addingTimeInterval(-10 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let comparison = try XCTUnwrap(PoolViewModel().runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: [],
            offset: .fourHours,
            actualDate: actualDate
        ))

        XCTAssertEqual(comparison.v2Assessment.state, .testBeforeSwimming)
        XCTAssertTrue(comparison.v2Assessment.testingRequired)
        XCTAssertEqual(comparison.v2Assessment.treatmentAwareContext?.classifications.first?.completionState, .completedVerificationRequired)
        XCTAssertNotEqual(comparison.v2Assessment.state, .readyToSwim)
    }

    func testNewPostTreatmentTestWithSafePHCanBeReadyToSwim() {
        let prior = makeReadyTest(date: evaluationDate.addingTimeInterval(-6 * 60 * 60), pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-5 * 60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = prior
        prior.treatments.append(treatment)
        let current = makeReadyTest(date: evaluationDate.addingTimeInterval(-30 * 60), pH: 7.5, totalAlkalinity: 120)

        let assessment = SwimabilityV2Engine().assess(
            request: AIRecommendationRequest(
                currentTest: current,
                recentHistory: [prior],
                poolConfig: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, testMethod: current.testMethod)
            ),
            evaluationDate: evaluationDate
        )

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(gateState(.pH, in: assessment), .pass)
    }

    func testNewPostTreatmentTestWithUnsafePHIsNotReadyToSwim() {
        let prior = makeReadyTest(date: evaluationDate.addingTimeInterval(-6 * 60 * 60), pH: 8.0, totalAlkalinity: 140)
        let treatment = makeTreatment(
            chemicalName: "Muriatic Acid 31%",
            amount: 2,
            unit: "gal",
            targetParameter: "pH",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-5 * 60 * 60),
            minutesBeforeNext: 240,
            expectedDelta: -0.4
        )
        treatment.poolTest = prior
        prior.treatments.append(treatment)
        let current = makeReadyTest(date: evaluationDate.addingTimeInterval(-30 * 60), pH: 8.0, totalAlkalinity: 140)

        let assessment = SwimabilityV2Engine().assess(
            request: AIRecommendationRequest(
                currentTest: current,
                recentHistory: [prior],
                poolConfig: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, testMethod: current.testMethod)
            ),
            evaluationDate: evaluationDate
        )

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.pH, in: assessment), .fail)
    }

    func testElevatedCombinedChlorineChlorineCompletedInsideWaitRemainsDoNotSwim() throws {
        let test = makeReadyTest(freeChlorine: 6.0, totalChlorine: 7.0)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Treat elevated combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .recommended,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-30 * 60),
            minutesBeforeNext: 60,
            expectedDelta: -1.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
        XCTAssertEqual(classification.completionState, .completedWaiting)
        XCTAssertTrue(classification.verificationRequiredBeforeSwimming)
    }

    func testElevatedCombinedChlorineChlorineWaitExpiredRequiresPostTreatmentVerification() throws {
        let test = makeReadyTest(freeChlorine: 6.0, totalChlorine: 7.0)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Treat elevated combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .recommended,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-70 * 60),
            minutesBeforeNext: 60,
            expectedDelta: -1.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first)
        let treatmentContext = try XCTUnwrap(assessment.treatmentAwareContext)

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(assessment.testingRequired)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
        XCTAssertEqual(classification.completionState, .completedVerificationRequired)
        XCTAssertTrue(classification.verificationRequiredBeforeSwimming)
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.contains(.combinedChlorine))
        XCTAssertNil(assessment.earliestPredictedReadyTime)
    }

    @MainActor
    func testJumpAheadBeyondElevatedCombinedChlorineWaitRequiresPostTreatmentVerification() throws {
        let actualDate = evaluationDate
        let test = makeReadyTest(date: actualDate.addingTimeInterval(-60 * 60), freeChlorine: 6.0, totalChlorine: 7.0)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Treat elevated combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .recommended,
            isCompleted: true,
            completedAt: actualDate.addingTimeInterval(-10 * 60),
            minutesBeforeNext: 60,
            expectedDelta: -1.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let comparison = try XCTUnwrap(PoolViewModel().runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: [],
            offset: .oneHour,
            actualDate: actualDate
        ))

        XCTAssertEqual(comparison.v2Assessment.state, .testBeforeSwimming)
        XCTAssertTrue(comparison.v2Assessment.testingRequired)
        XCTAssertEqual(comparison.v2Assessment.treatmentAwareContext?.classifications.first?.completionState, .completedVerificationRequired)
        XCTAssertNotEqual(comparison.v2Assessment.state, .readyToSwim)
    }

    func testNewPostTreatmentTestWithSafeCombinedChlorineCanBeReadyToSwim() {
        let assessment = assess(test: makeReadyTest(freeChlorine: 6.0, totalChlorine: 6.5))

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .pass)
    }

    func testNewPostTreatmentTestWithUnsafeCombinedChlorineIsDoNotSwim() {
        let assessment = assess(test: makeReadyTest(freeChlorine: 6.0, totalChlorine: 7.0))

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
    }

    func testLowFCAndElevatedCombinedChlorineWaitExpiredRequireTestingForBothGates() throws {
        let test = makeReadyTest(freeChlorine: 1.0, totalChlorine: 2.0)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Treat low sanitizer and elevated combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .recommended,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-70 * 60),
            minutesBeforeNext: 60,
            expectedDelta: 4.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let treatmentContext = try XCTUnwrap(assessment.treatmentAwareContext)

        XCTAssertEqual(assessment.state, .testBeforeSwimming)
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.contains(.sanitizerAdequacy))
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.contains(.combinedChlorine))
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
    }

    func testRecoveryVisualBlockersRemainDoNotSwimAfterChlorineWaitExpired() throws {
        let test = makeReadyTest(
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Recovery chlorine for algae, cloudy water, and combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .immediate,
            isCompleted: true,
            completedAt: evaluationDate.addingTimeInterval(-70 * 60),
            minutesBeforeNext: 60,
            expectedDelta: 4.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let treatmentContext = try XCTUnwrap(assessment.treatmentAwareContext)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.contains(.sanitizerAdequacy))
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.contains(.combinedChlorine))
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .fail)
        XCTAssertEqual(gateState(.visibleAlgae, in: assessment), .fail)
    }

    func testSkippedElevatedCombinedChlorineTreatmentDoesNotClearCCBlocker() throws {
        let test = makeReadyTest(freeChlorine: 6.0, totalChlorine: 7.0)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Treat elevated combined chlorine.",
            targetParameter: "freeChlorine",
            urgency: .recommended,
            isSkipped: true,
            minutesBeforeNext: 60,
            expectedDelta: -1.0
        )
        treatment.poolTest = test
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let treatmentContext = try XCTUnwrap(assessment.treatmentAwareContext)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.combinedChlorine, in: assessment), .fail)
        XCTAssertTrue(treatmentContext.pendingVerificationGateIdentifiers.isEmpty)
        XCTAssertEqual(treatmentContext.classifications.first?.completionState, .skippedTreatment)
    }

    func testPoolCareOnlyPendingTreatmentDoesNotAutomaticallyBlockSwimming() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Calcium Chloride",
            targetParameter: "calciumHardness",
            urgency: .recommended
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.treatmentAwareContext?.classifications.first?.category, .poolCare)
    }

    func testBakingSodaRemainsPoolCareAndDoesNotBlockReadiness() {
        let test = makeReadyTest(totalAlkalinity: 50)
        test.treatments.append(makeTreatment(
            chemicalName: "Baking Soda (Sodium Bicarbonate)",
            amount: 13.7,
            unit: "lbs",
            targetParameter: "totalAlkalinity",
            urgency: .recommended
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertFalse(assessment.swimmingBlocked)
        XCTAssertEqual(assessment.treatmentAwareContext?.classifications.first?.category, .poolCare)
    }

    func testTC7StabilizerRemainsPoolCareAndReadyToSwim() {
        let test = makeReadyTest(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 20
        )
        test.treatments.append(makeTreatment(
            chemicalName: "Cyanuric Acid (Granular)",
            amount: 5.3,
            unit: "lbs",
            targetParameter: "cyanuricAcid",
            urgency: .optional
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertFalse(assessment.swimmingBlocked)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertEqual(assessment.treatmentAwareContext?.classifications.first?.category, .poolCare)
    }

    func testKeepFilteringCloudyWaterDoesNotCreateChemicalBlocker() {
        let test = makeReadyTest(waterClarityAssessment: .cloudy)
        test.treatments.append(makeTreatment(
            chemicalName: "Keep Filtering Cloudy Water",
            amount: 0,
            unit: "",
            targetParameter: "visualIndicators",
            urgency: .recommended
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.waterClarity, in: assessment), .fail)
        XCTAssertEqual(assessment.treatmentAwareContext?.classifications.first?.category, .nonChemicalAction)
    }

    func testSkippedSwimBlockingTreatmentDoesNotResolveUnderlyingProblem() {
        let test = makeReadyTest(freeChlorine: 1.0, totalChlorine: 1.0)
        test.treatments.append(makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .immediate,
            isSkipped: true
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
    }

    func testCompletedTreatmentMissingTimestampDoesNotProducePreciseReadyTime() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Muriatic Acid (31.45%)",
            targetParameter: "pH",
            urgency: .recommended,
            isCompleted: true,
            completedAt: nil,
            minutesBeforeNext: 240,
            expectedDelta: -0.3
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .expectedReadyAfterTreatment)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
    }

    func testActiveTreatmentWithUnknownReentryRequirementDoesNotPredictReadiness() {
        let test = makeReadyTest()
        test.treatments.append(makeTreatment(
            chemicalName: "Unknown Immediate Product",
            targetParameter: "unknownProduct",
            urgency: .immediate
        ))

        let assessment = assess(test: test)

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(assessment.predictionConfidence, .low)
        XCTAssertEqual(gateState(.productReentry, in: assessment), .unknown)
    }

    func testCleanTC1GeneratedRoutineChlorineIsVisibleToTreatmentAwareV2() async throws {
        let test = makeCleanTC1Test()
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { treatment in
            if !test.treatments.contains(where: { $0.id == treatment.id }) {
                test.treatments.append(treatment)
            }
        }

        let chlorineTreatments = generatedTreatments.filter { $0.targetParameter == "freeChlorine" && !$0.isWatchlistItem }
        let chlorine = try XCTUnwrap(chlorineTreatments.first)
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
        let treatmentContext = try XCTUnwrap(assessment.treatmentAwareContext)
        let classification = try XCTUnwrap(treatmentContext.classifications.first { $0.treatmentID == chlorine.id })

        XCTAssertEqual(chlorineTreatments.count, 1)
        XCTAssertEqual(chlorine.chemicalName, "Liquid Chlorine 12.5%")
        XCTAssertEqual(chlorine.amount, 0.75, accuracy: 0.001)
        XCTAssertEqual(chlorine.urgency, .optional)
        XCTAssertEqual(chlorine.minutesBeforeNext, 60)
        XCTAssertEqual(TreatmentTimingGuidance.cardTip(for: chlorine), "Swim after ~1 hr")
        XCTAssertEqual(treatmentContext.activeTreatmentCount, 1)
        XCTAssertEqual(classification.category, .poolCare)
        XCTAssertEqual(classification.completionState, .plannedTreatment)
        XCTAssertFalse(classification.blocksCurrentSwimability)
        XCTAssertFalse(classification.verificationRequiredBeforeSwimming)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .observed)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertFalse(assessment.swimmingBlocked)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .pass)
        XCTAssertEqual(gateState(.treatmentCompletion, in: assessment), .pass)
    }

    func testCleanTC1SkippedOptionalMaintenanceChlorineRemainsReadyToSwim() async throws {
        let test = makeCleanTC1Test()
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { test.treatments.append($0) }
        let chlorine = try XCTUnwrap(generatedTreatments.first { $0.targetParameter == "freeChlorine" && !$0.isWatchlistItem })

        chlorine.isSkipped = true
        chlorine.skippedAt = evaluationDate
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first { $0.treatmentID == chlorine.id })

        XCTAssertEqual(classification.category, .poolCare)
        XCTAssertEqual(classification.completionState, .skippedTreatment)
        XCTAssertFalse(classification.blocksCurrentSwimability)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertFalse(assessment.swimmingBlocked)
        XCTAssertFalse(assessment.testingRequired)
    }

    func testBelowReadinessMinimumChlorineTreatmentRemainsSwimBlocking() async throws {
        let test = makeCleanTC1Test()
        test.freeChlorine = 4.0
        test.totalChlorine = 4.0
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { test.treatments.append($0) }
        let chlorine = try XCTUnwrap(generatedTreatments.first { $0.targetParameter == "freeChlorine" && !$0.isWatchlistItem })

        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first { $0.treatmentID == chlorine.id })

        XCTAssertEqual(chlorine.urgency, .recommended)
        XCTAssertEqual(TreatmentTimingGuidance.cardTip(
            for: chlorine,
            requiresVerificationBeforeSwimming: TreatmentTimingGuidance.requiresVerificationBeforeSwimming(for: chlorine)
        ), "Test before swimming")
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .fail)
        XCTAssertEqual(classification.category, .swimBlocking)
        XCTAssertEqual(classification.completionState, .plannedTreatment)
        XCTAssertTrue(classification.blocksCurrentSwimability)
        XCTAssertEqual(gateState(.treatmentCompletion, in: assessment), .fail)
        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertTrue(assessment.swimmingBlocked)
    }

    func testRecoveryChlorineClassificationRemainsSwimBlocking() throws {
        let test = makeReadyTest(
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Recovery chlorine for algae and cloudy water.",
            targetParameter: "freeChlorine",
            urgency: .immediate,
            minutesBeforeNext: 60
        )
        test.treatments.append(treatment)

        let assessment = assess(test: test)
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first { $0.treatmentID == treatment.id })

        XCTAssertEqual(classification.category, .swimBlocking)
        XCTAssertTrue(classification.blocksCurrentSwimability)
        XCTAssertTrue(classification.verificationRequiredBeforeSwimming)
        XCTAssertEqual(assessment.state, .doNotSwim)
        XCTAssertTrue(assessment.swimmingBlocked)
    }

    func testPreferredTargetChlorineDoesNotGenerateMaintenanceTopOff() async throws {
        let test = makeCleanTC1Test()
        test.freeChlorine = 6.5
        test.totalChlorine = 6.5
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { test.treatments.append($0) }

        XCTAssertFalse(generatedTreatments.contains { $0.targetParameter == "freeChlorine" && !$0.isWatchlistItem })
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
        XCTAssertEqual(gateState(.sanitizerAdequacy, in: assessment), .pass)
        XCTAssertEqual(gateState(.treatmentCompletion, in: assessment), .pass)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertFalse(assessment.swimmingBlocked)
    }

    func testCleanTC1FinalComparisonReflectsGeneratedTreatmentsOnce() async throws {
        let test = makeCleanTC1Test()
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { treatment in
            if !test.treatments.contains(where: { $0.id == treatment.id }) {
                test.treatments.append(treatment)
            }
        }

        let comparison = PoolViewModel().swimabilityV2Comparison(
            for: request,
            context: "Normal Generation",
            generatedAt: evaluationDate
        )
        let output = comparison.developerDescription

        XCTAssertEqual(output.components(separatedBy: "===== POOL SIDE V2 SWIMABILITY =====").count - 1, 1)
        XCTAssertEqual(output.components(separatedBy: "===== END POOL SIDE V2 SWIMABILITY =====").count - 1, 1)
        XCTAssertTrue(output.contains("Active Treatments: 1"))
        XCTAssertTrue(output.contains("Treatment-Aware Swimability: Ready to Swim"))
        XCTAssertTrue(output.contains("Prediction Confidence: Medium"))
        XCTAssertTrue(output.contains("Active Treatment Count: 1"))
        XCTAssertTrue(output.contains("Liquid Chlorine 12.5%=poolCare"))
        XCTAssertTrue(output.contains("Liquid Chlorine 12.5%=plannedTreatment"))
        XCTAssertTrue(output.contains("Verification Required: No"))
        XCTAssertTrue(output.contains("Earliest Predicted Ready Time: None"))
        XCTAssertFalse(output.contains("Treatment-Aware Swimability: Expected Ready After Treatment"))
        XCTAssertFalse(output.contains("V2 Swimability: Test Before Swimming"))
        XCTAssertEqual(generatedTreatments.filter { !$0.isWatchlistItem }.count, 1)
    }

    @MainActor
    func testTC1RoutineChlorineCompletionHookReportsCompletedWaitingPrediction() async throws {
        let test = makeCleanTC1Test()
        let config = makeTC1Config()
        let request = AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        let response = try await RuleBasedService().generateRecommendations(for: request)
        let generatedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        generatedTreatments.forEach { test.treatments.append($0) }
        let chlorine = try XCTUnwrap(generatedTreatments.first { $0.targetParameter == "freeChlorine" && !$0.isWatchlistItem })
        let completedAt = evaluationDate.addingTimeInterval(-10 * 60)
        let viewModel = PoolViewModel()
        viewModel.saveConfig(config)

        viewModel.completeTreatment(chlorine)
        chlorine.completedAt = completedAt
        let comparison = try XCTUnwrap(viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
            for: test,
            recentTests: [],
            context: "Treatment Completed",
            generatedAt: evaluationDate
        ))
        let assessment = comparison.v2Assessment
        let classification = try XCTUnwrap(assessment.treatmentAwareContext?.classifications.first { $0.treatmentID == chlorine.id })
        let output = comparison.developerDescription

        XCTAssertTrue(chlorine.isCompleted)
        XCTAssertEqual(classification.completionState, .noActiveTreatment)
        XCTAssertNil(classification.readyAt)
        XCTAssertEqual(assessment.state, .readyToSwim)
        XCTAssertEqual(assessment.evidenceType, .predicted)
        XCTAssertEqual(assessment.predictionConfidence, .medium)
        XCTAssertNil(assessment.earliestPredictedReadyTime)
        XCTAssertFalse(classification.verificationRequiredBeforeSwimming)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertFalse(assessment.swimmingBlocked)
        XCTAssertEqual(gateState(.circulation, in: assessment), .notApplicable)
        XCTAssertTrue(output.contains("Evaluation Context: Treatment Completed"))
        XCTAssertTrue(output.contains("Completed Treatments: 1"))
        XCTAssertTrue(output.contains("Treatment-Aware Swimability: Ready to Swim"))
        XCTAssertTrue(output.contains("Liquid Chlorine 12.5%=noActiveTreatment"))
        XCTAssertTrue(output.contains("Verification Required: No"))
        XCTAssertFalse(output.contains("Treatment-Aware Swimability: Expected Ready Around Time"))
        XCTAssertFalse(output.contains("V2 Swimability: Test Before Swimming"))
        XCTAssertEqual(test.treatments.filter { !$0.isWatchlistItem }.count, 1)
    }

    @MainActor
    func testTreatmentStateChangeHookReflectsSkipAndRestoreTransitionsWithoutDuplicatingTreatments() async throws {
        let test = makeReadyTest()
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .optional,
            minutesBeforeNext: 60
        )
        test.treatments.append(treatment)
        let viewModel = PoolViewModel()

        viewModel.skipTreatment(treatment)
        let skippedComparison = try XCTUnwrap(viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
            for: test,
            recentTests: [],
            context: "Treatment Skipped",
            generatedAt: evaluationDate
        ))
        let skippedClassification = try XCTUnwrap(skippedComparison.v2Assessment.treatmentAwareContext?.classifications.first)

        XCTAssertEqual(skippedClassification.completionState, .skippedTreatment)
        XCTAssertTrue(treatment.isSkipped)
        XCTAssertFalse(treatment.isCompleted)
        XCTAssertTrue(skippedComparison.developerDescription.contains("Evaluation Context: Treatment Skipped"))
        XCTAssertEqual(test.treatments.filter { !$0.isWatchlistItem }.count, 1)

        viewModel.restoreTreatment(treatment)
        let restoredComparison = try XCTUnwrap(viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
            for: test,
            recentTests: [],
            context: "Treatment Restored",
            generatedAt: evaluationDate
        ))
        let restoredClassification = try XCTUnwrap(restoredComparison.v2Assessment.treatmentAwareContext?.classifications.first)

        XCTAssertEqual(restoredClassification.completionState, .plannedTreatment)
        XCTAssertEqual(restoredClassification.category, .poolCare)
        XCTAssertFalse(restoredClassification.blocksCurrentSwimability)
        XCTAssertFalse(treatment.isSkipped)
        XCTAssertTrue(restoredComparison.developerDescription.contains("Evaluation Context: Treatment Restored"))
        XCTAssertEqual(restoredComparison.v2Assessment.state, .readyToSwim)
        XCTAssertFalse(restoredComparison.v2Assessment.swimmingBlocked)
        XCTAssertEqual(test.treatments.filter { !$0.isWatchlistItem }.count, 1)
    }

    @MainActor
    func testJumpAheadUsesSimulatedEvaluationDateAndDoesNotMutateTreatmentData() throws {
        let actualDate = evaluationDate
        let test = makeReadyTest(date: actualDate.addingTimeInterval(-60 * 60))
        let completedAt = actualDate.addingTimeInterval(-10 * 60)
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            targetParameter: "freeChlorine",
            urgency: .optional,
            isCompleted: true,
            completedAt: completedAt,
            minutesBeforeNext: 60
        )
        test.treatments.append(treatment)
        let originalTestDate = test.date
        let originalTreatmentCount = test.treatments.count
        let viewModel = PoolViewModel()

        let comparison = try XCTUnwrap(viewModel.runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: [],
            offset: .oneHour,
            actualDate: actualDate
        ))
        let output = comparison.developerDescription

        XCTAssertEqual(comparison.generatedAt, actualDate.addingTimeInterval(60 * 60))
        XCTAssertEqual(comparison.actualEvaluationTimestamp, actualDate)
        XCTAssertEqual(comparison.v2Assessment.state, .readyToSwim)
        XCTAssertEqual(comparison.v2Assessment.evidenceType, .predicted)
        XCTAssertNil(comparison.v2Assessment.earliestPredictedReadyTime)
        XCTAssertEqual(test.date, originalTestDate)
        XCTAssertEqual(treatment.completedAt, completedAt)
        XCTAssertTrue(treatment.isCompleted)
        XCTAssertFalse(treatment.isSkipped)
        XCTAssertEqual(test.treatments.count, originalTreatmentCount)
        XCTAssertTrue(output.contains("Evaluation Context: Developer Jump Ahead +1 hr"))
        XCTAssertTrue(output.contains("Actual Evaluation Timestamp:"))
        XCTAssertTrue(output.contains("Simulated Evaluation Timestamp:"))
    }

    @MainActor
    func testJumpAheadDoesNotMakeRecoveryChlorineReadyFromElapsedTime() throws {
        let actualDate = evaluationDate
        let test = makeReadyTest(
            date: actualDate.addingTimeInterval(-60 * 60),
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        let treatment = makeTreatment(
            chemicalName: "Liquid Chlorine 12.5%",
            instructions: "Recovery chlorine for algae.",
            targetParameter: "freeChlorine",
            urgency: .immediate,
            isCompleted: true,
            completedAt: actualDate.addingTimeInterval(-2 * 60 * 60),
            minutesBeforeNext: 60
        )
        test.treatments.append(treatment)

        let comparison = try XCTUnwrap(PoolViewModel().runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: [],
            offset: .oneHour,
            actualDate: actualDate
        ))

        XCTAssertEqual(comparison.v2Assessment.state, .doNotSwim)
        XCTAssertEqual(gateState(.waterClarity, in: comparison.v2Assessment), .fail)
        XCTAssertEqual(gateState(.visibleAlgae, in: comparison.v2Assessment), .fail)
        XCTAssertNotEqual(comparison.v2Assessment.state, .readyToSwim)
    }

    @MainActor
    func testJumpAheadStillRespectsTestFreshnessPolicy() throws {
        let actualDate = evaluationDate
        let test = makeReadyTest(date: actualDate.addingTimeInterval(-7.5 * 60 * 60))

        let comparison = try XCTUnwrap(PoolViewModel().runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: [],
            offset: .oneHour,
            actualDate: actualDate
        ))

        XCTAssertEqual(comparison.generatedAt, actualDate.addingTimeInterval(60 * 60))
        XCTAssertEqual(gateState(.testFreshness, in: comparison.v2Assessment), .fail)
        XCTAssertNotEqual(comparison.v2Assessment.state, .readyToSwim)
    }

    func testJumpAheadOffsetsExposeExpectedDeveloperOptions() {
        XCTAssertEqual(TreatmentPlanDeveloperJumpAheadOffset.allCases.map(\.displayName), [
            "+15 min",
            "+30 min",
            "+1 hr",
            "+2 hr",
            "+4 hr",
            "+8 hr"
        ])
        XCTAssertEqual(TreatmentPlanDeveloperJumpAheadOffset.oneHour.timeInterval, 60 * 60)
    }

    func testComparisonFormatterContainsCopyableDiagnosticBlock() {
        let test = makeReadyTest(
            pH: 7.5,
            freeChlorine: 1.0,
            totalChlorine: 2.0,
            cyanuricAcid: 60,
            waterClarityAssessment: .cloudy,
            visibleAlgaeAssessment: .present
        )
        test.notes = "private dogfood note"
        let request = AIRecommendationRequest(
            currentTest: test,
            recentHistory: [],
            poolConfig: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, testMethod: test.testMethod)
        )
        let normalizedState = PoolStateNormalizer().normalize(request: request, evaluationDate: evaluationDate)
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
        let comparison = SwimabilityV2Comparison(
            existingStatus: "Needs Attention",
            existingScore: 62,
            v2Assessment: assessment,
            meaningfulDifferences: ["v2 blocks swimming"],
            generatedAt: evaluationDate,
            normalizedPoolState: normalizedState,
            evaluationContext: "Normal Generation"
        )
        let output = comparison.developerDescription

        XCTAssertTrue(output.contains("===== POOL SIDE V2 SWIMABILITY ====="))
        XCTAssertTrue(output.contains("===== END POOL SIDE V2 SWIMABILITY ====="))
        XCTAssertTrue(output.contains("Evaluation Context: Normal Generation"))
        XCTAssertTrue(output.contains("Current Test Timestamp:"))
        XCTAssertTrue(output.contains("Current Test ID:"))
        XCTAssertTrue(output.contains("V1 Score: 62"))
        XCTAssertTrue(output.contains("V1 Status: Needs Attention"))
        XCTAssertTrue(output.contains("V2 Swimability: Do Not Swim"))
        XCTAssertTrue(output.contains("Evidence Type: Observed"))
        XCTAssertTrue(output.contains("Confidence: High"))
        XCTAssertTrue(output.contains("Testing Required: Yes"))
        XCTAssertTrue(output.contains("Swimming Blocked: Yes"))
        XCTAssertTrue(output.contains("Chemistry: FC 1 | CC 1 | TC 2 | pH 7.5 | TA 100 | CH 330 | CYA 60"))
        XCTAssertTrue(output.contains("Water Clarity: cloudy"))
        XCTAssertTrue(output.contains("Visible Algae: present"))
        XCTAssertTrue(output.contains("Recent Rain: unknown"))
        XCTAssertTrue(output.contains("Active Treatments: 0"))
        XCTAssertTrue(output.contains("Sanitizer Adequacy: FAIL"))
        XCTAssertTrue(output.contains("pH: PASS"))
        XCTAssertTrue(output.contains("Combined Chlorine: FAIL"))
        XCTAssertTrue(output.contains("Water Clarity: FAIL"))
        XCTAssertTrue(output.contains("Visible Algae: FAIL"))
        XCTAssertTrue(output.contains("Test Freshness: PASS"))
        XCTAssertTrue(output.contains("Treatment Completion: PASS"))
        XCTAssertTrue(output.contains("Circulation: N/A"))
        XCTAssertTrue(output.contains("Product Re-entry: N/A"))
        XCTAssertTrue(output.contains("Failed Gates: Sanitizer Adequacy, Combined Chlorine, Water Clarity, Visible Algae"))
        XCTAssertTrue(output.contains("Unknown Gates: None"))
        XCTAssertTrue(output.contains("Meaningful V1/V2 Differences: v2 blocks swimming"))
        XCTAssertFalse(output.contains("private dogfood note"))
    }

    func testDebugFeatureFlagIsEnabledForDebugBuildsAndDisabledOtherwise() {
        #if DEBUG
        XCTAssertTrue(RecommendationV2FeatureFlags.swimabilityV2ComparisonEnabled)
        #else
        XCTAssertFalse(RecommendationV2FeatureFlags.swimabilityV2ComparisonEnabled)
        #endif
    }

    private func assess(test: PoolTest) -> SwimabilityV2Assessment {
        SwimabilityV2Engine().assess(
            request: AIRecommendationRequest(
                currentTest: test,
                recentHistory: [],
                poolConfig: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, testMethod: test.testMethod)
            ),
            evaluationDate: evaluationDate
        )
    }

    private func gateState(
        _ identifier: SwimReadinessGateIdentifier,
        in assessment: SwimabilityV2Assessment
    ) -> SwimReadinessGateState? {
        assessment.gateResults.first { $0.identifier == identifier }?.state
    }

    private func makeReadyTest(
        date: Date? = nil,
        pH: Double = 7.5,
        freeChlorine: Double = 5.0,
        totalChlorine: Double = 5.0,
        totalAlkalinity: Double = 100,
        calciumHardness: Double = 330,
        cyanuricAcid: Double = 60,
        testMethod: TestMethod = .liquidDropKit,
        waterClarityAssessment: WaterClarityAssessment = .clear,
        visibleAlgaeAssessment: VisibleAlgaeAssessment = .absent
    ) -> PoolTest {
        PoolTest(
            date: date ?? evaluationDate.addingTimeInterval(-60 * 60),
            pH: pH,
            freeChlorine: freeChlorine,
            totalChlorine: totalChlorine,
            totalAlkalinity: totalAlkalinity,
            calciumHardness: calciumHardness,
            cyanuricAcid: cyanuricAcid,
            testMethod: testMethod,
            poolConditions: PoolConditions(),
            visualIndicators: [],
            waterClarityAssessment: waterClarityAssessment,
            visibleAlgaeAssessment: visibleAlgaeAssessment
        )
    }

    private func makeCleanTC1Test() -> PoolTest {
        PoolTest(
            date: evaluationDate.addingTimeInterval(-60 * 60),
            pH: 7.5,
            freeChlorine: 4.5,
            totalChlorine: 4.5,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60,
            testMethod: .liquidDropKit,
            poolConditions: PoolConditions(
                swimmingLoad: .none,
                petSwimmingLoad: .none,
                rainLoad: .none,
                coverOpenTime: .sixToEighteenHours,
                organicDebrisLoad: .low,
                skimmedDebris: .yes,
                backwashedFilter: .no,
                waterAdded: .none,
                cleaningActivity: .oneCycle,
                poolBrushed: .no
            ),
            visualIndicators: [],
            waterClarityAssessment: .clear,
            visibleAlgaeAssessment: .absent
        )
    }

    private func makeTC1Config() -> PoolConfiguration {
        PoolConfiguration(
            volumeGallons: 32_583,
            surfaceType: .plaster,
            testMethod: .liquidDropKit,
            isSaltwater: false,
            chlorinePreference: .liquidChlorine12_5
        )
    }

    private func makeTreatment(
        chemicalName: String = "Liquid Chlorine 12.5%",
        amount: Double = 1,
        unit: String = "gal",
        instructions: String = "Add treatment.",
        targetParameter: String = "freeChlorine",
        urgency: TreatmentUrgency = .recommended,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        isSkipped: Bool = false,
        minutesBeforeNext: Int = 0,
        expectedDelta: Double = 0
    ) -> Treatment {
        Treatment(
            chemicalName: chemicalName,
            actionDescription: "Test treatment",
            amount: amount,
            unit: unit,
            instructions: instructions,
            urgency: urgency,
            isCompleted: isCompleted,
            completedAt: completedAt,
            isSkipped: isSkipped,
            targetParameter: targetParameter,
            minutesBeforeNext: minutesBeforeNext,
            expectedDelta: expectedDelta
        )
    }
}
