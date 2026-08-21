import XCTest
@testable import Pool_Side

/// Base test case for anything that persists `PoolConfiguration`.
///
/// Under XCTest, `PoolConfiguration.defaultsStore` automatically resolves to a dedicated isolated
/// UserDefaults suite (never `.standard`) — the fix for the confirmed defect where running the suite on
/// the dogfooding iPhone overwrote the app's real preferences. This base additionally wipes that suite
/// before and after each test so tests start from a clean config domain and cannot leak into each other.
class ConfigIsolatedTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        PoolConfiguration.resetForTesting()
    }

    override func tearDown() {
        PoolConfiguration.resetForTesting()
        super.tearDown()
    }
}

/// Regression coverage proving the test-isolation seam.
final class ConfigStoreIsolationTests: ConfigIsolatedTestCase {

    // Production/default store behavior: under tests the config store is an isolated suite, never `.standard`.
    func testConfigStoreIsIsolatedFromStandardUnderTests() {
        XCTAssertFalse(PoolConfiguration.defaultsStore === UserDefaults.standard,
                       "Under XCTest, PoolConfiguration must not use UserDefaults.standard.")
    }

    // 1. Test writes must never alter UserDefaults.standard["poolConfiguration"].
    func testWritesDoNotTouchStandardDomain() {
        let standardBefore = UserDefaults.standard.data(forKey: PoolConfiguration.defaultsKey)

        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(volumeGallons: 22_000,
                                        chlorinePreference: .liquidChlorine12_5,
                                        pHDecreaserPreference: .dryAcid))
        PoolConfiguration.current = PoolConfiguration(testMethod: .liquidDropKit)

        let standardAfter = UserDefaults.standard.data(forKey: PoolConfiguration.defaultsKey)
        XCTAssertEqual(standardBefore, standardAfter,
                       "A test write leaked into the production UserDefaults.standard domain.")
    }

    // 2. Isolated configs can be created / read / updated / cleared normally.
    func testIsolatedConfigCRUD() {
        XCTAssertNil(PoolConfiguration.persisted, "Precondition: clean isolated store.")

        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(volumeGallons: 18_000,
                                        chlorinePreference: .liquidChlorine12_5,
                                        pHDecreaserPreference: .dryAcid),
                      marksEquipmentChoicesExplicit: true)

        XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5)
        XCTAssertEqual(PoolConfiguration.current.pHDecreaserPreference, .dryAcid)
        XCTAssertEqual(PoolConfiguration.current.volumeGallons, 18_000)
        XCTAssertTrue(PoolConfiguration.isConfigured)

        vm.updateConfig { $0.testMethod = .digitalTester }
        XCTAssertEqual(PoolConfiguration.current.testMethod, .digitalTester)
        XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5,
                       "Unrelated partial update must not disturb other saved preferences.")

        PoolConfiguration.clearCurrent()
        XCTAssertNil(PoolConfiguration.persisted)
        XCTAssertFalse(PoolConfiguration.isConfigured)
    }

    // 3a. Writes a distinctive config; paired with 3b to prove no cross-test leak.
    func testLeakageA_writesDistinctiveConfig() {
        let vm = PoolViewModel()
        vm.saveConfig(PoolConfiguration(chlorinePreference: .liquidChlorine12_5, pHDecreaserPreference: .dryAcid))
        XCTAssertEqual(PoolConfiguration.current.chlorinePreference, .liquidChlorine12_5)
    }

    // 3b. Regardless of execution order, this test starts from a clean isolated domain (per-test wipe).
    func testLeakageB_startsFromCleanDomain() {
        XCTAssertNil(PoolConfiguration.persisted,
                     "A prior test's config leaked into this one; per-test isolation is broken.")
    }

    // 4. Default store behavior unchanged: an unconfigured store surfaces the struct defaults for display.
    func testDefaultStoreFallbackUnchanged() {
        XCTAssertNil(PoolConfiguration.persisted)
        let current = PoolConfiguration.current
        XCTAssertEqual(current.chlorinePreference, .calHypo)
        XCTAssertEqual(current.pHDecreaserPreference, .muriaticAcid)
        XCTAssertEqual(current.testMethod, .testStrips)
    }
}
