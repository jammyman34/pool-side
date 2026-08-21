import XCTest
@testable import Pool_Side

/// Guards that a missing/invalid persisted configuration is never silently converted into saved struct
/// defaults (Cal-Hypo / Muriatic) by an unrelated read-modify-write, while intentional setup / Settings /
/// treatment "save as default" writes continue to work.
@MainActor
final class ConfigurationPersistenceGuardTests: ConfigIsolatedTestCase {

    // MARK: - Saved preferences survive refresh and unrelated updates

    func testSavedChlorineAndAcidSurviveRefreshAndUnrelatedUpdate() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()
            viewModel.saveConfig(
                PoolConfiguration(
                    volumeGallons: 20_000,
                    chlorinePreference: .liquidChlorine12_5,
                    pHDecreaserPreference: .dryAcid
                )
            )

            viewModel.refreshConfigFromStorage(reconcilingWith: [])
            XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5)
            XCTAssertEqual(PoolConfiguration.current.pHDecreaserPreference, .dryAcid)

            // An unrelated partial update must not disturb the saved chemical preferences.
            viewModel.updateConfig { $0.testMethod = .digitalTester }
            XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5)
            XCTAssertEqual(PoolConfiguration.current.pHDecreaserPreference, .dryAcid)
            XCTAssertEqual(PoolConfiguration.current.testMethod, .digitalTester)
        }
    }

    // MARK: - Missing / invalid config is not cemented as defaults by an unrelated writer

    func testUnrelatedUpdateDoesNotPersistDefaultsWhenNoConfigStored() {
        preservePoolConfigurationDefaults {
            XCTAssertNil(PoolConfiguration.persisted, "Precondition: nothing stored.")
            let viewModel = PoolViewModel()

            viewModel.updateConfig { $0.testMethod = .digitalTester }

            XCTAssertNil(PoolConfiguration.persisted,
                         "An unrelated update must not create a persisted default (Cal-Hypo/Muriatic) config.")
            XCTAssertNil(UserDefaults.standard.data(forKey: PoolConfiguration.defaultsKey))
        }
    }

    func testInvalidStoredConfigIsNotConvertedToPersistedDefaults() {
        preservePoolConfigurationDefaults {
            UserDefaults.standard.set(Data("not valid json".utf8), forKey: PoolConfiguration.defaultsKey)
            XCTAssertNil(PoolConfiguration.persisted, "Invalid data does not decode to a valid config.")
            let viewModel = PoolViewModel()

            viewModel.updateConfig { $0.testMethod = .digitalTester }

            XCTAssertNil(PoolConfiguration.persisted,
                         "An unrelated update must not overwrite invalid data with persisted defaults.")
        }
    }

    func testRefreshWithHistoryDoesNotPersistDefaultsWhenNoConfigStored() {
        preservePoolConfigurationDefaults {
            XCTAssertNil(PoolConfiguration.persisted)
            let viewModel = PoolViewModel()
            let historicalTest = PoolTest(
                pH: 7.5, freeChlorine: 5, totalChlorine: 5, totalAlkalinity: 100,
                calciumHardness: 330, cyanuricAcid: 60,
                poolConditions: PoolConditions(coverOpenTime: .twoToSixHours)
            )

            viewModel.refreshConfigFromStorage(reconcilingWith: [historicalTest])

            XCTAssertNil(PoolConfiguration.persisted,
                         "Reconciling against history without a stored config must not persist defaults.")
        }
    }

    // MARK: - Intentional writes still work

    func testFirstUseDefaultsPersist() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()

            viewModel.saveConfig(PoolConfiguration(volumeGallons: 15_000), marksEquipmentChoicesExplicit: true)

            XCTAssertNotNil(PoolConfiguration.persisted, "First-use setup persists a config.")
            XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .calHypo)
            XCTAssertEqual(PoolConfiguration.current.pHDecreaserPreference, .muriaticAcid)
        }
    }

    func testExplicitSettingsSaveOverwritesPreferences() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()
            viewModel.saveConfig(PoolConfiguration(volumeGallons: 15_000))

            viewModel.saveConfig(
                PoolConfiguration(
                    volumeGallons: 18_000,
                    chlorinePreference: .liquidChlorine12_5,
                    pHDecreaserPreference: .dryAcid
                ),
                marksEquipmentChoicesExplicit: true
            )

            XCTAssertEqual(PoolConfiguration.current.volumeGallons, 18_000)
            XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5)
            XCTAssertEqual(PoolConfiguration.current.pHDecreaserPreference, .dryAcid)
        }
    }

    func testTreatmentSaveAsDefaultUpdatesPreference() {
        preservePoolConfigurationDefaults {
            let viewModel = PoolViewModel()
            viewModel.saveConfig(PoolConfiguration(volumeGallons: 15_000, chlorinePreference: .calHypo))

            viewModel.updateConfig { config in
                config = ChemicalProductCategory.chlorine.configApplying(selection: .liquidChlorine12_5, to: config)
            }

            XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5,
                           "Treatment-level 'save as default' still persists the chosen product.")
        }
    }

    // MARK: - Isolation helper

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
