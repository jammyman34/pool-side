import XCTest
@testable import Pool_Side

final class PoolConfigurationMigrationTests: XCTestCase {
    func testRetiredPreferenceLabelsMigrateToCurrentProducts() throws {
        XCTAssertEqual(try decode(ChlorinePreference.self, from: "Chlorine Granules"), .calHypo)
        XCTAssertEqual(try decode(ChlorinePreference.self, from: "Chlorine Tablets"), .tablets)
        XCTAssertEqual(try decode(PHIncreaserPreference.self, from: "pH Increaser / Soda Ash"), .sodaAsh)
        XCTAssertEqual(try decode(PHDecreaserPreference.self, from: "pH Decreaser / Muriatic Acid"), .muriaticAcid)
        XCTAssertEqual(try decode(PHDecreaserPreference.self, from: "pH Decreaser / Dry Acid"), .dryAcid)
        XCTAssertEqual(try decode(StabilizerPreference.self, from: "Pool Stabilizer Granules"), .granularCYA)
        XCTAssertEqual(try decode(StabilizerPreference.self, from: "Liquid Pool Stabilizer"), .liquidConditioner)
    }

    func testUnknownLegacyValuesFailSafelyToValidFallbacks() throws {
        XCTAssertEqual(try decode(ChlorinePreference.self, from: "Mystery Chlorine"), .calHypo)
        XCTAssertEqual(try decode(PHIncreaserPreference.self, from: "Mystery pH Up"), .sodaAsh)
        XCTAssertEqual(try decode(PHDecreaserPreference.self, from: "Mystery Acid"), .muriaticAcid)
        XCTAssertEqual(try decode(StabilizerPreference.self, from: "Mystery Stabilizer"), .granularCYA)
    }

    func testSaltTogglePreservesAndRestoresManualChlorinePreference() {
        var config = ChemistryTestFixtures.config(
            chlorine: .liquidChlorine12_5,
            pHDecreaser: .dryAcid,
            stabilizer: .liquidConditioner
        )

        config.setSaltwater(true)
        XCTAssertTrue(config.isSaltwater)
        XCTAssertEqual(config.chlorinePreference, .saltGenerator)
        XCTAssertEqual(config.lastNonSaltChlorinePreference, .liquidChlorine12_5)
        XCTAssertEqual(config.pHDecreaserPreference, .dryAcid, "Unrelated acid preference should not change.")
        XCTAssertEqual(config.stabilizerPreference, .liquidConditioner, "Unrelated stabilizer preference should not change.")

        config.setSaltwater(false)
        XCTAssertFalse(config.isSaltwater)
        XCTAssertEqual(config.chlorinePreference, .liquidChlorine12_5)
        XCTAssertNotEqual(config.chlorinePreference, .saltGenerator)

        config.setSaltwater(true)
        config.setSaltwater(false)
        XCTAssertEqual(config.chlorinePreference, .liquidChlorine12_5, "Repeated toggling should not corrupt the remembered manual product.")
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = try JSONEncoder().encode(string)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
