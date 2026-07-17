import XCTest
@testable import Pool_Side

final class ChemicalProductModelTests: XCTestCase {
    func testChemicalProductIdentifiersExposeStableProductMetadata() {
        let expected: [(ChemicalProductID, String, String, String, [String])] = [
            (.liquidChlorine10, "liquid_chlorine_10", "Liquid Chlorine 10%", "10% sodium hypochlorite", ["raises FC", "does not raise CYA"]),
            (.liquidChlorine12_5, "liquid_chlorine_12_5", "Liquid Chlorine 12.5%", "12.5% sodium hypochlorite", ["raises FC", "does not raise CYA"]),
            (.trichlorTablets, "tablets", "Chlorine Tablets (Trichlor)", "trichlor stabilized chlorine", ["raises FC", "raises CYA", "acidic effect"]),
            (.calHypoGranules, "cal_hypo", "Cal-Hypo Granules", "calcium hypochlorite", ["raises FC", "raises calcium hardness"]),
            (.dichlorGranules, "dichlor", "Dichlor Granules", "dichlor stabilized chlorine", ["raises FC", "raises CYA"]),
            (.saltGenerator, "salt_generator", "Salt Chlorine Generator", "chlorine production source", ["raises FC by generation", "no manual dose"]),
            (.sodaAsh, "soda_ash", "Soda Ash (Sodium Carbonate)", "Soda Ash (Sodium Carbonate)", ["raises pH", "raises TA"]),
            (.borax, "borax", "Borax", "Borax", ["raises pH", "smaller TA effect than soda ash"]),
            (.muriaticAcid31, "muriatic_acid", "Muriatic Acid (31.45%)", "31.45% hydrochloric acid", ["lowers pH", "lowers TA"]),
            (.muriaticAcid20, "low_fume_muriatic_acid", "Low-Fume Muriatic Acid (20%)", "20% hydrochloric acid", ["lowers pH", "lowers TA"]),
            (.dryAcid, "dry_acid", "Dry Acid (Sodium Bisulfate)", "sodium bisulfate", ["lowers pH", "lowers TA", "adds sulfate over time"]),
            (.bakingSoda, "sodium_bicarbonate", "Baking Soda (Sodium Bicarbonate)", "Baking Soda (Sodium Bicarbonate)", ["raises TA"]),
            (.calciumChloride, "calcium_chloride", "Calcium Chloride", "Calcium Chloride", ["raises calcium hardness"]),
            (.granularCYA, "granular_cya", "Cyanuric Acid (Granular)", "Cyanuric Acid (Granular)", ["raises CYA"]),
            (.liquidStabilizer, "liquid_conditioner", "Liquid Stabilizer", "Liquid Stabilizer", ["raises CYA"])
        ]

        XCTAssertEqual(ChemicalProductID.allCases.count, expected.count, "Every product should be represented in the product metadata test.")

        for (product, rawValue, displayName, concentration, effects) in expected {
            XCTAssertEqual(product.rawValue, rawValue, "\(displayName) raw value changed unexpectedly.")
            XCTAssertEqual(product.displayName, displayName)
            XCTAssertEqual(product.concentrationLabel, concentration)
            XCTAssertFalse(product.doseUnitKind.isEmpty, "\(displayName) should expose a dose unit kind.")
            for effect in effects {
                XCTAssertTrue(product.chemistryEffects.contains(effect), "\(displayName) missing effect: \(effect)")
            }
        }
    }
}
