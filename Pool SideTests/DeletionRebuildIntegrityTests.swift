import XCTest
import SwiftData
@testable import Pool_Side

/// Increment 3 — deletion/edit/rebuild integrity: no stale plans, orphaned Checks, dangling
/// checkResultTestID links, false completed verification, or orphan notifications.
@MainActor
final class DeletionRebuildIntegrityTests: ConfigIsolatedTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func container() throws -> ModelContainer {
        try ModelContainer(for: PoolTest.self, Treatment.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func vm(_ spy: NotificationSchedulingSpy) -> PoolViewModel {
        let v = PoolViewModel(); v.saveConfig(config); v.notificationSchedulerOverride = spy; return v
    }

    private func poolTest(_ mc: ModelContext, date: Date = Date(), pH: Double = 7.8) -> PoolTest {
        let t = PoolTest(date: date, pH: pH, freeChlorine: 6, totalChlorine: 6,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
        mc.insert(t)
        return t
    }

    private func acid(on t: PoolTest, completed: Bool = false, at: Date? = nil) -> Treatment {
        Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20, unit: "fl oz",
                  instructions: "", urgency: .recommended, isCompleted: completed, completedAt: completed ? (at ?? Date()) : nil,
                  targetParameter: "pH", sortOrder: 1, expectedEffectParameter: "pH", expectedDelta: -0.4,
                  effectDelayHours: 4, poolTest: t)
    }

    private func check(after parent: Treatment, on t: PoolTest) -> Treatment {
        let c = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: parent.sortOrder + 1)!
        t.treatments.append(c)
        return c
    }

    // A/B/C. Delete latest test with active treatment / waiting or ready Check: cancels notifications,
    // removes rows, falls back correctly.
    func testDeleteLatestWithActiveWorkflow() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let older = poolTest(mc, date: Date().addingTimeInterval(-86_400), pH: 7.4)
        let latest = poolTest(mc, date: Date(), pH: 7.9)
        let a = acid(on: latest); let c = check(after: a, on: latest)
        await v.completeTreatment(a, in: [older, latest], modelContext: mc)
        XCTAssertNotNil(c.checkReminderNotificationIdentifier)

        try await v.deletePoolTestAndRefreshHistory(latest, allTests: [older, latest], modelContext: mc)

