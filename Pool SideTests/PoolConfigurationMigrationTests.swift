import XCTest
@testable import Pool_Side

final class PoolConfigurationMigrationTests: ConfigIsolatedTestCase {
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

    func testPartialConfigUpdatePreservesCoverAndRoboticCleanerSettings() {
        preservePoolConfigurationDefaults {
            PoolConfiguration.current = PoolConfiguration(
                volumeGallons: 32_583,
                surfaceType: .plaster,
                testMethod: .liquidDropKit,
                isSaltwater: false,
                hasCover: true,
                petsRegularlySwim: true,
                usesRoboticCleaner: true,
                chlorinePreference: .liquidChlorine12_5
            )
            let viewModel = PoolViewModel()

            viewModel.updateConfig { config in
                config.chlorinePreference = .liquidChlorine10
            }

            let updated = PoolConfiguration.current
            XCTAssertTrue(updated.hasCover)
            XCTAssertTrue(updated.petsRegularlySwim)
            XCTAssertTrue(updated.usesRoboticCleaner)
            XCTAssertEqual(updated.chlorinePreference, .liquidChlorine10)
            XCTAssertEqual(updated.volumeGallons, 32_583)
            XCTAssertEqual(updated.testMethod, .liquidDropKit)
        }
    }

    func testRecoveredEquipmentBackupsSurviveDefaultConfigurationOverwrite() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()
            viewModel.saveConfig(
                PoolConfiguration(
                    volumeGallons: 32_583,
                    hasCover: true,
                    usesRoboticCleaner: true
                ),
                marksEquipmentChoicesExplicit: true
            )

            PoolConfiguration.current = PoolConfiguration(volumeGallons: 32_583)

            let recovered = PoolConfiguration.current
            XCTAssertTrue(recovered.hasCover)
            XCTAssertTrue(recovered.usesRoboticCleaner)
        }
    }

    func testSavedTestHistoryCanRecoverMissingEquipmentSettings() {
        preservePoolConfigurationDefaults {
            PoolConfiguration.current = PoolConfiguration(volumeGallons: 32_583)
            let historicalTest = PoolTest(
                pH: 7.5,
                freeChlorine: 5,
                totalChlorine: 5,
                totalAlkalinity: 100,
                calciumHardness: 330,
                cyanuricAcid: 60,
                poolConditions: PoolConditions(
                    coverOpenTime: .twoToSixHours,
                    cleaningActivity: .oneCycle
                )
            )
            let viewModel = PoolViewModel()

            viewModel.refreshConfigFromStorage(reconcilingWith: [historicalTest])

            XCTAssertTrue(viewModel.poolConfig.hasCover)
            XCTAssertTrue(viewModel.poolConfig.usesRoboticCleaner)
            XCTAssertTrue(PoolConfiguration.current.hasCover)
            XCTAssertTrue(PoolConfiguration.current.usesRoboticCleaner)
        }
    }

    func testExplicitEquipmentOffChoiceIsNotReenabledByHistory() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()
            viewModel.saveConfig(
                PoolConfiguration(
                    volumeGallons: 32_583,
                    hasCover: false,
                    usesRoboticCleaner: false
                ),
                marksEquipmentChoicesExplicit: true
            )
            let historicalTest = PoolTest(
                pH: 7.5,
                freeChlorine: 5,
                totalChlorine: 5,
                totalAlkalinity: 100,
                calciumHardness: 330,
                cyanuricAcid: 60,
                poolConditions: PoolConditions(
                    coverOpenTime: .twoToSixHours,
                    cleaningActivity: .oneCycle
                )
            )

            viewModel.refreshConfigFromStorage(reconcilingWith: [historicalTest])

            XCTAssertFalse(viewModel.poolConfig.hasCover)
            XCTAssertFalse(viewModel.poolConfig.usesRoboticCleaner)
        }
    }

    func testManualVacuumHistoryDoesNotRecoverRoboticCleanerSetting() {
        preservePoolConfigurationDefaults {
            PoolConfiguration.current = PoolConfiguration(volumeGallons: 32_583)
            let historicalTest = PoolTest(
                pH: 7.5,
                freeChlorine: 5,
                totalChlorine: 5,
                totalAlkalinity: 100,
                calciumHardness: 330,
                cyanuricAcid: 60,
                poolConditions: PoolConditions(cleaningActivity: .entirePool)
            )
            let viewModel = PoolViewModel()

            viewModel.refreshConfigFromStorage(reconcilingWith: [historicalTest])

            XCTAssertFalse(viewModel.poolConfig.usesRoboticCleaner)
        }
    }

    func testInvalidSavedFieldDoesNotResetCoverOrRoboticCleanerSettings() throws {
        let json = """
        {
            "name": "Dogfood Pool",
            "volumeGallons": 32583,
            "surfaceType": "plaster",
            "testMethod": "liquid_drop_kit",
            "liquidDropKitBrand": "Unsupported Future Kit",
            "isSaltwater": false,
            "hasCover": true,
            "petsRegularlySwim": false,
            "usesRoboticCleaner": true,
            "chlorinePreference": "liquid_chlorine_12_5"
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))

        let config = try JSONDecoder().decode(PoolConfiguration.self, from: data)

        XCTAssertEqual(config.name, "Dogfood Pool")
        XCTAssertEqual(config.volumeGallons, 32_583)
        XCTAssertEqual(config.testMethod, .liquidDropKit)
        XCTAssertEqual(config.liquidDropKitBrand, .taylorK2006FASDPD)
        XCTAssertTrue(config.hasCover)
        XCTAssertTrue(config.usesRoboticCleaner)
        XCTAssertEqual(config.chlorinePreference, .liquidChlorine12_5)
    }

    func testTreatmentProductDefaultUpdatePreservesUnrelatedPoolConfiguration() {
        var config = PoolConfiguration(
            volumeGallons: 32_583,
            surfaceType: .plaster,
            testMethod: .liquidDropKit,
            isSaltwater: false,
            hasCover: true,
            petsRegularlySwim: false,
            usesRoboticCleaner: true,
            chlorinePreference: .liquidChlorine12_5
        )

        config = ChemicalProductCategory.chlorine.configApplying(
            selection: .liquidChlorine10,
            to: config
        )

        XCTAssertTrue(config.hasCover)
        XCTAssertTrue(config.usesRoboticCleaner)
        XCTAssertFalse(config.petsRegularlySwim)
        XCTAssertEqual(config.chlorinePreference, .liquidChlorine10)
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let data = try JSONEncoder().encode(string)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func preservePoolConfigurationDefaults(_ body: () -> Void) {
        let keys = [
            PoolConfiguration.defaultsKey,
            PoolConfiguration.hasCoverBackupKey,
            PoolConfiguration.usesRoboticCleanerBackupKey,
            PoolConfiguration.hasCoverExplicitChoiceKey,
            PoolConfiguration.usesRoboticCleanerExplicitChoiceKey
        ]
        let originalValues = keys.reduce(into: [String: Any]()) { result, key in
            if let value = UserDefaults.standard.object(forKey: key) {
                result[key] = value
            }
        }

        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        body()

        keys.forEach { key in
            if let value = originalValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
