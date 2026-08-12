import XCTest
import SwiftData
@testable import Pool_Side

/// A focused Check is created ONLY when verification is actually required — swimming is blocked until the
/// treatment is verified, or the dose was staged/capped. Recommended maintenance adds on an already-safe
/// pool get no Check; completing them schedules a wait-complete "safe to swim" reminder instead, while
/// skipping schedules nothing.
@MainActor
final class FocusedCheckGatingTests: XCTestCase {

    private let config = PoolConfiguration(volumeGallons: 32_583, surfaceType: .plaster, isSaltwater: false)

    private func container() throws -> ModelContainer {
        try ModelContainer(for: PoolTest.self, Treatment.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func vm(_ spy: NotificationSchedulingSpy) -> PoolViewModel {
        let v = PoolViewModel(); v.saveConfig(config); v.notificationSchedulerOverride = spy; return v
    }

    private func poolTest(_ mc: ModelContext, pH: Double, fc: Double = 4.5, cc: Double = 0) -> PoolTest {
        let t = PoolTest(date: Date(), pH: pH, freeChlorine: fc, totalChlorine: fc + cc,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 55, testMethod: .liquidDropKit)
        mc.insert(t)
        return t
    }

    private func treatment(param: String, name: String, capped: Bool = false, on test: PoolTest) -> Treatment {
        Treatment(chemicalName: name, actionDescription: "", amount: 1, unit: "gal",
                  wasDoseCapped: capped, instructions: "", urgency: .recommended,
                  targetParameter: param, expectedEffectParameter: param, poolTest: test)
    }

    // MARK: - Engine gate

    private func reason(_ t: Treatment) -> TreatmentWorkflowEngine.FocusedCheckReason {
        TreatmentWorkflowEngine().focusedCheckReason(for: t, config: config)
    }

    func testSafeChlorineTopOffRequiresNoCheck() throws {
        let mc = ModelContext(try container())
        let test = poolTest(mc, pH: 7.4, fc: 4.5, cc: 0)
        XCTAssertEqual(reason(treatment(param: "freeChlorine", name: "Liquid Chlorine 12.5%", on: test)), .none,
                       "A safe FC top-off (above readiness minimum, CC 0) needs no Check.")
    }

    func testSwimSafePHRangeRequiresNoCheck() throws {
        // Approved swim range is 7.0–7.8 inclusive: none of these require a Check (7.7 is a Recommended
        // optimization only).
        let mc = ModelContext(try container())
        for pH in [7.0, 7.1, 7.6, 7.7, 7.8] {
            XCTAssertEqual(reason(treatment(param: "pH", name: "Dry Acid", on: poolTest(mc, pH: pH))), .none,
                           "pH \(pH) is inside the approved swim range.")
        }
    }

    func testPHOutsideSwimRangeRequiresSwimSafetyCheck() throws {
        let mc = ModelContext(try container())
        XCTAssertEqual(reason(treatment(param: "pH", name: "Dry Acid", on: poolTest(mc, pH: 8.1))), .swimSafety,
                       "pH above 7.8 blocks swimming.")
        XCTAssertEqual(reason(treatment(param: "pH", name: "Soda Ash", on: poolTest(mc, pH: 6.8))), .swimSafety,
                       "pH below 7.0 blocks swimming.")
    }

    func testCappedOptimizationDoseOnSafePoolRequiresNoCheck() throws {
        // A dose capped toward an optimization target does NOT force a Check when the pool is swim-safe and
        // the parameter isn't at a corrective extreme. (This is Justin's real pH-7.7 capped acid case.)
        let mc = ModelContext(try container())
        XCTAssertEqual(reason(treatment(param: "pH", name: "Dry Acid", capped: true, on: poolTest(mc, pH: 7.7))), .none)
    }

    func testCorrectiveCalciumOnPlasterRequiresProtectionCheck() throws {
        // Calcium never blocks swimming, but a corrective extreme on plaster must be verified before
        // repeating so the correction does not harm the surface.
        let mc = ModelContext(try container())
        let test = PoolTest(date: Date(), pH: 7.4, freeChlorine: 4.5, totalChlorine: 4.5,
                            totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 55, testMethod: .liquidDropKit)
        mc.insert(test)
        XCTAssertEqual(reason(treatment(param: "calciumHardness", name: "Calcium Chloride", on: test)),
                       .poolOrEquipmentProtection)
    }

    func testStagedCorrectiveCalciumRequiresBeforeNextTreatment() throws {
        // A staged/capped corrective calcium dose must be re-measured before another application.
        let mc = ModelContext(try container())
        let test = PoolTest(date: Date(), pH: 7.4, freeChlorine: 4.5, totalChlorine: 4.5,
                            totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 55, testMethod: .liquidDropKit)
        mc.insert(test)
        XCTAssertEqual(reason(treatment(param: "calciumHardness", name: "Calcium Chloride", capped: true, on: test)),
                       .requiredBeforeNextTreatment)
    }

    func testMildCalciumRequiresNoCheck() throws {
        let mc = ModelContext(try container())
        let test = PoolTest(date: Date(), pH: 7.4, freeChlorine: 4.5, totalChlorine: 4.5,
                            totalAlkalinity: 100, calciumHardness: 240, cyanuricAcid: 55, testMethod: .liquidDropKit)
        mc.insert(test)
        XCTAssertEqual(reason(treatment(param: "calciumHardness", name: "Calcium Chloride", on: test)), .none,
                       "Calcium within the ideal band is not a corrective extreme.")
    }

    // MARK: - Plan assembly (the dogfooding case)

    func testAlreadySafePoolGeneratesNoFocusedChecks() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        // Real dogfooding pool: FC above readiness minimum, CC 0, pH swim-safe. Any generated treatments are
        // recommended optimizations only — neither should force a purple Check.
        let test = PoolTest(date: Date(), pH: 7.7, freeChlorine: 4.5, totalChlorine: 4.5,
                            totalAlkalinity: 170, calciumHardness: 370, cyanuricAcid: 55, testMethod: .liquidDropKit)
        mc.insert(test)
        await v.generateRecommendations(for: test, recentTests: [], modelContext: mc)

        let checks = test.treatments.filter { $0.isFocusedCheckStep }
        let checkSummary = checks.map(\.chemicalName).joined(separator: "; ")
        XCTAssertTrue(checks.isEmpty,
                      "An already-safe pool with only recommended optimizations must generate no focused Checks. Got: [\(checkSummary)]")
    }

    // MARK: - Wait-complete notification (only on Complete, never on Skip)

    func testCompletingSafeChlorineSchedulesWaitCompleteReminder() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let test = poolTest(mc, pH: 7.4)
        let chlorine = treatment(param: "freeChlorine", name: "Liquid Chlorine 12.5%", on: test)
        test.treatments.append(chlorine)

        let outcome = await v.completeTreatment(chlorine, in: [test], modelContext: mc)

        XCTAssertEqual(spy.scheduledWaitCompleteTreatmentIDs, [chlorine.id],
                       "Completing a safe treatment with a swim wait schedules a wait-complete reminder.")
        guard case .waitCompleteScheduled = outcome else {
            return XCTFail("Expected a wait-complete outcome so the UI can confirm the reminder was set.")
        }

        let acidSpy = NotificationSchedulingSpy()
        let acidViewModel = vm(acidSpy)
        let acidTest = poolTest(mc, pH: 7.7, fc: 3.5)
        let acid = treatment(param: "pH", name: "Muriatic Acid (31.45%)", on: acidTest)
        acid.unit = "qt"
        acidTest.treatments.append(acid)

        _ = await acidViewModel.completeTreatment(acid, in: [acidTest], modelContext: mc)

        XCTAssertTrue(acidSpy.scheduledCheckIDs.isEmpty, "No purple Check means no pH retest notification is scheduled.")
        XCTAssertEqual(acidSpy.scheduledWaitCompleteTreatmentIDs, [acid.id])
        XCTAssertEqual(acidSpy.scheduledWaitCompleteNames, ["Muriatic Acid (31.45%)"])

        let oldIdentifier = acid.stepReminderNotificationIdentifier
        acid.chemicalName = "Dry Acid (Sodium Bisulfate)"
        acid.productIdentifier = ChemicalProductID.dryAcid.rawValue
        _ = await acidViewModel.refreshTreatmentNotificationsAfterProductChange(acid, in: [acidTest], modelContext: mc)

        XCTAssertTrue(acidSpy.didCancel(oldIdentifier), "Changing the product cancels the previous chemical's wait reminder.")
        XCTAssertEqual(acidSpy.scheduledWaitCompleteNames, ["Muriatic Acid (31.45%)", "Dry Acid (Sodium Bisulfate)"])
        XCTAssertEqual(acidSpy.activeIdentifiers, Set(["treatment-wait-\(acid.id.uuidString)"]))
        XCTAssertTrue(acidSpy.scheduledCheckIDs.isEmpty)
    }

    func testSkippingSafeChlorineSchedulesNoReminder() async throws {
        let mc = ModelContext(try container())
        let spy = NotificationSchedulingSpy(); let v = vm(spy)
        let test = poolTest(mc, pH: 7.4)
        let chlorine = treatment(param: "freeChlorine", name: "Liquid Chlorine 12.5%", on: test)
        test.treatments.append(chlorine)

        v.skipTreatment(chlorine)

        XCTAssertTrue(spy.scheduledWaitCompleteTreatmentIDs.isEmpty,
                      "Skipping a treatment never schedules a wait-complete reminder — the user opted out.")
    }
}