        let remaining = try mc.fetch(FetchDescriptor<PoolTest>())
        XCTAssertFalse(remaining.contains { $0.id == latest.id })
        XCTAssertTrue(remaining.contains { $0.id == older.id })
        XCTAssertTrue(spy.didCancel(c.checkReminderNotificationIdentifier) || c.checkReminderNotificationIdentifier == nil)
        // No orphan Treatments remain from the deleted test.
        let treatments = try mc.fetch(FetchDescriptor<Treatment>())
        XCTAssertFalse(treatments.contains { $0.id == c.id }, "Orphaned Check must be cascade-deleted.")
    }

    // E. A later full test never auto-completes a pending Check in an older workflow, and deleting that
    //    later test leaves the Check untouched. Checks are user-completed only (no full-test supersession).
    func testLaterFullTestNeverCompletesOrDisturbsOlderCheck() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let root = poolTest(mc, date: completedAt.addingTimeInterval(-3600), pH: 7.9)
        let a = acid(on: root, completed: true, at: completedAt); let c = check(after: a, on: root)
        // A later full test that measures pH after the Check's due time must NOT complete the Check.
        let later = poolTest(mc, date: completedAt.addingTimeInterval(5 * 3600), pH: 7.4)
        XCTAssertFalse(c.isCompleted, "Logging a later full test never completes a pending Check.")
        XCTAssertNil(c.checkResultTestID)

        try await v.deletePoolTestAndRefreshHistory(later, allTests: [root, later], modelContext: mc)

        XCTAssertFalse(c.isCompleted, "Deleting an unrelated later test leaves the pending Check pending.")
        XCTAssertNil(c.checkResultTestID)
    }

    // F. Delete originating root test → entire workflow removed, notifications cancelled, no orphans.
    func testDeleteOriginatingRootRemovesEntireWorkflow() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let root = poolTest(mc, date: Date(), pH: 7.9)
        let a = acid(on: root); let c = check(after: a, on: root)
        await v.completeTreatment(a, in: [root], modelContext: mc)

        try await v.deletePoolTestAndRefreshHistory(root, allTests: [root], modelContext: mc)

        let tests = try mc.fetch(FetchDescriptor<PoolTest>())
        let treatments = try mc.fetch(FetchDescriptor<Treatment>())
        XCTAssertTrue(tests.isEmpty)
        XCTAssertTrue(treatments.isEmpty, "Root deletion cascade-removes its whole workflow.")
        _ = c
    }

    // G. Delete a middle historical test → later plans rebuild from remaining history (no crash, coherent).
    func testDeleteMiddleTestRebuildsLaterPlans() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let t1 = poolTest(mc, date: Date().addingTimeInterval(-2 * 86_400), pH: 7.5)
        let t2 = poolTest(mc, date: Date().addingTimeInterval(-1 * 86_400), pH: 7.6)
        let t3 = poolTest(mc, date: Date(), pH: 7.9)
        await v.generateRecommendations(for: t3, recentTests: [t2, t1], modelContext: mc)

        try await v.deletePoolTestAndRefreshHistory(t2, allTests: [t1, t2, t3], modelContext: mc)

        let remaining = try mc.fetch(FetchDescriptor<PoolTest>())
        XCTAssertEqual(Set(remaining.map(\.id)), Set([t1.id, t3.id]))
    }

    // J/K. Delete latest test → Dashboard score/sections fall back to the next valid state.
    func testDeleteLatestFallsBackDashboard() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let older = poolTest(mc, date: Date().addingTimeInterval(-86_400), pH: 7.4)
        let latest = poolTest(mc, date: Date(), pH: 7.9)
        try await v.deletePoolTestAndRefreshHistory(latest, allTests: [older, latest], modelContext: mc)

        let remaining = try mc.fetch(FetchDescriptor<PoolTest>())
        let workflows = v.dashboardWorkflows(from: remaining)
        XCTAssertFalse((workflows.active + workflows.completed).contains { $0.rootTestID == latest.id })
        XCTAssertTrue((workflows.active + workflows.completed).contains { $0.rootTestID == older.id })
    }

    // L. Deleting the last test replaces (cancels) the routine Next Pool Test reminder.
    func testDeleteLastTestCancelsRoutineReminder() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let only = poolTest(mc, date: Date(), pH: 7.9)
        try await v.deletePoolTestAndRefreshHistory(only, allTests: [only], modelContext: mc)
        XCTAssertTrue(spy.didCancelNextPoolTest, "With no remaining tests, the routine reminder is cancelled.")
    }

    // H. Editing chemistry on an active root test regenerates unfinished recommendations from new evidence.
    func testEditingChemistryRegeneratesUnfinishedRecommendations() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let t = PoolTest(date: Date(), pH: 7.9, freeChlorine: 8, totalChlorine: 8, totalAlkalinity: 100,
                         calciumHardness: 350, cyanuricAcid: 60, testMethod: .liquidDropKit)
        mc.insert(t)
        await v.generateRecommendations(for: t, recentTests: [], modelContext: mc)
        XCTAssertTrue(t.treatments.contains { $0.targetParameter == "pH" && $0.isAcidTreatment && $0.amount > 0 })

        // Edit the reading to an ideal pH and regenerate (evidence replacement).
        t.pH = 7.4
        await v.generateRecommendations(for: t, recentTests: [], modelContext: mc, replacingCompletedPlan: false)
        XCTAssertFalse(t.treatments.contains { $0.targetParameter == "pH" && $0.isAcidTreatment && !$0.isCompleted && !$0.isSkipped && $0.amount > 0 },
                       "Unfinished pH recommendation is removed once the edited evidence is in range.")
    }

    // Q. Persistence/relaunch after deletion: a pending Check stays pending across a fresh context load,
    //    and deleting an unrelated later test never completes it.
    func testRelaunchAfterDeletionYieldsRepairedState() async throws {
        let ctn = try container()
        let mc = ModelContext(ctn)
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let root = poolTest(mc, date: completedAt.addingTimeInterval(-3600), pH: 7.9)
        let a = acid(on: root, completed: true, at: completedAt); let c = check(after: a, on: root)
        let checkID = c.id
        let later = poolTest(mc, date: completedAt.addingTimeInterval(5 * 3600), pH: 7.4)
        try await v.deletePoolTestAndRefreshHistory(later, allTests: [root, later], modelContext: mc)
        try mc.save()

        let fresh = ModelContext(ctn)
        let reloaded = try fresh.fetch(FetchDescriptor<Treatment>()).first { $0.id == checkID }
        XCTAssertEqual(reloaded?.isCompleted, false)
        XCTAssertNil(reloaded?.checkResultTestID)
    }

    // R. One-time repair reopens Checks auto-completed by a *different* test (old supersession), while
    //    leaving a user's own completion (checkResultTestID == its own test) untouched. Idempotent.
    func testReopenAutoCompletedChecksRepairsOnlySupersededOnes() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let root = poolTest(mc, date: Date().addingTimeInterval(-3600), pH: 7.9)
        let a = acid(on: root, completed: true)
        let stale = check(after: a, on: root)   // simulates an old full-test supersession auto-completion
        let legit = check(after: a, on: root)   // simulates a genuine user-entered result
        let other = poolTest(mc, date: Date(), pH: 7.4)
        stale.isCompleted = true; stale.completedAt = Date(); stale.checkResultTestID = other.id
        legit.isCompleted = true; legit.completedAt = Date(); legit.checkResultTestID = root.id

        let reopened = v.reopenAutoCompletedChecks(in: [root, other], modelContext: mc)

        XCTAssertEqual(reopened, 1)
        XCTAssertFalse(stale.isCompleted, "A Check completed by a different test is reopened.")
        XCTAssertNil(stale.checkResultTestID)
        XCTAssertTrue(legit.isCompleted, "A user's own completion is preserved.")
        XCTAssertEqual(legit.checkResultTestID, root.id)

        // Idempotent: a second run finds nothing to repair.
        XCTAssertEqual(v.reopenAutoCompletedChecks(in: [root, other], modelContext: mc), 0)
    }
}
