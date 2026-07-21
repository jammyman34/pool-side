import XCTest
@testable import Pool_Side

final class NormalizedPoolStateTests: XCTestCase {
    private let evaluationDate = Date(timeIntervalSince1970: 1_800_003_600)

    func testCombinedChlorineIsDerivedFromFreeAndTotalChlorine() {
        let state = normalize(test: makeTest(freeChlorine: 2.0, totalChlorine: 2.4))

        XCTAssertEqual(try XCTUnwrap(state.combinedChlorine), 0.4, accuracy: 0.001)
        XCTAssertFalse(state.internallyConflictingReadingIdentifiers.contains("combinedChlorine"))
    }

    func testDirectlyRecordedCombinedChlorineIsPreservedWhenTaylorInputsExist() {
        let test = makeTest(freeChlorine: 2.0, totalChlorine: 2.0, testMethod: .liquidDropKit)
        test.taylorSampleSize = .tenMl
        test.taylorCCDrops = 3

        let state = normalize(test: test)

        XCTAssertEqual(try XCTUnwrap(state.combinedChlorine), 1.5, accuracy: 0.001)
    }

    func testCombinedChlorineIsUnavailableWhenInputsAreInsufficient() {
        let state = normalize(test: makeTest(freeChlorine: .nan, totalChlorine: 2.0))

        XCTAssertNil(state.combinedChlorine)
        XCTAssertTrue(state.unavailableReadingIdentifiers.contains("freeChlorine"))
        XCTAssertTrue(state.unavailableReadingIdentifiers.contains("combinedChlorine"))
    }

    func testTotalChlorineBelowFreeChlorineIsRecordedAsConflict() {
        let state = normalize(test: makeTest(freeChlorine: 3.0, totalChlorine: 2.8))

        XCTAssertNil(state.combinedChlorine)
        XCTAssertTrue(state.internallyConflictingReadingIdentifiers.contains("combinedChlorine"))
    }

    func testExplicitVisualConditionMappings() {
        XCTAssertEqual(normalize(test: makeTest(waterClarityAssessment: .clear)).normalizedWaterClarity, .clear)
        XCTAssertEqual(normalize(test: makeTest(waterClarityAssessment: .cloudy)).normalizedWaterClarity, .cloudy)
        XCTAssertEqual(normalize(test: makeTest(waterClarityAssessment: .cannotTell)).normalizedWaterClarity, .cannotTell)
        XCTAssertEqual(normalize(test: makeTest(waterClarityAssessment: .notRecorded, visualIndicators: [])).normalizedWaterClarity, .notRecorded)

        XCTAssertEqual(normalize(test: makeTest(visibleAlgaeAssessment: .absent)).normalizedVisibleAlgae, .absent)
        XCTAssertEqual(normalize(test: makeTest(visibleAlgaeAssessment: .present)).normalizedVisibleAlgae, .present)
        XCTAssertEqual(normalize(test: makeTest(visibleAlgaeAssessment: .cannotTell)).normalizedVisibleAlgae, .cannotTell)
        XCTAssertEqual(normalize(test: makeTest(visibleAlgaeAssessment: .notRecorded, visualIndicators: [])).normalizedVisibleAlgae, .notRecorded)
    }

    func testLegacyVisualIndicatorsBackfillOnlyPositiveEvidence() {
        let clear = normalize(test: makeTest(visualIndicators: [VisualIndicator.crystalClear.rawValue]))
        XCTAssertEqual(clear.normalizedWaterClarity, .clear)
        XCTAssertEqual(clear.normalizedVisibleAlgae, .notRecorded)
        XCTAssertFalse(clear.visualConditionsComplete)

        let algae = normalize(test: makeTest(visualIndicators: [VisualIndicator.algaeSpots.rawValue]))
        XCTAssertEqual(algae.normalizedVisibleAlgae, .present)

        let green = normalize(test: makeTest(visualIndicators: [VisualIndicator.greenWater.rawValue]))
        XCTAssertEqual(green.normalizedWaterClarity, .cloudy)
        XCTAssertEqual(green.normalizedVisibleAlgae, .present)
        XCTAssertTrue(green.visualConditionsComplete)
    }

