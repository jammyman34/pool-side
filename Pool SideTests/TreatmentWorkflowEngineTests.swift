import XCTest
@testable import Pool_Side

final class TreatmentWorkflowEngineTests: XCTestCase {
    func testOptionalChlorineCreatesOptionalFocusedCheckWithoutChangingRoutineNextPoolTest() {
        let testDate = Date(timeIntervalSince1970: 1_800_100_000)
        let test = PoolTest(
            date: testDate,
            pH: 7.6,
            freeChlorine: 2.5,
            totalChlorine: 2.5,
            totalAlkalinity: 160,
            calciumHardness: 350,
            cyanuricAcid: 60,
            waterClarityAssessment: .clear,
            visibleAlgaeAssessment: .absent
        )
        let treatment = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Maintenance top-off toward 3 ppm",
            amount: 0.1,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .optional,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        test.treatments = [treatment]

        let check = TreatmentWorkflowEngine().makeCheckStep(after: treatment, sortOrder: 2)
        XCTAssertEqual(check?.chemicalName, "Check FC & CC")
        XCTAssertEqual(check?.checkParameters, ["freeChlorine", "combinedChlorine"])
        XCTAssertEqual(check?.urgency, .optional)
        XCTAssertEqual(check?.workflowStepKind, .focusedCheck)

        // The optional Focused Check does not change routine testing: the routine cadence is owned by the
        // SSOT and anchored to the Full Test Panel (FC & pH +3d, Full Panel +7d), independent of the Check.
        let schedule = NextTestRecommendationEngine().routineSchedule(mostRecentFullTestDate: test.date)
        XCTAssertEqual(schedule.fcAndPH.recommendedDate, test.date.addingTimeInterval(3 * 24 * 3600))
        XCTAssertEqual(schedule.fullPanel.recommendedDate, test.date.addingTimeInterval(7 * 24 * 3600))
    }

    func testLowFCCheckWaitActivatesFromTreatmentCompletionTime() {
        let completedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let test = PoolTest(date: completedAt.addingTimeInterval(-600), freeChlorine: 1.5, totalChlorine: 1.5, cyanuricAcid: 60)
        let treatment = Treatment(
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Raise free chlorine toward 3 ppm",
            amount: 0.5,
            unit: "gal",
            instructions: "Add chlorine.",
            urgency: .needsAttention,
            isCompleted: true,
            completedAt: completedAt,
            targetParameter: "freeChlorine",
            sortOrder: 1,
            effectDelayHours: 1,
            poolTest: test
        )
        let check = TreatmentWorkflowEngine().makeCheckStep(after: treatment, sortOrder: 2)!
        test.treatments = [treatment, check]

        let engine = TreatmentWorkflowEngine()
        XCTAssertEqual(engine.availableDate(for: check, in: test.treatments), completedAt.addingTimeInterval(3600))
        XCTAssertEqual(engine.state(for: check, in: test.treatments, evaluationDate: completedAt.addingTimeInterval(1800)), .waiting(availableAt: completedAt.addingTimeInterval(3600)))
        XCTAssertEqual(engine.state(for: check, in: test.treatments, evaluationDate: completedAt.addingTimeInterval(3700)), .current)
    }

    // MARK: - Bug 1 + 2: a required Check gates every later workflow step

    /// Builds the dogfood workflow: chlorine (parent) → required "Check FC & CC" → dry acid (downstream).
    /// `chlorineCompletedAt == nil` leaves the parent pending; a date marks it completed so the Check gains
    /// its `availableDate` (parent completion + 60 min circulation for liquid chlorine).
    private func chlorineCheckAcidWorkflow(
        chlorineCompletedAt: Date?,
        checkOptional: Bool = false
    ) -> (chlorine: Treatment, check: Treatment, acid: Treatment, steps: [Treatment]) {
        let test = PoolTest(date: Date(timeIntervalSince1970: 1_800_000_000), pH: 7.8,
                            freeChlorine: 1, totalChlorine: 1, totalAlkalinity: 170,
                            calciumHardness: 380, cyanuricAcid: 52)
        let chlorine = Treatment(
            chemicalName: "Liquid Chlorine 12.5%", actionDescription: "Raise free chlorine",
            amount: 0.75, unit: "gal", instructions: "Add chlorine.",
            urgency: .needsAttention, isCompleted: chlorineCompletedAt != nil,
            completedAt: chlorineCompletedAt, targetParameter: "freeChlorine",
            sortOrder: 0, effectDelayHours: 1, poolTest: test
        )
        let check = TreatmentWorkflowEngine().makeCheckStep(after: chlorine, sortOrder: 1)!
        if checkOptional { check.urgency = .optional }
        let acid = Treatment(
            chemicalName: "Dry Acid", actionDescription: "Lower pH",
            amount: 1.2, unit: "lbs", instructions: "Add dry acid.",
            urgency: .needsAttention, targetParameter: "pH",
            sortOrder: 2, effectDelayHours: 4, poolTest: test
        )
        test.treatments = [chlorine, check, acid]
        return (chlorine, check, acid, [chlorine, check, acid])
    }

