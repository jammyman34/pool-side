import XCTest
@testable import Pool_Side

final class TestEntryContextTests: XCTestCase {
    private let resolver = TestEntryContextResolver()
    private let config = PoolConfiguration(volumeGallons: 18_000)

    func testZeroPriorTestsSelectsInitialAssessment() {
        let context = resolver.resolve(poolConfig: config, recentHistory: [])

        XCTAssertEqual(context.kind, .initialAssessment)
        XCTAssertTrue(context.followUpReasons.isEmpty)
    }

    func testPriorStableTestSelectsMaintenance() {
        let context = resolver.resolve(poolConfig: config, recentHistory: [stableTest()])

        XCTAssertEqual(context.kind, .maintenance)
        XCTAssertTrue(context.followUpReasons.isEmpty)
    }

    func testPriorAlgaePresentSelectsAlgaeFollowUp() {
        let context = resolver.resolve(poolConfig: config, recentHistory: [test(algae: .present)])

        XCTAssertEqual(context.kind, .followUp)
        XCTAssertEqual(context.followUpReasons.first, .previouslyReportedAlgae)
    }

    func testAlgaePresentFollowedByExplicitAlgaeAbsentReturnsMaintenance() {
        let older = test(date: Date(timeIntervalSince1970: 1_000), algae: .present)
        let newer = test(date: Date(timeIntervalSince1970: 2_000), clarity: .clear, algae: .absent)

        let context = resolver.resolve(poolConfig: config, recentHistory: [older, newer])

        XCTAssertEqual(context.kind, .maintenance)
        XCTAssertFalse(context.followUpReasons.contains(.previouslyReportedAlgae))
    }

    func testPriorCloudyWaterSelectsCloudinessFollowUp() {
        let context = resolver.resolve(poolConfig: config, recentHistory: [test(clarity: .cloudy)])

        XCTAssertEqual(context.kind, .followUp)
        XCTAssertTrue(context.followUpReasons.contains(.previouslyCloudyWater))
    }

    func testCloudyFollowedByExplicitClearReturnsMaintenance() {
        let older = test(date: Date(timeIntervalSince1970: 1_000), clarity: .cloudy)
        let newer = test(date: Date(timeIntervalSince1970: 2_000), clarity: .clear, algae: .absent)

        let context = resolver.resolve(poolConfig: config, recentHistory: [older, newer])

        XCTAssertEqual(context.kind, .maintenance)
        XCTAssertFalse(context.followUpReasons.contains(.previouslyCloudyWater))
    }

    func testUnresolvedAlgaeTakesPriorityOverLowerPriorityObservations() {
        let recent = test(clarity: .cloudy, algae: .present, totalChlorine: 5.6, freeChlorine: 4.5)

        let context = resolver.resolve(poolConfig: config, recentHistory: [recent])

        XCTAssertEqual(context.followUpReasons.first, .previouslyReportedAlgae)
        XCTAssertTrue(context.followUpReasons.contains(.previouslyCloudyWater))
    }

    func testHistoricalResolvedConcernDoesNotKeepGeneratingFollowUp() {
        let oldest = test(date: Date(timeIntervalSince1970: 1_000), clarity: .cloudy, algae: .present)
        let middle = test(date: Date(timeIntervalSince1970: 2_000), clarity: .clear, algae: .absent)
        let newest = stableTest(date: Date(timeIntervalSince1970: 3_000))

        let context = resolver.resolve(poolConfig: config, recentHistory: [oldest, newest, middle])

        XCTAssertEqual(context.kind, .maintenance)
    }

    func testCurrentCannotTellDoesNotFalselyResolvePriorAlgaeConcern() {
        let older = test(date: Date(timeIntervalSince1970: 1_000), algae: .present)
        let newer = test(date: Date(timeIntervalSince1970: 2_000), clarity: .cannotTell, algae: .cannotTell)

        let context = resolver.resolve(poolConfig: config, recentHistory: [newer, older])

        XCTAssertEqual(context.kind, .followUp)
        XCTAssertTrue(context.followUpReasons.contains(.previouslyReportedAlgae))
    }

    func testMaintenanceLooksClearNormalRecordsExplicitNormalVisualState() {
        let mapped = MaintenanceVisualResponseMapper.mappedAssessments(for: .looksClearNormal)

        XCTAssertEqual(mapped.clarity, .clear)
        XCTAssertEqual(mapped.algae, .absent)
        XCTAssertFalse(mapped.revealsDetailedObservations)
    }

    func testMaintenanceSomethingDifferentRevealsDetailedObservations() {
        let mapped = MaintenanceVisualResponseMapper.mappedAssessments(for: .somethingLooksDifferent)

        XCTAssertEqual(mapped.clarity, .notRecorded)
        XCTAssertEqual(mapped.algae, .notRecorded)
        XCTAssertTrue(mapped.revealsDetailedObservations)
    }

    func testMaintenanceCannotTellPreservesUncertainty() {
        let mapped = MaintenanceVisualResponseMapper.mappedAssessments(for: .cannotTell)

        XCTAssertEqual(mapped.clarity, .cannotTell)
        XCTAssertEqual(mapped.algae, .cannotTell)
        XCTAssertFalse(mapped.revealsDetailedObservations)
    }

    func testFollowUpAlgaeResponseMapping() {
        XCTAssertEqual(FollowUpVisualResponseMapper.algaeResponse(.yes), .absent)
        XCTAssertEqual(FollowUpVisualResponseMapper.algaeResponse(.no), .present)
        XCTAssertEqual(FollowUpVisualResponseMapper.algaeResponse(.mostly), .present)
        XCTAssertEqual(FollowUpVisualResponseMapper.algaeResponse(.cannotTell), .cannotTell)
    }

    func testFollowUpCloudinessResponseMapping() {
        XCTAssertEqual(FollowUpVisualResponseMapper.cloudinessResponse(.yes), .clear)
        XCTAssertEqual(FollowUpVisualResponseMapper.cloudinessResponse(.no), .cloudy)
        XCTAssertEqual(FollowUpVisualResponseMapper.cloudinessResponse(.mostly), .cloudy)
        XCTAssertEqual(FollowUpVisualResponseMapper.cloudinessResponse(.cannotTell), .cannotTell)
    }

    private func stableTest(date: Date = Date(timeIntervalSince1970: 10_000)) -> PoolTest {
        test(date: date, clarity: .clear, algae: .absent, totalChlorine: 5.0, freeChlorine: 5.0)
    }

    private func test(
        date: Date = Date(timeIntervalSince1970: 10_000),
        clarity: WaterClarityAssessment = .notRecorded,
        algae: VisibleAlgaeAssessment = .notRecorded,
        totalChlorine: Double = 5.0,
        freeChlorine: Double = 5.0,
        visualIndicators: [String] = []
    ) -> PoolTest {
        PoolTest(
            date: date,
            pH: 7.5,
            freeChlorine: freeChlorine,
            totalChlorine: totalChlorine,
            totalAlkalinity: 100,
            calciumHardness: 300,
            cyanuricAcid: 50,
            testMethod: .liquidDropKit,
            visualIndicators: visualIndicators,
            waterClarityAssessment: clarity,
            visibleAlgaeAssessment: algae
        )
    }
}