    func testExplicitVisualAssessmentTakesPrecedenceOverLegacyIndicators() {
        let explicit = normalize(test: makeTest(
            waterClarityAssessment: .clear,
            visibleAlgaeAssessment: .absent,
            visualIndicators: [VisualIndicator.greenWater.rawValue, VisualIndicator.algaeSpots.rawValue]
        ))

        XCTAssertEqual(explicit.normalizedWaterClarity, .clear)
        XCTAssertEqual(explicit.normalizedVisibleAlgae, .absent)
        XCTAssertTrue(explicit.visualConditionsComplete)
    }

    func testMissingPoolEventDataRemainsNotRecorded() {
        let state = normalize(test: makeTest(poolConditions: nil))

        XCTAssertEqual(state.recentRain, .notRecorded)
        XCTAssertEqual(state.recentRefill, .notRecorded)
        XCTAssertEqual(state.recentBackwash, .notRecorded)
        XCTAssertEqual(state.recentHeavyBatherLoad, .notRecorded)
        XCTAssertEqual(state.recentContaminationConcern, .notRecorded)
        XCTAssertEqual(state.circulationStatus, .notRecorded)
        XCTAssertNil(state.knownPumpRunningSince)
    }

    func testReportedPoolEventsPreservePresentAbsentAndUnknown() {
        let conditions = PoolConditions(
            swimmingLoad: .high,
            petSwimmingLoad: .none,
            rainLoad: .none,
            backwashedFilter: .yes,
            waterAdded: .moreThanTwoInches
        )
        let state = normalize(test: makeTest(poolConditions: conditions))

        XCTAssertEqual(state.recentRain, .reportedAbsent)
        XCTAssertEqual(state.recentRefill, .reportedPresent)
        XCTAssertEqual(state.recentBackwash, .reportedPresent)
        XCTAssertEqual(state.recentHeavyBatherLoad, .reportedPresent)
    }

    func testTestAgeUsesFixedEvaluationDateAndNeverGoesNegative() {
        let past = normalize(test: makeTest(date: evaluationDate.addingTimeInterval(-90 * 60)))
        let future = normalize(test: makeTest(date: evaluationDate.addingTimeInterval(90 * 60)))

        XCTAssertEqual(past.ageInMinutes, 90)
        XCTAssertEqual(future.ageInMinutes, 0)
    }

    func testUnavailableReadingIdentification() {
        let state = normalize(test: makeTest(pH: .nan, saltLevel: nil, waterTemperature: nil))

        XCTAssertTrue(state.unavailableReadingIdentifiers.contains("pH"))
        XCTAssertTrue(state.unavailableReadingIdentifiers.contains("saltLevel"))
        XCTAssertTrue(state.unavailableReadingIdentifiers.contains("waterTemperature"))
    }

    func testTreatmentStateCountsAndMostRecentCompletion() {
        let test = makeTest()
        let completed = makeTreatment(isCompleted: true, completedAt: evaluationDate.addingTimeInterval(-1800))
        let skipped = makeTreatment(isSkipped: true)
        let active = makeTreatment()
        test.treatments.append(contentsOf: [completed, skipped, active])

        let state = normalize(test: test)

        XCTAssertEqual(state.activeTreatmentCount, 1)
        XCTAssertEqual(state.completedTreatmentCount, 1)
        XCTAssertEqual(state.skippedTreatmentCount, 1)
        XCTAssertEqual(state.mostRecentTreatmentCompletionDate, completed.completedAt)
    }

    func testRecentHistoryExcludesCurrentTestAndUsesDateOrdering() {
        let current = makeTest(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: evaluationDate)
        let older = makeTest(date: evaluationDate.addingTimeInterval(-86_400 * 3))
        let latestPrevious = makeTest(date: evaluationDate.addingTimeInterval(-86_400))
        let duplicateCurrent = makeTest(id: current.id, date: evaluationDate)
        let future = makeTest(date: evaluationDate.addingTimeInterval(86_400))

        let state = normalize(test: current, recentHistory: [older, future, duplicateCurrent, latestPrevious])

        XCTAssertEqual(state.recentTestCount, 2)
        XCTAssertEqual(state.latestPreviousTestDate, latestPrevious.date)
    }

