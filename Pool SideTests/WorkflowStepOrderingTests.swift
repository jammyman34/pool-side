import XCTest
import SwiftData
@testable import Pool_Side

/// Regression: the Treatment Plan must list steps in the order the user performs them — each treatment
/// immediately followed by its focused Check — rather than all treatments first and all Checks last.
/// Guards against the sortOrder collision that occurred when a freshly created Check was auto-linked into
/// the test's treatments (via the SwiftData inverse relationship) before its sortOrder was assigned.
@MainActor
final class WorkflowStepOrderingTests: ConfigIsolatedTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func container() throws -> ModelContainer {
        try ModelContainer(for: PoolTest.self, Treatment.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testChlorineAndAcidChecksInterleaveWithTheirParents() async throws {
        let mc = ModelContext(try container())
        let v = PoolViewModel()
        v.saveConfig(config)
        v.notificationSchedulerOverride = NotificationSchedulingSpy()

        // Low FC (needs chlorine) + high pH 7.9 (needs dry acid, blocks swimming → each gets a Check).
        let t = PoolTest(date: Date(), pH: 7.9, freeChlorine: 1, totalChlorine: 1.2,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
        mc.insert(t)

        await v.generateRecommendations(for: t, recentTests: [], modelContext: mc)

        let steps = TreatmentWorkflowEngine().workflowSteps(
            from: t.treatments.filter { !$0.isWatchlistItem }
        )
        let signature = steps.map { $0.isFocusedCheckStep ? "check:\($0.targetParameter)" : "treat:\($0.targetParameter)" }
        XCTAssertEqual(
            signature,
            ["treat:freeChlorine", "check:freeChlorine", "treat:pH", "check:pH"],
            "Each treatment must be immediately followed by its own Check, in performance order."
        )

        // A focused Check must sort directly after its parent treatment (no shared/duplicated sortOrder).
        for check in steps where check.isFocusedCheckStep {
            let parent = steps.first { $0.id == check.parentTreatmentID }
            XCTAssertNotNil(parent)
            XCTAssertEqual(check.sortOrder, (parent?.sortOrder ?? -99) + 1)
        }
    }
}
