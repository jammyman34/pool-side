import XCTest
@testable import Pool_Side

/// Routine test-scope UX: FC & pH vs Full Test — model storage/defaults, FC & pH field scope, partial
/// (mixed-age) evidence carry-forward, scheduling-anchor behavior, contextual scope resolution, and the
/// Active/Completed row icon. Focused Checks remain a separate workflow.
final class RoutineTestScopeTests: ConfigIsolatedTestCase {

    private let day: TimeInterval = 24 * 60 * 60
    private var day0: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private func day(_ n: Double) -> Date { day0.addingTimeInterval(n * day) }

    private func fullTest(date: Date) -> PoolTest {
        let t = PoolTest(date: date, pH: 7.5, freeChlorine: 3, totalChlorine: 3,
                         totalAlkalinity: 120, calciumHardness: 350, cyanuricAcid: 60,
                         testMethod: .liquidDropKit)
        t.routineTestScope = .fullPanel
        return t
    }

    // 1. Existing/plain tests default to fullPanel.
    func testDefaultsToFullPanel() {
        let t = PoolTest(date: day0)
        XCTAssertEqual(t.routineTestScope, .fullPanel)
        XCTAssertEqual(t.routineTestScopeRaw, RoutineTestScope.fullPanel.rawValue)
    }

    // 2 & 3. Scope stores/round-trips for each type.
    func testScopeStoresPerType() {
        let fc = PoolTest(date: day0); fc.routineTestScope = .fcAndPH
        XCTAssertEqual(fc.routineTestScope, .fcAndPH)
        XCTAssertEqual(fc.routineTestScopeRaw, "fcAndPH")

        let full = PoolTest(date: day0); full.routineTestScope = .fullPanel
        XCTAssertEqual(full.routineTestScope, .fullPanel)
        XCTAssertEqual(full.routineTestScopeRaw, "fullPanel")
    }

    // 4. FC & pH scope measures only chlorine + pH (no TA/CH/CYA/salt/temperature).
    func testFCAndPHMeasuresOnlyChlorineAndPH() {
        let params = RoutineTestScope.fcAndPH.measuredChemistryParameters
        XCTAssertEqual(params, ["freeChlorine", "combinedChlorine", "totalChlorine", "pH"])
        for excluded in ["totalAlkalinity", "calciumHardness", "cyanuricAcid", "saltLevel", "temperature"] {
            XCTAssertFalse(params.contains(excluded), "\(excluded) must not be collected in FC & pH scope.")
        }
    }

    // 5. Full Test retains the complete field set.
    func testFullTestMeasuresCompletePanel() {
        let params = RoutineTestScope.fullPanel.measuredChemistryParameters
        for expected in ["freeChlorine", "combinedChlorine", "totalChlorine", "pH",
                         "totalAlkalinity", "calciumHardness", "cyanuricAcid", "saltLevel", "temperature"] {
            XCTAssertTrue(params.contains(expected), "Full Test must collect \(expected).")
        }
    }

    // 6, 7, 8. FC & pH carry-forward: old TA/CH/CYA keep ORIGINAL timestamps + values; FC/pH get the new
    // date; nothing becomes 0 or "measured today".
    func testFCAndPHCarryForwardPreservesMixedAgeEvidence() {
        let source = fullTest(date: day0) // all params measured day0
        let fresh = PoolTest(date: day(5), pH: 7.6, freeChlorine: 3.1, totalChlorine: 3.1,
                             totalAlkalinity: 120, calciumHardness: 350, cyanuricAcid: 60,
                             testMethod: .liquidDropKit)
        fresh.routineTestScope = .fcAndPH
        fresh.applyFCAndPHCarryForward(from: source)

        // Fresh chlorine/pH evidence stamped with the new test date.
        XCTAssertEqual(fresh.evidenceDate(for: "freeChlorine"), day(5))
        XCTAssertEqual(fresh.evidenceDate(for: "pH"), day(5))
        // Carried-forward chemistry retains its ORIGINAL measurement timestamp.
        XCTAssertEqual(fresh.evidenceDate(for: "totalAlkalinity"), day0)
        XCTAssertEqual(fresh.evidenceDate(for: "calciumHardness"), day0)
        XCTAssertEqual(fresh.evidenceDate(for: "cyanuricAcid"), day0)
        // Values are preserved, never zeroed/fabricated.
        XCTAssertEqual(fresh.totalAlkalinity, 120)
        XCTAssertEqual(fresh.calciumHardness, 350)
        XCTAssertEqual(fresh.cyanuricAcid, 60)
    }

