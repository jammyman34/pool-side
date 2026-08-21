import XCTest
import SwiftData
@testable import Pool_Side

/// Increment 1 — defensive completed/superseded focused-Check state guards at the ViewModel boundary.
@MainActor
final class CompletedCheckGuardTests: ConfigIsolatedTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func vm() -> PoolViewModel {
        let v = PoolViewModel(); v.saveConfig(config); return v
    }

    private func poolTest(pH: Double = 7.8) -> PoolTest {
        PoolTest(date: Date(), pH: pH, freeChlorine: 6, totalChlorine: 6,
                 totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
    }

    private func acid(on t: PoolTest, completed: Bool = false) -> Treatment {
        let a = Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20, unit: "fl oz",
                          instructions: "", urgency: .recommended, isCompleted: completed,
                          completedAt: completed ? Date() : nil, targetParameter: "pH", sortOrder: 1,
                          expectedEffectParameter: "pH", expectedDelta: -0.4, effectDelayHours: 4, poolTest: t)
        return a
    }

    private func check(after parent: Treatment, on t: PoolTest) -> Treatment {
        let c = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: parent.sortOrder + 1)!
        t.treatments.append(c)
        return c
    }

    // 1. Unresolved focused Check can be skipped.
    func testUnresolvedCheckCanBeSkipped() throws {
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        let result = vm().skipTreatment(c)
        XCTAssertEqual(result, .applied)
        XCTAssertTrue(c.isSkipped)
        XCTAssertFalse(c.isCompleted)
    }

    // 2. Skipped unresolved Check can be restored.
    func testSkippedUnresolvedCheckCanBeRestored() throws {
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        let v = vm()
        v.skipTreatment(c)
        XCTAssertEqual(v.restoreTreatment(c), .applied)
        XCTAssertFalse(c.isSkipped)
        XCTAssertFalse(c.isCompleted)
    }

    // 3. Completed focused Check rejects Skip and is not un-completed.
    func testCompletedCheckRejectsSkip() throws {
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        c.isCompleted = true; c.completedAt = Date(); c.checkResultTestID = t.id
        let result = vm().skipTreatment(c)
        XCTAssertEqual(result, .rejectedCompleted)
        XCTAssertTrue(c.isCompleted, "A completed Check must never be un-completed by Skip.")
        XCTAssertFalse(c.isSkipped)
    }

    // 4. Completed focused Check rejects Restore.
    func testCompletedCheckRejectsRestore() throws {
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        c.isCompleted = true; c.completedAt = Date(); c.checkResultTestID = t.id
        XCTAssertEqual(vm().restoreTreatment(c), .rejectedCompleted)
        XCTAssertTrue(c.isCompleted)
    }

    // 7. Generic completeTreatment cannot complete a Check.
    func testGenericCompletionCannotCompleteCheck() async throws {
        let ctx = try context()
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t); ctx.insert(t)
        await vm().completeTreatment(c, in: [t], modelContext: ctx)
        XCTAssertFalse(c.isCompleted)
    }

    // 8 & 9. Parent skip/restore does not alter a completed Check.
    func testParentSkipRestoreDoesNotAlterCompletedCheck() throws {
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        c.isCompleted = true; c.completedAt = Date(); c.checkResultTestID = t.id
        let v = vm()
        v.skipTreatment(a)   // skip parent
        XCTAssertTrue(c.isCompleted, "Parent skip must not un-complete a completed Check.")
        XCTAssertFalse(c.isSkipped)
        v.restoreTreatment(a)
        XCTAssertTrue(c.isCompleted, "Parent restore must not alter a completed Check.")
    }

    // 10. A rejected transition leaves persisted state unchanged across a save/refetch.
    func testRejectedTransitionLeavesPersistedStateUnchanged() throws {
        let container = try ModelContainer(for: PoolTest.self, Treatment.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let t = poolTest(); let a = acid(on: t, completed: true); let c = check(after: a, on: t)
        c.isCompleted = true; c.completedAt = Date(); c.checkResultTestID = t.id
        let checkID = c.id
        ctx.insert(t); try ctx.save()

        _ = vm().skipTreatment(c)   // rejected
        try? ctx.save()

        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(FetchDescriptor<Treatment>()).first { $0.id == checkID }
        XCTAssertEqual(reloaded?.isCompleted, true)
        XCTAssertEqual(reloaded?.isSkipped, false)
    }

    // 11. UI and ViewModel transition rules agree: the card's gate uses the same rejection helper.
    func testUIAndViewModelRulesAgree() throws {
        let t = poolTest(); let a = acid(on: t, completed: true)
        let unresolved = check(after: a, on: t)
        let v = vm()
        XCTAssertNil(v.focusedCheckTransitionRejection(unresolved), "Unresolved → gesture enabled.")

        let completed = check(after: a, on: t)
        completed.isCompleted = true; completed.checkResultTestID = t.id
        XCTAssertNotNil(v.focusedCheckTransitionRejection(completed), "Completed → gesture disabled.")

        // Parent-skipped cascade → inapplicable.
        let t2 = poolTest(); let a2 = acid(on: t2); let dependent = check(after: a2, on: t2)
        v.skipTreatment(a2)
        XCTAssertEqual(v.focusedCheckTransitionRejection(dependent), .rejectedInapplicable)
    }
}
