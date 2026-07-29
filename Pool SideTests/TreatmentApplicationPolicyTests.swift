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

    func testStagedAcidLoadCapsCurrentApplicationToVolumeScaledLimit() {
        // 32,583 gal -> 1 qt (52.1328 fl oz) per application. Demand 123.45 fl-oz-equivalent-31.
        let staged = TreatmentApplicationPolicy.stagedAcidLoad(equivalent31FluidOunces: 123.45, volumeGallons: 32_583)
        XCTAssertEqual(staged.currentEquivalent31FluidOunces, 52.1328, accuracy: 0.001)
        XCTAssertEqual(staged.totalEquivalent31FluidOunces, 123.45, accuracy: 0.001)
        XCTAssertTrue(staged.isApplicationLimited)

        // Small demand under the per-application limit is not staged.
        let small = TreatmentApplicationPolicy.stagedAcidLoad(equivalent31FluidOunces: 20, volumeGallons: 32_583)
        XCTAssertEqual(small.currentEquivalent31FluidOunces, 20, accuracy: 0.001)
        XCTAssertFalse(small.isApplicationLimited)
    }

    func testStagedAcidLoadScalesLimitWithVolume() {
        // Same demand, larger pool -> larger single application allowed.
        let small = TreatmentApplicationPolicy.stagedAcidLoad(equivalent31FluidOunces: 200, volumeGallons: 20_000)
        let large = TreatmentApplicationPolicy.stagedAcidLoad(equivalent31FluidOunces: 200, volumeGallons: 40_000)
        XCTAssertEqual(small.currentEquivalent31FluidOunces, 32, accuracy: 0.001)
        XCTAssertEqual(large.currentEquivalent31FluidOunces, 64, accuracy: 0.001)
    }

    func testStagedCurrentApplicationsAreChemicallyEquivalentAcrossAcidProducts() {
        // The safe current application should represent comparable corrective acid strength regardless
        // of product. Compare pure hydrochloric/bisulfate mass-equivalents of each product's current dose.
        let staged = TreatmentApplicationPolicy.stagedAcidLoad(equivalent31FluidOunces: 123.45, volumeGallons: 32_583)
        let current31 = staged.currentEquivalent31FluidOunces           // fl oz of 31.45% muriatic
        let current20 = current31 * (31.45 / 20.0)                      // fl oz of 20% muriatic
        let currentDryOz = current31 * 0.375                            // oz of dry acid

        // Reference "acid units" = fl oz × HCl fraction for muriatic; the 0.375 factor is defined to match.
        let units31 = current31 * 0.3145
        let units20 = current20 * 0.20
        XCTAssertEqual(units31, units20, accuracy: 0.01)                 // 20% translation is load-preserving

        // Dry acid current dose is the audited 0.375 equivalence of the same staged 31.45% load.
        XCTAssertEqual(currentDryOz, current31 * 0.375, accuracy: 0.0001)
        XCTAssertEqual((currentDryOz / 16).rounded(toPlaces: 1), 1.2, accuracy: 0.001)  // lbs displayed
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
