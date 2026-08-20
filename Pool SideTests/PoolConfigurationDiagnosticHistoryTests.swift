import XCTest
@testable import Pool_Side

/// TEMP DIAGNOSTIC — remove before App Store submission (alongside the instrumentation in
/// `PoolConfiguration`). Proves the rolling configuration-event history: entries are appended and capped,
/// clears are recorded, and — critically — the diagnostic storage can never alter or break the real
/// persisted configuration, even when the diagnostic store itself is corrupt.
final class PoolConfigurationDiagnosticHistoryTests: XCTestCase {

    private func config(
        chlorine: ChlorinePreference,
        pHDecreaser: PHDecreaserPreference,
        method: TestMethod
    ) -> PoolConfiguration {
        PoolConfiguration(
            volumeGallons: 20_000,
            testMethod: method,
            chlorinePreference: chlorine,
            pHDecreaserPreference: pHDecreaser
        )
    }

    // 1. Writes are appended to the history.
    func testWriteEventIsAppended() {
        preserveDiagnosticState {
            PoolConfiguration.clearDiagnosticHistory()

            PoolConfiguration.current = config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid, method: .liquidDropKit)

            let entries = PoolConfiguration.diagnosticHistoryEntries()
            XCTAssertEqual(entries.count, 1)
            let entry = entries.last!
            XCTAssertEqual(entry.eventType, .write)
            XCTAssertEqual(entry.afterChlorine, ChlorinePreference.liquidChlorine12_5.rawValue)
            XCTAssertEqual(entry.afterPHDecreaser, PHDecreaserPreference.dryAcid.rawValue)
            XCTAssertEqual(entry.afterTestMethod, TestMethod.liquidDropKit.rawValue)
            XCTAssertFalse(entry.caller.isEmpty)
        }
    }

    // 2. History is capped at ~20 entries.
    func testHistoryIsCappedAtTwentyEntries() {
        preserveDiagnosticState {
            PoolConfiguration.clearDiagnosticHistory()

            for _ in 0..<25 {
                PoolConfiguration.current = config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid, method: .digitalTester)
            }

            XCTAssertEqual(PoolConfiguration.diagnosticHistoryEntries().count, 20,
                           "History must retain only the most recent ~20 events.")
        }
    }

    // 3. Recording a write diagnostic does not alter the persisted PoolConfiguration.
    func testWriteDiagnosticDoesNotAlterPersistedConfiguration() {
        preserveDiagnosticState {
            PoolConfiguration.clearDiagnosticHistory()
            let saved = config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid, method: .liquidDropKit)

            PoolConfiguration.current = saved

            let readBack = PoolConfiguration.current
            XCTAssertEqual(readBack.chlorinePreference, .liquidChlorine12_5)
            XCTAssertEqual(readBack.pHDecreaserPreference, .dryAcid)
            XCTAssertEqual(readBack.testMethod, .liquidDropKit)
            XCTAssertEqual(readBack.volumeGallons, 20_000)
        }
    }

    // 4. Clear events are recorded.
    func testClearEventIsRecorded() {
        preserveDiagnosticState {
            PoolConfiguration.clearDiagnosticHistory()
            PoolConfiguration.current = config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid, method: .liquidDropKit)

            PoolConfiguration.clearCurrent()

            XCTAssertNil(PoolConfiguration.persisted, "clearCurrent must remove the persisted config.")
            let entry = PoolConfiguration.diagnosticHistoryEntries().last!
            XCTAssertEqual(entry.eventType, .clear)
            XCTAssertTrue(entry.persistedExistedBefore)
            XCTAssertEqual(entry.beforeChlorine, ChlorinePreference.liquidChlorine12_5.rawValue)
            XCTAssertNil(entry.afterChlorine)
        }
    }

    // 5. A corrupt/failing diagnostic store cannot affect normal configuration behavior.
    func testDiagnosticStorageFailureDoesNotAffectConfiguration() {
        preserveDiagnosticState {
            // Corrupt the diagnostic history store so decoding it fails.
            UserDefaults.standard.set(Data("not valid diagnostic json".utf8), forKey: PoolConfiguration.diagnosticHistoryKey)
            let saved = config(chlorine: .liquidChlorine12_5, pHDecreaser: .dryAcid, method: .liquidDropKit)

            PoolConfiguration.current = saved

            // Real configuration behavior is unaffected by the broken diagnostic store...
            let readBack = PoolConfiguration.current
            XCTAssertEqual(readBack.chlorinePreference, .liquidChlorine12_5)
            XCTAssertEqual(readBack.pHDecreaserPreference, .dryAcid)
            XCTAssertEqual(readBack.testMethod, .liquidDropKit)
            // ...and the history recovers by starting fresh rather than throwing.
            XCTAssertEqual(PoolConfiguration.diagnosticHistoryEntries().count, 1)
        }
    }

    // MARK: - Isolation helper

    private func preserveDiagnosticState(_ body: () -> Void) {
        let keys = [
            PoolConfiguration.defaultsKey,
            PoolConfiguration.diagnosticHistoryKey,
            PoolConfiguration.hasCoverBackupKey,
            PoolConfiguration.usesRoboticCleanerBackupKey,
            PoolConfiguration.hasCoverExplicitChoiceKey,
            PoolConfiguration.usesRoboticCleanerExplicitChoiceKey
        ]
        let original = keys.reduce(into: [String: Any]()) { result, key in
            if let value = UserDefaults.standard.object(forKey: key) { result[key] = value }
        }
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        body()

        keys.forEach { key in
            if let value = original[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
