import XCTest
@testable import Pool_Side

final class ChemicalDoseCalculatorTests: XCTestCase {
    func testLiquidChlorineDosesUseStrengthAndScaleLinearly() {
        XCTAssertEqual(ChemicalDoseCalculator.liquidChlorineGallons(volumeGallons: 10_000, ppmIncrease: 1, strengthPercent: 10), 0.1, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.liquidChlorineGallons(volumeGallons: 10_000, ppmIncrease: 1, strengthPercent: 12.5), 0.08, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.liquidChlorineGallons(volumeGallons: 20_000, ppmIncrease: 1, strengthPercent: 10), 0.2, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.liquidChlorineGallons(volumeGallons: 10_000, ppmIncrease: 2, strengthPercent: 10), 0.2, accuracy: 0.0001)
    }

    func testDryChlorineDosesUseTenThousandGallonBasis() {
        XCTAssertEqual(ChemicalDoseCalculator.calHypoPounds(volumeGallons: 10_000, ppmIncrease: 1), 0.125, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.calHypoPounds(volumeGallons: 20_000, ppmIncrease: 1), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.calHypoPounds(volumeGallons: 10_000, ppmIncrease: 2), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.dichlorPounds(volumeGallons: 10_000, ppmIncrease: 1), 0.15625, accuracy: 0.0001)
    }

    func testCarbonateAlkalinityAdjustsMeasuredTAForCYAAndPH() {
        XCTAssertEqual(ChemicalDoseCalculator.cyanuricAcidCorrectionFactor(pH: 7.4), 0.31, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.cyanuricAcidCorrectionFactor(pH: 7.5), 0.325, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.carbonateAlkalinity(totalAlkalinity: 140, cyanuricAcid: 60, pH: 8.0), 118.4, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.carbonateAlkalinity(totalAlkalinity: 100, cyanuricAcid: 60, pH: 7.5), 80.5, accuracy: 0.0001)
    }

