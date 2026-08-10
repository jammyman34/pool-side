import XCTest
import SwiftData
@testable import Pool_Side

/// Watchlist items are observations, not treatments: they never carry repeat-suppression and never appear in
/// the engine repeat-deferral ("Repeat … dosing is deferred …") pipeline.
@MainActor
final class WatchlistContextualizationTests: XCTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func container() throws -> ModelContainer {
        try ModelContainer(for: PoolTest.self, Treatment.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // A generated advisory (e.g. "Maintain Higher FC for Current CYA" at CYA 60) must not carry a
    // repeat-suppression timestamp.
    func testGeneratedAdvisoryCarriesNoRepeatSuppression() async throws {
        let mc = ModelContext(try container())
        let vm = PoolViewModel(); vm.saveConfig(config)
        let test = PoolTest(date: Date(), pH: 7.4, freeChlorine: 6, totalChlorine: 6,
                            totalAlkalinity: 90, calciumHardness: 300, cyanuricAcid: 60, testMethod: .liquidDropKit)
        mc.insert(test)
        await vm.generateRecommendations(for: test, recentTests: [], modelContext: mc)

        let advisories = test.treatments.filter { $0.isWatchlistItem }
        XCTAssertFalse(advisories.isEmpty, "CYA 60 should surface at least one advisory/watchlist item.")
        for advisory in advisories {
            XCTAssertNil(advisory.doNotRepeatBefore,
                         "Advisory '\(advisory.chemicalName)' must never carry a repeat-suppression timestamp.")
        }
    }

    // The repeat-deferral section reports real corrective treatments only — never advisory observations,
    // so "Repeat Monitor pH Trend dosing is deferred …" style messaging can never appear.
    func testEngineDeferralsExcludesAdvisoryItems() {
        let future = Date().addingTimeInterval(72 * 3600)
        let advisory = Treatment(
            chemicalName: "Monitor pH Trend", actionDescription: "", amount: 0, unit: "",
            instructions: "", urgency: .advisory, targetParameter: "totalAlkalinity",
            doNotRepeatBefore: future
        )
        let realTreatment = Treatment(
            chemicalName: "Muriatic Acid", actionDescription: "", amount: 20, unit: "fl oz",
            instructions: "", urgency: .recommended, targetParameter: "pH",
            expectedEffectParameter: "pH", doNotRepeatBefore: future
        )

        let output = ExternalReviewExportBuilder.engineDeferralsSection(allTreatments: [advisory, realTreatment])

        XCTAssertFalse(output.contains("Monitor pH Trend"),
                       "Advisory items must never appear in the repeat-deferral section.")
        XCTAssertTrue(output.contains("Muriatic Acid"),
                      "Real corrective treatments still report their repeat-suppression window.")
    }
}