    // Ordering comes from canonical sortOrder: parent → required Check → downstream treatment.
    func testRequiredCheckIsOrderedBetweenChlorineParentAndDownstreamAcid() {
        let engine = TreatmentWorkflowEngine()
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: nil)

        // Even fed out of order, the engine renders them chlorine → check → acid.
        let ordered = engine.workflowSteps(from: [wf.acid, wf.check, wf.chlorine])
        XCTAssertEqual(ordered.map(\.id), [wf.chlorine.id, wf.check.id, wf.acid.id])
        XCTAssertTrue(wf.chlorine.sortOrder < wf.check.sortOrder)
        XCTAssertTrue(wf.check.sortOrder < wf.acid.sortOrder)
        XCTAssertEqual(wf.check.parentTreatmentID, wf.chlorine.id)
    }

    // While the parent is still pending, the parent itself gates the downstream step.
    func testDownstreamAcidNotActionableWhileChlorineParentPending() {
        let engine = TreatmentWorkflowEngine()
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: nil)
        XCTAssertEqual(engine.state(for: wf.chlorine, in: wf.steps), .current)
        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps), .upcoming,
                       "Acid must not be current while the chlorine parent is still pending.")
    }

    // Bug 2: once the parent completes, the required Check gates the acid WHILE IT IS STILL WAITING.
    func testDownstreamAcidNotActionableWhileRequiredCheckIsWaiting() {
        let engine = TreatmentWorkflowEngine()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: t0)
        let whileWaiting = t0.addingTimeInterval(30 * 60) // before the 60-min circulation elapses

        XCTAssertEqual(engine.state(for: wf.check, in: wf.steps, evaluationDate: whileWaiting),
                       .waiting(availableAt: t0.addingTimeInterval(3600)))
        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps, evaluationDate: whileWaiting), .upcoming,
                       "Acid must remain gated while the required Check is still waiting to become available.")
    }

    // Bug 2: the acid stays gated once the Check is available/due but not yet recorded.
    func testDownstreamAcidNotActionableWhileRequiredCheckAvailableButIncomplete() {
        let engine = TreatmentWorkflowEngine()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: t0)
        let whenDue = t0.addingTimeInterval(90 * 60) // after the circulation elapses

        XCTAssertEqual(engine.state(for: wf.check, in: wf.steps, evaluationDate: whenDue), .current)
        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps, evaluationDate: whenDue), .upcoming,
                       "Acid must remain gated while the available Check is still unrecorded.")
    }

    // Bug 2: recording the Check unblocks the downstream acid.
    func testCompletingRequiredCheckMakesDownstreamAcidActionable() {
        let engine = TreatmentWorkflowEngine()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: t0)
        wf.check.isCompleted = true
        wf.check.completedAt = t0.addingTimeInterval(90 * 60)

        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps, evaluationDate: t0.addingTimeInterval(95 * 60)),
                       .current, "Acid becomes actionable once the required Check is recorded.")
    }

    // Skipping the required Check also releases the downstream step (skip/restore still work).
    func testSkippingRequiredCheckMakesDownstreamAcidActionable() {
        let engine = TreatmentWorkflowEngine()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: t0)
        wf.check.isSkipped = true
        wf.check.skippedAt = t0.addingTimeInterval(30 * 60)

        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps, evaluationDate: t0.addingTimeInterval(30 * 60)),
                       .current, "A skipped Check no longer gates the downstream step.")
    }

    // Discretionary (optional) Checks must NOT gate downstream treatments.
    func testOptionalCheckDoesNotGateDownstreamAcid() {
        let engine = TreatmentWorkflowEngine()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        let wf = chlorineCheckAcidWorkflow(chlorineCompletedAt: t0, checkOptional: true)
        let whileWaiting = t0.addingTimeInterval(30 * 60)

        XCTAssertEqual(engine.state(for: wf.acid, in: wf.steps, evaluationDate: whileWaiting), .current,
                       "An optional/discretionary Check must not gate the downstream treatment.")
    }

    func testFocusedCheckEvidenceDatesOnlyUpdateMeasuredParameters() {
        let originalDate = Date(timeIntervalSince1970: 1_800_100_000)
        let measuredAt = originalDate.addingTimeInterval(3600)
        let test = PoolTest(
            date: originalDate,
            pH: 7.6,
            freeChlorine: 4.0,
            totalChlorine: 4.0,
            totalAlkalinity: 160,
            calciumHardness: 350,
            cyanuricAcid: 60
        )

        test.freeChlorine = 6.5
        test.totalChlorine = 6.5
        test.freeChlorineMeasuredAt = measuredAt
        test.totalChlorineMeasuredAt = measuredAt

        XCTAssertEqual(test.evidenceDate(for: "freeChlorine"), measuredAt)
        XCTAssertEqual(test.evidenceDate(for: "combinedChlorine"), measuredAt)
        XCTAssertEqual(test.evidenceDate(for: "pH"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "totalAlkalinity"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "calciumHardness"), originalDate)
        XCTAssertEqual(test.evidenceDate(for: "cyanuricAcid"), originalDate)
    }
}