    // 9. An FC & pH test does not reset the Day-7 Full Panel anchor.
    func testFCAndPHDoesNotResetAnchor() {
        let full = fullTest(date: day0)
        let fc = PoolTest(date: day(3), testMethod: .liquidDropKit); fc.routineTestScope = .fcAndPH

        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: fc, in: [full, fc], now: day(3))
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, day(7), "Full Panel stays anchored to the Day-0 full test.")
        XCTAssertEqual(schedule?.fcAndPH.recommendedDate, day(3))
    }

    // 10. A new Full Panel resets +3/+7.
    func testNewFullPanelResetsAnchor() {
        let older = fullTest(date: day0)
        let newer = fullTest(date: day(5))
        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: newer, in: [older, newer], now: day(5))
        XCTAssertEqual(schedule?.fcAndPH.recommendedDate, day(8))
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, day(12))
    }

    // 11 & 12. Global + and the scheduled pill preselect the firstUpcoming scope (same resolver).
    func testFirstUpcomingScopeResolution() {
        let full = fullTest(date: day0)
        let vm = PoolViewModel()
        // Before Day 3 the next routine test is FC & pH; between Day 3 and Day 7 it is the Full Panel.
        XCTAssertEqual(vm.firstUpcomingRoutineScope(for: full, in: [full], now: day(1)), .fcAndPH)
        XCTAssertEqual(vm.firstUpcomingRoutineScope(for: full, in: [full], now: day(4)), .fullPanel)
    }

    // 13. Editing preserves/locks the saved scope; new tests honor the preselected scope.
    func testResolvedScopeLocksEditingAndHonorsPreselection() {
        let fc = PoolTest(date: day0); fc.routineTestScope = .fcAndPH
        let full = PoolTest(date: day0); full.routineTestScope = .fullPanel
        XCTAssertEqual(AddTestView.resolvedScope(editing: fc, preselected: .fullPanel), .fcAndPH)
        XCTAssertEqual(AddTestView.resolvedScope(editing: full, preselected: .fcAndPH), .fullPanel)
        XCTAssertEqual(AddTestView.resolvedScope(editing: nil, preselected: .fcAndPH), .fcAndPH)
        XCTAssertEqual(AddTestView.resolvedScope(editing: nil, preselected: .fullPanel), .fullPanel)
    }

    // 14. DashboardWorkflowItem carries the scope + correct icon (Active/Completed rows only).
    func testDashboardWorkflowItemCarriesScopeAndIcon() {
        let full = fullTest(date: day0)
        let fc = PoolTest(date: day(1), testMethod: .liquidDropKit); fc.routineTestScope = .fcAndPH

        let vm = PoolViewModel()
        let (_, completed) = vm.dashboardWorkflows(from: [full, fc])
        let fullItem = completed.first { $0.rootTestID == full.id }
        let fcItem = completed.first { $0.rootTestID == fc.id }
        XCTAssertEqual(fullItem?.testScope, .fullPanel)
        XCTAssertEqual(fullItem?.testScope.iconName, "testtube.2")
        XCTAssertEqual(fcItem?.testScope, .fcAndPH)
        XCTAssertEqual(fcItem?.testScope.iconName, "drop.fill")
    }

    // 15. Focused Checks remain independent: they never anchor the routine schedule and are not a scope.
    func testFocusedChecksRemainIndependent() {
        let full = fullTest(date: day0)
        let focused = PoolTest(date: day(3), testMethod: .liquidDropKit)
        focused.isFocusedCheck = true
        focused.focusedCheckParameters = ["freeChlorine", "pH"]

        let vm = PoolViewModel()
        let schedule = vm.nextTestSchedule(for: focused, in: [full, focused], now: day(3))
        XCTAssertEqual(schedule?.fullPanel.recommendedDate, day(7),
                       "A focused check must not re-anchor the routine schedule.")

        // The routine scope model has no focused-check case; focused checks are their own workflow.
        XCTAssertEqual(Set(RoutineTestScope.allCases), [.fullPanel, .fcAndPH])
        let fc = PoolTest(date: day0); fc.routineTestScope = .fcAndPH
        XCTAssertFalse(fc.isFocusedCheck)
    }

    // 16. The custom segmented control exposes both options with their labels + icons, in FC & pH / Full order.
    func testSegmentedControlExposesBothLabelsAndIcons() {
        XCTAssertEqual(RoutineScopeSegmentedControl.orderedScopes, [.fcAndPH, .fullPanel])
        XCTAssertEqual(RoutineScopeSegmentedControl.orderedScopes.map(\.displayName), ["FC & pH", "Full Test"])
        XCTAssertEqual(RoutineScopeSegmentedControl.orderedScopes.map(\.iconName), ["drop.fill", "testtube.2"])
    }

    // 17. Selection behavior: an enabled tap switches scope; an edit-locked (disabled) tap keeps the current scope.
    func testSegmentedControlSelectionAndEditLock() {
        // New (unsaved) test: tapping switches scope.
        XCTAssertEqual(
            RoutineScopeSegmentedControl.nextSelection(current: .fullPanel, tapped: .fcAndPH, isDisabled: false),
            .fcAndPH)
        // Editing a saved test: the stored scope is locked, so a tap is ignored.
        XCTAssertEqual(
            RoutineScopeSegmentedControl.nextSelection(current: .fcAndPH, tapped: .fullPanel, isDisabled: true),
            .fcAndPH)
    }
}
