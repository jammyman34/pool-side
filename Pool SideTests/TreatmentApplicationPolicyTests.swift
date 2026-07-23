import XCTest
@testable import Pool_Side

final class TreatmentApplicationPolicyTests: XCTestCase {
    func testMuriaticAcid31ApplicationLimitScalesWithPoolVolume() {
        XCTAssertEqual(
            TreatmentApplicationPolicy.muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: 20_000),
            32,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TreatmentApplicationPolicy.muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: 40_000),
            64,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TreatmentApplicationPolicy.muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: 32_583),
            52.1328,
            accuracy: 0.001
        )
    }

    func testMuriaticAcid31SeparatesTotalRequirementFromCurrentApplication() {
        let application = TreatmentApplicationPolicy.muriaticAcid31CurrentApplication(
            totalFluidOunces: 123.45,
            volumeGallons: 32_583,
            displayDose: { ounces in
                if ounces < 32 { return (ounces.rounded(), "fl oz") }
                if ounces < 128 { return ((((ounces / 32) * 2).rounded() / 2), "qt") }
                return ((ounces / 128).rounded(toPlaces: 1), "gal")
            }
        )

        XCTAssertEqual(application.currentAmount, 1.5, accuracy: 0.001)
        XCTAssertEqual(application.currentUnit, "qt")
        XCTAssertEqual(application.totalCalculatedAmount, 4.0, accuracy: 0.001)
        XCTAssertEqual(application.totalCalculatedUnit, "qt")
        XCTAssertTrue(application.isApplicationLimited)
        XCTAssertGreaterThan(application.remainingEstimatedAmount, 0)
    }

    func testPoolCareRetestPolicyWindowsAreSeparatedFromSwimRestrictions() {
        XCTAssertEqual(TreatmentApplicationPolicy.bakingSodaRetestWindowHours.lowerBound, 6, accuracy: 0.001)
        XCTAssertEqual(TreatmentApplicationPolicy.bakingSodaRetestWindowHours.upperBound, 8, accuracy: 0.001)
        XCTAssertEqual(TreatmentApplicationPolicy.calciumChlorideRetestHours, 24)
        XCTAssertEqual(TreatmentApplicationPolicy.granularCYARetestWindowHours.lowerBound, 24, accuracy: 0.001)
        XCTAssertEqual(TreatmentApplicationPolicy.granularCYARetestWindowHours.upperBound, 48, accuracy: 0.001)
        XCTAssertEqual(TreatmentApplicationPolicy.granularCYACanonicalRetestHours, 48)
    }
}