    func testRecentTreatmentHistoryIsSummarized() {
        let historical = makeTest(date: evaluationDate.addingTimeInterval(-86_400))
        historical.treatments.append(makeTreatment(isCompleted: true, completedAt: evaluationDate.addingTimeInterval(-80_000)))

        let state = normalize(test: makeTest(), recentHistory: [historical])

        XCTAssertTrue(state.hasRecentTreatmentHistory)
        XCTAssertFalse(state.hasConflictingRecentTest)
    }

    func testNormalizerDoesNotProduceSwimabilityDecisionFields() {
        let state = normalize(test: makeTest())
        let propertyNames = Set(Mirror(reflecting: state).children.compactMap(\.label))

        XCTAssertFalse(propertyNames.contains("state"))
        XCTAssertFalse(propertyNames.contains("confidence"))
        XCTAssertFalse(propertyNames.contains("gateResults"))
        XCTAssertFalse(propertyNames.contains("testingRequired"))
    }

    func testSwimabilityV2EngineStillReturnsPlaceholderAssessment() {
        let assessment = SwimabilityV2Engine().assess(request: request(test: makeTest()))

        XCTAssertEqual(assessment.state, .moreInformationNeeded)
        XCTAssertEqual(assessment.evidenceType, .unknown)
        XCTAssertEqual(assessment.confidence, .insufficient)
        XCTAssertFalse(assessment.testingRequired)
        XCTAssertTrue(assessment.gateResults.isEmpty)
    }

    private func normalize(test: PoolTest, recentHistory: [PoolTest] = []) -> NormalizedPoolState {
        PoolStateNormalizer().normalize(request: request(test: test, recentHistory: recentHistory), evaluationDate: evaluationDate)
    }

    private func request(test: PoolTest, recentHistory: [PoolTest] = []) -> AIRecommendationRequest {
        AIRecommendationRequest(
            currentTest: test,
            recentHistory: recentHistory,
            poolConfig: PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, testMethod: .liquidDropKit)
        )
    }

    private func makeTest(
        id: UUID = UUID(),
        date: Date? = nil,
        pH: Double = 7.5,
        freeChlorine: Double = 2.0,
        totalChlorine: Double = 2.0,
        saltLevel: Double? = 3200,
        waterTemperature: Double? = 82,
        testMethod: TestMethod = .liquidDropKit,
        poolConditions: PoolConditions? = PoolConditions(),
        waterClarityAssessment: WaterClarityAssessment = .notRecorded,
        visibleAlgaeAssessment: VisibleAlgaeAssessment = .notRecorded,
        visualIndicators: [String] = [VisualIndicator.crystalClear.rawValue]
    ) -> PoolTest {
        PoolTest(
            id: id,
            date: date ?? evaluationDate.addingTimeInterval(-3600),
            pH: pH,
            freeChlorine: freeChlorine,
            totalChlorine: totalChlorine,
            totalAlkalinity: 100,
            calciumHardness: 300,
            cyanuricAcid: 40,
            temperatureFahrenheit: waterTemperature,
            saltLevel: saltLevel,
            testMethod: testMethod,
            poolConditions: poolConditions,
            visualIndicators: visualIndicators,
            waterClarityAssessment: waterClarityAssessment,
            visibleAlgaeAssessment: visibleAlgaeAssessment
        )
    }

    private func makeTreatment(
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        isSkipped: Bool = false
    ) -> Treatment {
        Treatment(
            chemicalName: "Liquid Chlorine 10%",
            actionDescription: "Test treatment",
            amount: 1,
            unit: "gal",
            instructions: "Test instructions",
            urgency: .recommended,
            isCompleted: isCompleted,
            completedAt: completedAt,
            isSkipped: isSkipped,
            targetParameter: "freeChlorine"
        )
    }
}