    func testPHIncreaseDosesUseTenThousandGallonBasisAndBuffering() {
        XCTAssertEqual(ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 10_000, pHIncrease: 0.2), 6, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 20_000, pHIncrease: 0.2), 12, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 10_000, pHIncrease: 0.4), 12, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.boraxOunces(volumeGallons: 10_000, pHIncrease: 0.2), 11.4, accuracy: 0.0001)

        let lowBuffer = ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 10_000, currentPH: 7.0, targetPH: 7.2, totalAlkalinity: 80, cyanuricAcid: 60)
        let highBuffer = ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 10_000, currentPH: 7.0, targetPH: 7.2, totalAlkalinity: 140, cyanuricAcid: 60)
        XCTAssertLessThan(lowBuffer, highBuffer)
        XCTAssertEqual(ChemicalDoseCalculator.boraxOunces(volumeGallons: 10_000, currentPH: 7.0, targetPH: 7.2, totalAlkalinity: 100, cyanuricAcid: 60), ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 10_000, currentPH: 7.0, targetPH: 7.2, totalAlkalinity: 100, cyanuricAcid: 60) * 1.9, accuracy: 0.0001)
    }

    func testPHDecreaseDosesUseAuditedAcidConstantsAndBuffering() {
        XCTAssertEqual(ChemicalDoseCalculator.muriaticAcid31FluidOuncesForPH(volumeGallons: 10_000, pHDecrease: 0.4), 25.6, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.muriaticAcid20FluidOuncesForPH(volumeGallons: 10_000, pHDecrease: 0.4), 40.256, accuracy: 0.001)
        XCTAssertEqual(ChemicalDoseCalculator.dryAcidOuncesForPH(volumeGallons: 10_000, pHDecrease: 0.4), 9.6, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.muriaticAcid31FluidOuncesForAlkalinity(volumeGallons: 10_000, ppmDecrease: 40), 102.4, accuracy: 0.0001)

        let acidTA80 = ChemicalDoseCalculator.muriaticAcid31FluidOuncesForPH(volumeGallons: 32_583, currentPH: 8.0, targetPH: 7.5, totalAlkalinity: 80, cyanuricAcid: 60)
        let acidTA100 = ChemicalDoseCalculator.muriaticAcid31FluidOuncesForPH(volumeGallons: 32_583, currentPH: 8.0, targetPH: 7.5, totalAlkalinity: 100, cyanuricAcid: 60)
        let acidTA140 = ChemicalDoseCalculator.muriaticAcid31FluidOuncesForPH(volumeGallons: 32_583, currentPH: 8.0, targetPH: 7.5, totalAlkalinity: 140, cyanuricAcid: 60)
        XCTAssertLessThan(acidTA80, acidTA100)
        XCTAssertLessThan(acidTA100, acidTA140)
        XCTAssertEqual(acidTA140, 123.45, accuracy: 0.01)
        XCTAssertEqual(ChemicalDoseCalculator.muriaticAcid20FluidOuncesForPH(volumeGallons: 32_583, currentPH: 8.0, targetPH: 7.5, totalAlkalinity: 140, cyanuricAcid: 60), 194.13, accuracy: 0.01)
        XCTAssertEqual(ChemicalDoseCalculator.dryAcidOuncesForPH(volumeGallons: 32_583, currentPH: 8.0, targetPH: 7.5, totalAlkalinity: 140, cyanuricAcid: 60), 46.29, accuracy: 0.01)
    }

    func testBakingSodaDosesUseTenThousandGallonBasis() {
        XCTAssertEqual(ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 32_583, ppmIncrease: 30).rounded(toPlaces: 1), 13.7, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 20_000, ppmIncrease: 30), ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 10_000, ppmIncrease: 30) * 2, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 10_000, ppmIncrease: 60), ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 10_000, ppmIncrease: 30) * 2, accuracy: 0.0001)
    }

    func testCalciumChlorideDosesUseTenThousandGallonBasis() {
        XCTAssertEqual(ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 32_583, ppmIncrease: 100).rounded(toPlaces: 1), 40.7, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 20_000, ppmIncrease: 100), ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 10_000, ppmIncrease: 100) * 2, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 10_000, ppmIncrease: 200), ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 10_000, ppmIncrease: 100) * 2, accuracy: 0.0001)
    }

    func testGranularCYADosesUseTenThousandGallonBasis() {
        XCTAssertEqual(ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 32_583, ppmIncrease: 20).rounded(toPlaces: 1), 5.3, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 20_000, ppmIncrease: 20), ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 10_000, ppmIncrease: 20) * 2, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 10_000, ppmIncrease: 40), ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 10_000, ppmIncrease: 20) * 2, accuracy: 0.0001)
    }

    func testSaltDosesUseTenThousandGallonBasis() {
        XCTAssertEqual(ChemicalDoseCalculator.saltPounds(volumeGallons: 10_000, ppmIncrease: 100), 8.3333, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.saltPounds(volumeGallons: 20_000, ppmIncrease: 100), ChemicalDoseCalculator.saltPounds(volumeGallons: 10_000, ppmIncrease: 100) * 2, accuracy: 0.0001)
        XCTAssertEqual(ChemicalDoseCalculator.saltPounds(volumeGallons: 10_000, ppmIncrease: 200), ChemicalDoseCalculator.saltPounds(volumeGallons: 10_000, ppmIncrease: 100) * 2, accuracy: 0.0001)
    }

    func testResidentialMaintenanceCorrectionsAvoidOrderOfMagnitudeRegressions() {
        XCTAssertLessThan(ChemicalDoseCalculator.sodiumBicarbonatePounds(volumeGallons: 32_583, ppmIncrease: 30), 20)
        XCTAssertLessThan(ChemicalDoseCalculator.granularCYAPounds(volumeGallons: 32_583, ppmIncrease: 20), 10)
        XCTAssertLessThan(ChemicalDoseCalculator.calciumChloridePounds(volumeGallons: 32_583, ppmIncrease: 100), 60)
        XCTAssertLessThan(ChemicalDoseCalculator.sodaAshOunces(volumeGallons: 32_583, pHIncrease: 0.2), 30)
    }
}
