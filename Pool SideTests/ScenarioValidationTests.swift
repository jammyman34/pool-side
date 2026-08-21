import XCTest
@testable import Pool_Side

final class ScenarioValidationTests: XCTestCase {
    func testCompleteScenarioCatalog() async throws {
        let catalogResult = await ScenarioRunner().run(ScenarioCatalog.all)
        let report = ScenarioReportFormatter().format(catalogResult)
        print(report)
        let reportURL = ScenarioReportFormatter.writeDebugReport(report)
        print("Pool Side scenario report: \(reportURL.path)")

        XCTAssertTrue(catalogResult.failures.isEmpty, catalogResult.failureSummary)
    }
}

private enum ScenarioCatalog {
    static let baseDate = Date(timeIntervalSince1970: 1_800_010_000)

    static var all: [ScenarioDefinition] {
        coreScenarios
            + acidProductScenarios
            + pHIncreaseScenarios
            + dryChlorineScenarios
            + trichlorScenarios
            + dilutionScenarios
            + saltScenarios
            + conflictScenarios
            + multipleTreatmentScenarios
            + freshnessScenarios
            + uncertaintyScenarios
            + historyDrivenPHScenarios
            + volumeScalingScenarios
            + sanityGuardScenarios
            + applicationPolicyScenarios
            + boundaryScenarios
            + treatmentStateScenarios
            + nextTestScenarios
    }

    private static var pHDriftHistory: [ScenarioHistoricalTest] {
        [
            .init(daysBefore: 7, chemistry: .init(freeChlorine: 4, combinedChlorine: 0, pH: 7.6, totalAlkalinity: 160, calciumHardness: 300, cyanuricAcid: 55)),
            .init(daysBefore: 14, chemistry: .init(freeChlorine: 4, combinedChlorine: 0, pH: 7.6, totalAlkalinity: 160, calciumHardness: 300, cyanuricAcid: 55)),
            .init(daysBefore: 21, chemistry: .init(freeChlorine: 4, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 170, calciumHardness: 300, cyanuricAcid: 55)),
            .init(daysBefore: 28, chemistry: .init(freeChlorine: 4, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 170, calciumHardness: 300, cyanuricAcid: 55))
        ]
    }

    private static var coreScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(
                id: "A",
                name: "Healthy Baseline",
                area: "CORE",
                chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                steps: [
                    .generate(expect: .init(
                        treatmentCount: 0,
                        v2State: .readyToSwim,
                        swimmingBlocked: false,
                        testingRequired: false,
                        nextTestPending: false,
                        nextTestSource: .routineFCAndPH
                    ))
                ]
            ),
            ScenarioDefinition(
                id: "B",
                name: "Optional Maintenance Chlorine",
                area: "CORE",
                chemistry: .init(freeChlorine: 2.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                steps: [
                    .generate(expect: .init(
                        treatmentCount: 1,
                        // Category B: FC 2-<3 is now the safe Recommended top-off band toward 3 ppm.
                        treatments: [.init(nameContains: "Liquid Chlorine 12.5%", amount: 0.1, unit: "gal", urgency: .recommended, badge: "Swim after ~1 hr", category: .poolCare, completionState: .plannedTreatment)],
                        v2State: .readyToSwim,
                        swimmingBlocked: false,
                        testingRequired: false,
                        verificationRequired: false,
                        nextTestPending: false
                    )),
                    .skipTreatment(nameContains: "Liquid Chlorine", expect: .init(
                        v2State: .readyToSwim,
                        swimmingBlocked: false,
                        testingRequired: false,
                        verificationRequired: false,
                        treatmentStates: ["Liquid Chlorine": .skippedTreatment]
                    ))
                ]
            ),
            ScenarioDefinition(
                id: "C",
                name: "Below FC Readiness Minimum",
                area: "CORE",
                chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                steps: [
                    .generate(expect: .init(
                        treatmentCount: 1,
                        // Category B: FC 1-<2 is now Needs Attention and still swim-blocking.
                        treatments: [.init(nameContains: "Liquid Chlorine 12.5%", amount: 0.5, unit: "gal", urgency: .needsAttention, badge: "Test before swimming", category: .swimBlocking, completionState: .plannedTreatment)],
                        v2State: .doNotSwim,
                        swimmingBlocked: true,
                        testingRequired: true,
                        verificationRequired: true,
                        failedGates: [.sanitizerAdequacy, .treatmentCompletion],
                        nextTestPending: false
                    )),
                    .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 30, expect: .init(v2State: .doNotSwim, swimmingBlocked: true, verificationRequired: true, treatmentStates: ["Liquid Chlorine": .completedWaiting])),
                    .advance(minutes: 70, expect: .init(v2State: .testBeforeSwimming, swimmingBlocked: true, testingRequired: true, verificationRequired: true, treatmentStates: ["Liquid Chlorine": .completedVerificationRequired], pendingVerificationGates: [.sanitizerAdequacy])),
                    .addVerificationTest(chemistry: .init(freeChlorine: 3.0, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false)),
                    .addVerificationTest(chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy]))
                ]
            ),
            ScenarioDefinition(
                id: "D",
                name: "Elevated Combined Chlorine TC3",
                area: "CORE",
                chemistry: .init(freeChlorine: 2.5, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                steps: [
                    .generate(expect: .init(
                        treatmentCount: 1,
                        treatments: [.init(nameContains: "Liquid Chlorine 12.5%", amount: 0.5, unit: "gal", urgency: .recommended, badge: "Test before swimming", category: .swimBlocking, completionState: .plannedTreatment)],
                        v2State: .doNotSwim,
                        swimmingBlocked: true,
                        testingRequired: true,
                        verificationRequired: true,
                        failedGates: [.combinedChlorine, .treatmentCompletion],
                        nextTestPending: false
                    )),
                    .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 30, expect: .init(v2State: .doNotSwim, swimmingBlocked: true, verificationRequired: true, treatmentStates: ["Liquid Chlorine": .completedWaiting])),
                    .advance(minutes: 70, expect: .init(v2State: .testBeforeSwimming, swimmingBlocked: true, testingRequired: true, verificationRequired: true, treatmentStates: ["Liquid Chlorine": .completedVerificationRequired], pendingVerificationGates: [.combinedChlorine], activeWaitsEmpty: true)),
                    .addVerificationTest(chemistry: .init(freeChlorine: 6, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false)),
                    .addVerificationTest(chemistry: .init(freeChlorine: 6, combinedChlorine: 0.6, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.combinedChlorine]))
                ]
            ),
            ScenarioDefinition(
                id: "E",
                name: "Low FC + High CC",
                area: "CORE",
                chemistry: .init(freeChlorine: 1.5, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                steps: [
                    .generate(expect: .init(treatmentCount: 1, v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .combinedChlorine, .treatmentCompletion])),
                    .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 70, expect: .init(v2State: .testBeforeSwimming, testingRequired: true, verificationRequired: true, pendingVerificationGates: [.sanitizerAdequacy, .combinedChlorine])),
                    .addVerificationTest(chemistry: .init(freeChlorine: 3, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false)),
                    .addVerificationTest(chemistry: .init(freeChlorine: 1.5, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .combinedChlorine]))
                ]
            ),
            ScenarioDefinition(
                id: "F",
                name: "High pH TC4",
                area: "CORE",
                config: .init(pHDecreaser: .muriaticAcid),
                chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60),
                history: pHDriftHistory,
                steps: [
                    .generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Muriatic Acid", amount: 1.5, unit: "qt", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment, calculatedDose: 1.2, calculatedUnit: "gal")], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.pH, .treatmentCompletion], nextTestPending: false)),
                    .completeTreatment(nameContains: "Muriatic Acid", minutesAgo: 250, expect: .init(v2State: .testBeforeSwimming, testingRequired: true, verificationRequired: true, treatmentStates: ["Muriatic Acid": .completedVerificationRequired], pendingVerificationGates: [.pH])),
                    .addVerificationTest(chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 120, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false))
                ]
            ),
            ScenarioDefinition(
                id: "G",
                name: "Low TA TC6",
                area: "CORE",
                chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60),
                steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Baking Soda", amount: 18.2, unit: "lbs", urgency: .immediate, badge: "Retest TA after 6-8 hrs", category: .poolCare, completionState: .plannedTreatment)], v2State: .readyToSwim, swimmingBlocked: false, nextTestPending: false))]
            ),
            ScenarioDefinition(
                id: "H",
                name: "Low CYA TC7",
                area: "CORE",
                chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 20),
                steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Cyanuric Acid", amount: 5.3, unit: "lbs", urgency: .recommended, badge: "Retest CYA after 24-48 hrs", category: .poolCare, completionState: .plannedTreatment)], absentTreatment: "Remove Chlorine Source", v2State: .readyToSwim, swimmingBlocked: false, nextTestPending: false))]
            ),
            ScenarioDefinition(
                id: "I",
                name: "Low Calcium TC8",
                area: "CORE",
                chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 60),
                steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Calcium Hardness", amount: 71.3, unit: "lbs", urgency: .immediate, category: .poolCare, completionState: .plannedTreatment)], v2State: .readyToSwim, swimmingBlocked: false, nextTestPending: false))]
            ),
            ScenarioDefinition(
                id: "J",
                name: "Recovery",
                area: "CORE",
                chemistry: .init(freeChlorine: 1, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60),
                state: .normal(
                    clarity: .cloudy,
                    algae: .present,
                    visualIndicators: [VisualIndicator.cloudyWater.rawValue, VisualIndicator.algaeSpots.rawValue]
                ),
                steps: [
                    .generate(expect: .init(treatmentCount: 2, treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", urgency: .immediate, badge: "Test before swimming", category: .swimBlocking, completionState: .plannedTreatment), .init(nameContains: "Keep Filtering", urgency: .recommended, category: .nonChemicalAction, completionState: .unresolvedRecoveryAction)], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .combinedChlorine, .waterClarity, .visibleAlgae, .treatmentCompletion])),
                    .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 90, expect: .init(v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.waterClarity, .visibleAlgae], pendingVerificationGates: [.sanitizerAdequacy, .combinedChlorine]))
                ]
            )
        ]
    }

    private static var acidProductScenarios: [ScenarioDefinition] {
        [
            // pH 8.0 is just outside the swim-safe range (7.8–8.0), so it is Needs Attention (not Act Now) and
            // corrects toward ~7.4; the total demand for the 0.6 pH drop displays in gallons (1.2 gal); staged 1.5 qt.
            highPHScenario(
                id: "AP-acid31",
                name: "Muriatic Acid 31.45%",
                pHDecreaser: .muriaticAcid,
                expectation: .init(nameContains: "Muriatic Acid", amount: 1.5, unit: "qt", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment, calculatedDose: 1.2, calculatedUnit: "gal", wasDoseCapped: true)
            ),
            // Staged current application now matches the equivalent 31.45% single application:
            // 52.13 fl-oz-equivalent-31 × (31.45/20) ≈ 82 fl oz → 2.5 qt current; total ≈ 194 fl oz → 1.5 gal.
            // Superseded by approved policy §12 (acid application-policy symmetry): low-fume acid is now
            // staged rather than dumped in one 1.5 gal application, so wasDoseCapped is true.
            highPHScenario(
                id: "AP-acid20",
                name: "Low-Fume Muriatic Acid 20%",
                pHDecreaser: .lowFumeMuriaticAcid,
                expectation: .init(nameContains: "Low-Fume Muriatic Acid", amount: 2.5, unit: "qt", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment, calculatedMinimum: 1.4, calculatedUnit: "gal", wasDoseCapped: true)
            ),
            // Staged current 1.2 lbs; total now ~3.5 lbs for the 0.6 pH drop toward ~7.4 (policy §6 + §12).
            highPHScenario(
                id: "AP-dry-acid",
                name: "Dry Acid Sodium Bisulfate",
                pHDecreaser: .dryAcid,
                expectation: .init(nameContains: "Dry Acid", amount: 1.2, unit: "lbs", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment, calculatedDose: 3.5, calculatedUnit: "lbs", wasDoseCapped: true)
            )
        ]
    }

    private static func highPHScenario(id: String, name: String, pHDecreaser: PHDecreaserPreference, expectation: TreatmentExpectation) -> ScenarioDefinition {
        ScenarioDefinition(
            id: id,
            name: name,
            area: "ACID PRODUCTS",
            config: .init(pHDecreaser: pHDecreaser),
            chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60),
            history: pHDriftHistory,
            steps: [
                .generate(expect: .init(treatmentCount: 1, treatments: [expectation], v2State: .doNotSwim, swimmingBlocked: true, verificationRequired: true, failedGates: [.pH, .treatmentCompletion], nextTestPending: false)),
                .completeTreatment(nameContains: expectation.nameContains, minutesAgo: 250, expect: .init(v2State: .testBeforeSwimming, testingRequired: true, verificationRequired: true, pendingVerificationGates: [.pH], nextTestPending: false))
            ]
        )
    }

    private static var pHIncreaseScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "PI-soda-ash", name: "Soda Ash Low pH", area: "PH INCREASE", config: .init(pHIncreaser: .sodaAsh), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 6.9, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Soda Ash", amount: 2.6, unit: "lbs", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment, expectedDeltaMinimum: 0.49)], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.pH, .treatmentCompletion], nextTestPending: false)),
                .completeTreatment(nameContains: "Soda Ash", minutesAgo: 250, expect: .init(v2State: .testBeforeSwimming, testingRequired: true, verificationRequired: true, pendingVerificationGates: [.pH])),
                .addVerificationTest(chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.2, totalAlkalinity: 105, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false)),
                // pH 7.1 is within the approved 7.0–7.8 swim range: swimmable (a Recommended raise toward
                // ~7.4 may still exist, but it no longer blocks). Previously 7.1 failed the old 7.2 gate.
                .addVerificationTest(chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.1, totalAlkalinity: 105, calciumHardness: 330, cyanuricAcid: 60), expect: .init(v2State: .readyToSwim, swimmingBlocked: false))
            ]),
            ScenarioDefinition(id: "PI-borax", name: "Borax Low pH", area: "PH INCREASE", config: .init(pHIncreaser: .borax), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 6.9, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Borax", amountMinimum: 2.5, unit: "lbs", urgency: .needsAttention, badge: "Test pH after ~4 hrs", category: .swimBlocking, completionState: .plannedTreatment)], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.pH, .treatmentCompletion]))]),
            ScenarioDefinition(id: "PI-ta-sensitive-low", name: "Soda Ash Low Buffer", area: "PH INCREASE", config: .init(pHIncreaser: .sodaAsh), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 6.9, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCountMinimum: 2, treatments: [.init(nameContains: "Soda Ash", amountMaximum: 1.8, unit: "lbs"), .init(nameContains: "Baking Soda", unit: "lbs")], v2State: .doNotSwim, swimmingBlocked: true))])
        ]
    }

    private static var dryChlorineScenarios: [ScenarioDefinition] {
        [
            // Category B: severe FC <1 is Act Now and still uses liquid chlorine despite dry-chlorine preferences.
            ScenarioDefinition(id: "DC-calhypo-acute", name: "Cal-Hypo Preference Acute FC", area: "DRY CHLORINE", config: .init(chlorine: .calHypo), chemistry: .init(freeChlorine: 0.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", urgency: .immediate, category: .swimBlocking, completionState: .plannedTreatment, expectedDeltaMinimum: 2.4)], absentTreatment: "Cal-Hypo", v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .treatmentCompletion]))]),
            ScenarioDefinition(id: "DC-dichlor-acute", name: "Dichlor Preference Acute FC", area: "DRY CHLORINE", config: .init(chlorine: .dichlor), chemistry: .init(freeChlorine: 0.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", urgency: .immediate, category: .swimBlocking, completionState: .plannedTreatment)], absentTreatment: "Dichlor", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "DC-recovery-liquid-safe", name: "Recovery Avoids Stabilized Dry Chlorine", area: "DRY CHLORINE", config: .init(chlorine: .dichlor), chemistry: .init(freeChlorine: 1, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), state: .normal(clarity: .cloudy, algae: .present, visualIndicators: [VisualIndicator.cloudyWater.rawValue, VisualIndicator.algaeSpots.rawValue]), steps: [.generate(expect: .init(treatmentCount: 2, treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", urgency: .immediate, category: .swimBlocking)], absentTreatment: "Dichlor", v2State: .doNotSwim, swimmingBlocked: true))])
        ]
    }

    private static var trichlorScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "TR-acute-low-fc", name: "Trichlor Preference Acute FC Uses Immediate Chlorine", area: "TRICHLOR", config: .init(chlorine: .tablets), chemistry: .init(freeChlorine: 0.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", amount: 0.75, unit: "gal", expectedDeltaMinimum: 2.4)], absentTreatment: "Trichlor", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "TR-maintenance", name: "Trichlor Maintenance Preference Avoids Precise Tablet Dose", area: "TRICHLOR", config: .init(chlorine: .tablets), chemistry: .init(freeChlorine: 2.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", urgency: .recommended)], absentTreatment: "Chlorine Tablets", v2State: .readyToSwim, swimmingBlocked: false))])
        ]
    }

    private static var dilutionScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "DIL-cya-80", name: "High CYA 80 No Stabilizer", area: "HIGH CYA / DILUTION", chemistry: .init(freeChlorine: 8, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 80), steps: [.generate(expect: .init(absentTreatment: "Cyanuric Acid", v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "DIL-cya-100", name: "High CYA 100 Water Replacement", area: "HIGH CYA / DILUTION", chemistry: .init(freeChlorine: 3.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 100), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Partial Water Replacement", amountMinimum: 9000, amountMaximum: 11000, unit: "gallons to drain/refill", urgency: .recommended, category: .poolCare)], absentTreatment: "Cyanuric Acid", v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "DIL-cya-150-low-fc", name: "Very High CYA Low FC", area: "HIGH CYA / DILUTION", chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 150), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", unit: "gal", category: .swimBlocking), .init(nameContains: "Partial Water Replacement", unit: "gallons to drain/refill")], absentTreatment: "Cyanuric Acid", v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .treatmentCompletion]))]),
            ScenarioDefinition(id: "DIL-ch-450", name: "High Calcium 450", area: "HIGH CALCIUM", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 450, cyanuricAcid: 60), steps: [.generate(expect: .init(absentTreatment: "Calcium Hardness Increaser", v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "DIL-ch-600", name: "High Calcium 600 Monitor", area: "HIGH CALCIUM", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 600, cyanuricAcid: 60), steps: [.generate(expect: .init(absentTreatment: "Calcium Hardness Increaser", v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "DIL-ch-1000-scaling", name: "High Calcium 1000 With High pH", area: "HIGH CALCIUM", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 8.1, totalAlkalinity: 100, calciumHardness: 1000, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Manage Scaling Risk", urgency: .optional)], absentTreatment: "Calcium Hardness Increaser", v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.pH]))])
        ]
    }

    private static var saltScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "SALT-generator-modest", name: "Salt Generator Modest FC Deficit", area: "SALT", config: .init(isSaltwater: true, chlorine: .saltGenerator), chemistry: .init(freeChlorine: 2.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60, salt: 3200), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Salt Chlorine Generator", amount: 0, urgency: .recommended, category: .nonChemicalAction)], v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "SALT-urgent-deficit", name: "Salt Urgent Deficit Remains Blocked", area: "SALT", config: .init(isSaltwater: true, chlorine: .saltGenerator), chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60, salt: 3200), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Salt Chlorine Generator", urgency: .needsAttention, category: .nonChemicalAction)], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy]))]),
            ScenarioDefinition(id: "SALT-low", name: "Low Salt Addition", area: "SALT", config: .init(isSaltwater: true, chlorine: .saltGenerator), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60, salt: 2500), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Pool Salt", amount: 190.1, unit: "lbs", urgency: .recommended, category: .poolCare, expectedDelta: 700)], v2State: .readyToSwim, swimmingBlocked: false))]),
            ScenarioDefinition(id: "SALT-adequate", name: "Adequate Salt No Salt Treatment", area: "SALT", config: .init(isSaltwater: true, chlorine: .saltGenerator), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60, salt: 3200), steps: [.generate(expect: .init(absentTreatment: "Pool Salt", v2State: .readyToSwim, swimmingBlocked: false))])
        ]
    }

    private static var conflictScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "CON-high-ph-high-ta", name: "High pH High TA One Acid Strategy", area: "CONFLICTS", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 8.1, totalAlkalinity: 160, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCountMinimum: 1, treatmentCountMaximum: 1, treatments: [.init(nameContains: "Muriatic Acid", unit: "qt")], absentTreatment: "Baking Soda", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "CON-high-ph-low-ta", name: "High pH Low TA Defers Baking Soda", area: "CONFLICTS", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 8.1, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Muriatic Acid")], absentTreatment: "Baking Soda", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "CON-low-ph-low-ta", name: "Low pH Low TA Allows Compatible Raises", area: "CONFLICTS", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 6.9, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Soda Ash"), .init(nameContains: "Baking Soda")], absentTreatment: "Muriatic Acid", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "CON-low-ph-high-ta", name: "Low pH High TA No Acid Fight", area: "CONFLICTS", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 6.9, totalAlkalinity: 160, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Soda Ash")], absentTreatment: "Muriatic Acid", v2State: .doNotSwim, swimmingBlocked: true))]),
            ScenarioDefinition(id: "CON-low-fc-high-ph", name: "Low FC High pH Sequenced Treatments", area: "CONFLICTS", chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 8.1, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCountMinimum: 2, treatments: [.init(nameContains: "Muriatic Acid", urgency: .immediate), .init(nameContains: "Liquid Chlorine", urgency: .needsAttention, badge: "Test before swimming")], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy, .pH, .treatmentCompletion], nextTestPending: false))])
        ]
    }

    private static var multipleTreatmentScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "MT-poolcare-plus-blocking", name: "PoolCare Plus SwimBlocking", area: "MULTIPLE TREATMENTS", chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(treatmentCountMinimum: 2, treatments: [.init(nameContains: "Liquid Chlorine", category: .swimBlocking), .init(nameContains: "Baking Soda", category: .poolCare)], v2State: .doNotSwim, swimmingBlocked: true, nextTestPending: false)),
                .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 70, expect: .init(v2State: .testBeforeSwimming, pendingVerificationGates: [.sanitizerAdequacy], nextTestPending: false)),
                .skipTreatment(nameContains: "Baking Soda", expect: .init(v2State: .testBeforeSwimming, nextTestPending: false))
            ]),
            ScenarioDefinition(id: "MT-two-poolcare", name: "Two PoolCare Treatments", area: "MULTIPLE TREATMENTS", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 50, calciumHardness: 100, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCountMinimum: 2, treatments: [.init(nameContains: "Baking Soda", category: .poolCare), .init(nameContains: "Calcium Hardness", category: .poolCare)], v2State: .readyToSwim, swimmingBlocked: false, nextTestPending: false))])
        ]
    }

    private static var freshnessScenarios: [ScenarioDefinition] {
        [
            // Approved 24-hour (1440-minute) readiness-freshness window.
            freshnessScenario(id: "FRESH-now", name: "Fresh Test", minutesOld: 60, expected: .readyToSwim),
            freshnessScenario(id: "FRESH-inside", name: "Inside Freshness Boundary", minutesOld: 1439, expected: .readyToSwim),
            freshnessScenario(id: "FRESH-boundary", name: "Exact Freshness Boundary", minutesOld: 1440, expected: .readyToSwim),
            freshnessScenario(id: "FRESH-outside", name: "Outside Freshness Boundary", minutesOld: 1441, expected: .doNotSwim),
            freshnessScenario(id: "FRESH-stale", name: "Materially Stale", minutesOld: 2880, expected: .doNotSwim)
        ]
    }

    private static func freshnessScenario(id: String, name: String, minutesOld: Int, expected: SwimabilityState) -> ScenarioDefinition {
        ScenarioDefinition(id: id, name: name, area: "FRESHNESS", chemistry: .baseline, currentTestMinutesOld: minutesOld, steps: [.generate(expect: .init(treatmentCount: 0, v2State: expected, swimmingBlocked: expected != .readyToSwim, testingRequired: expected != .readyToSwim))])
    }

    private static var uncertaintyScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "UNK-clarity-not-recorded", name: "Clarity Not Recorded", area: "UNCERTAINTY", chemistry: .baseline, state: .normal(clarity: .notRecorded), steps: [.generate(expect: .init(v2State: .moreInformationNeeded, swimmingBlocked: true, unknownGates: [.waterClarity]))]),
            ScenarioDefinition(id: "UNK-algae-not-recorded", name: "Algae Not Recorded", area: "UNCERTAINTY", chemistry: .baseline, state: .normal(algae: .notRecorded), steps: [.generate(expect: .init(v2State: .moreInformationNeeded, swimmingBlocked: true, unknownGates: [.visibleAlgae]))]),
            ScenarioDefinition(id: "UNK-clarity-cannot-tell", name: "Clarity Cannot Tell", area: "UNCERTAINTY", chemistry: .baseline, state: .normal(clarity: .cannotTell), steps: [.generate(expect: .init(v2State: .moreInformationNeeded, swimmingBlocked: true, unknownGates: [.waterClarity]))]),
            ScenarioDefinition(id: "UNK-algae-cannot-tell", name: "Algae Cannot Tell", area: "UNCERTAINTY", chemistry: .baseline, state: .normal(algae: .cannotTell), steps: [.generate(expect: .init(v2State: .moreInformationNeeded, swimmingBlocked: true, unknownGates: [.visibleAlgae]))])
        ]
    }

    private static var historyDrivenPHScenarios: [ScenarioDefinition] {
        [
            // Approved policy §6: history no longer suppresses correction of out-of-operating-range pH.
            // pH 8.0 is Act Now High and is corrected toward ~7.4 regardless of whether it is isolated.
            ScenarioDefinition(id: "HIST-ph-isolated", name: "Isolated pH 8 Still Corrected", area: "HISTORY", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Muriatic Acid", urgency: .needsAttention)], v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.pH]))]),
            ScenarioDefinition(id: "HIST-ph-rising", name: "Rising pH History Treats", area: "HISTORY", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), history: pHDriftHistory, steps: [.generate(expect: .init(treatmentCount: 1, treatments: [.init(nameContains: "Muriatic Acid")], v2State: .doNotSwim, swimmingBlocked: true))]),
            // pH 7.8 is Recommended High: corrected toward ~7.4 but still swimmable (7.8 inclusive), so the
            // Muriatic Acid treatment is now generated yet the pool remains Ready to Swim (pool-care classification).
            ScenarioDefinition(id: "HIST-ph-stable-highish", name: "Stable High-ish pH Corrected But Swimmable", area: "HISTORY", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.8, totalAlkalinity: 130, calciumHardness: 330, cyanuricAcid: 60), history: [.init(daysBefore: 7, chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.8, totalAlkalinity: 130, calciumHardness: 330, cyanuricAcid: 60)), .init(daysBefore: 14, chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.8, totalAlkalinity: 130, calciumHardness: 330, cyanuricAcid: 60)), .init(daysBefore: 21, chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.8, totalAlkalinity: 130, calciumHardness: 330, cyanuricAcid: 60))], steps: [.generate(expect: .init(treatments: [.init(nameContains: "Muriatic Acid", urgency: .recommended, category: .poolCare)], v2State: .readyToSwim, swimmingBlocked: false))])
        ]
    }

    private static var volumeScalingScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "VOL-chlorine-10k", name: "12.5 Chlorine 10k Scaling", area: "VOLUME SCALING", config: .init(volume: 10_000), chemistry: .init(freeChlorine: 0.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", amount: 0.25, unit: "gal")]))]),
            ScenarioDefinition(id: "VOL-chlorine-40k", name: "12.5 Chlorine 40k Scaling", area: "VOLUME SCALING", config: .init(volume: 40_000), chemistry: .init(freeChlorine: 0.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Liquid Chlorine", amount: 0.75, unit: "gal")]))]),
            ScenarioDefinition(id: "VOL-baking-10k", name: "Baking Soda 10k Scaling", area: "VOLUME SCALING", config: .init(volume: 10_000), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Baking Soda", amount: 5.6, unit: "lbs")]))]),
            ScenarioDefinition(id: "VOL-calcium-20k", name: "Calcium 20k Scaling", area: "VOLUME SCALING", config: .init(volume: 20_000), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Calcium Hardness", amount: 43.8, unit: "lbs")]))]),
            ScenarioDefinition(id: "VOL-cya-40k", name: "CYA 40k Scaling", area: "VOLUME SCALING", config: .init(volume: 40_000), chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 20), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Cyanuric Acid", amount: 6.7, unit: "lbs")]))]),
            ScenarioDefinition(id: "VOL-salt-20k", name: "Salt 20k Scaling", area: "VOLUME SCALING", config: .init(volume: 20_000, isSaltwater: true, chlorine: .saltGenerator), chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60, salt: 2500), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Pool Salt", amount: 116.6, unit: "lbs")]))])
        ]
    }

    private static var sanityGuardScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "MAG-baking-not-hundreds", name: "Baking Soda Magnitude Guard", area: "MAGNITUDE", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Baking Soda", amountMaximum: 20, unit: "lbs")]))]),
            ScenarioDefinition(id: "MAG-cya-not-tens", name: "CYA Magnitude Guard", area: "MAGNITUDE", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 20), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Cyanuric Acid", amountMaximum: 8, unit: "lbs")]))]),
            // Low-CH now targets the operating range (~275, policy §8) rather than the 200 minimum, so +175 ppm
// in 32,583 gal is ~71 lbs (correct linear scaling; guard still catches order-of-magnitude errors).
ScenarioDefinition(id: "MAG-calcium-tens", name: "Calcium Magnitude Guard", area: "MAGNITUDE", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Calcium Hardness", amountMinimum: 30, amountMaximum: 80, unit: "lbs")]))]),
            ScenarioDefinition(id: "MAG-dry-acid-weight", name: "Dry Acid Uses Weight", area: "MAGNITUDE", config: .init(pHDecreaser: .dryAcid), chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), history: pHDriftHistory, steps: [.generate(expect: .init(treatments: [.init(nameContains: "Dry Acid", unit: "lbs")], absentTreatment: "fl oz"))])
        ]
    }

    private static var applicationPolicyScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "APP-acid-demand-vs-current", name: "Acid Total Demand Versus Current Application", area: "APPLICATION POLICY", config: .init(pHDecreaser: .muriaticAcid), chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), history: pHDriftHistory, steps: [.generate(expect: .init(treatments: [.init(nameContains: "Muriatic Acid", amount: 1.5, unit: "qt", calculatedDose: 1.2, calculatedUnit: "gal", wasDoseCapped: true)], nextTestPending: false)), .completeTreatment(nameContains: "Muriatic Acid", minutesAgo: 250, expect: .init(v2State: .testBeforeSwimming, pendingVerificationGates: [.pH]))]),
            ScenarioDefinition(id: "APP-cya-retest-policy", name: "CYA Retest Policy", area: "APPLICATION POLICY", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 20), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Cyanuric Acid", badge: "Retest CYA after 24-48 hrs", category: .poolCare)], nextTestPending: false))]),
            ScenarioDefinition(id: "APP-calcium-retest-policy", name: "Calcium Retest Policy", area: "APPLICATION POLICY", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 100, cyanuricAcid: 60), steps: [.generate(expect: .init(treatments: [.init(nameContains: "Calcium Hardness", category: .poolCare)], nextTestPending: false)), .completeTreatment(nameContains: "Calcium Hardness", minutesAgo: 10, expect: .init(nextTestPending: false))])
        ]
    }

    private static var boundaryScenarios: [ScenarioDefinition] {
        let fcValues = [0.9, 1.0, 1.9, 2.0, 2.9, 3.0, 4.0, 4.4]
        let fcScenarios = fcValues.map { fc in
            let blocked = fc < 2.0
            return ScenarioDefinition(id: "FC-\(fc)", name: "FC Boundary \(fc)", chemistry: .init(freeChlorine: fc, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(v2State: blocked ? .doNotSwim : .readyToSwim, swimmingBlocked: blocked, failedGates: blocked ? [.sanitizerAdequacy] : []))])
        }
        let ccValues = [0.0, 0.5, 0.6, 1.0]
        let ccScenarios = ccValues.map { cc in
            ScenarioDefinition(id: "CC-\(cc)", name: "CC Boundary \(cc)", chemistry: .init(freeChlorine: 6, combinedChlorine: cc, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(v2State: cc > 0.5 ? .doNotSwim : .readyToSwim, swimmingBlocked: cc > 0.5, failedGates: cc > 0.5 ? [.combinedChlorine] : []))])
        }
        // Approved swim range is 7.0–7.8 inclusive (wider than the 7.2–7.6 operating range): 7.1 swims.
        let pHValues = [6.9, 7.0, 7.1, 7.2, 7.5, 7.7, 7.8, 7.9, 8.0]
        let pHScenarios = pHValues.map { pH in
            let swimmable = (7.0...7.8).contains(pH)
            return ScenarioDefinition(id: "PH-\(pH)", name: "pH Boundary \(pH)", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: pH, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(v2State: swimmable ? .readyToSwim : .doNotSwim, swimmingBlocked: !swimmable, failedGates: swimmable ? [] : [.pH]))])
        }
        let visualCases: [(String, WaterClarityAssessment, VisibleAlgaeAssessment, SwimabilityState, [SwimReadinessGateIdentifier])] = [
            ("clear-no-algae", .clear, .absent, .readyToSwim, []),
            ("cloudy-no-algae", .cloudy, .absent, .doNotSwim, [.waterClarity]),
            ("clear-algae", .clear, .present, .doNotSwim, [.visibleAlgae]),
            ("cloudy-algae", .cloudy, .present, .doNotSwim, [.waterClarity, .visibleAlgae]),
            ("clarity-unknown", .notRecorded, .absent, .moreInformationNeeded, []),
            ("algae-unknown", .clear, .notRecorded, .moreInformationNeeded, [])
        ]
        let visualScenarios = visualCases.map { item in
            ScenarioDefinition(id: "VIS-\(item.0)", name: "Visual Boundary \(item.0)", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), state: .normal(clarity: item.1, algae: item.2), steps: [.generate(expect: .init(v2State: item.3, swimmingBlocked: item.3 != .readyToSwim, failedGates: item.4))])
        }
        return fcScenarios + ccScenarios + pHScenarios + visualScenarios
    }

    private static var treatmentStateScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "TS-poolcare-skip-restore", name: "PoolCare Skip Restore", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(treatments: [.init(nameContains: "Baking Soda", category: .poolCare, completionState: .plannedTreatment)], v2State: .readyToSwim, swimmingBlocked: false)),
                .skipTreatment(nameContains: "Baking Soda", expect: .init(v2State: .readyToSwim, swimmingBlocked: false, treatmentStates: ["Baking Soda": .skippedTreatment])),
                .restoreTreatment(nameContains: "Baking Soda", expect: .init(v2State: .readyToSwim, swimmingBlocked: false, treatmentStates: ["Baking Soda": .plannedTreatment]))
            ]),
            ScenarioDefinition(id: "TS-corrective-skip", name: "Skipped Corrective Treatment", chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(v2State: .doNotSwim, swimmingBlocked: true)),
                .skipTreatment(nameContains: "Liquid Chlorine", expect: .init(v2State: .doNotSwim, swimmingBlocked: true, failedGates: [.sanitizerAdequacy], treatmentStates: ["Liquid Chlorine": .skippedTreatment]))
            ])
        ]
    }

    private static var nextTestScenarios: [ScenarioDefinition] {
        [
            ScenarioDefinition(id: "NT-routine", name: "Routine Next Test", chemistry: .init(freeChlorine: 6, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [.generate(expect: .init(treatmentCount: 0, nextTestPending: false, nextTestSource: .routineFCAndPH, nextTestMinutesFromCurrentTest: 3 * 24 * 60))]),
            ScenarioDefinition(id: "NT-completion-anchor", name: "Completed Treatment Keeps Routine Next Full Test", config: .init(pHDecreaser: .muriaticAcid), chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 8.0, totalAlkalinity: 140, calciumHardness: 330, cyanuricAcid: 60), history: pHDriftHistory, steps: [
                .generate(expect: .init(nextTestPending: false)),
                .completeTreatment(nameContains: "Acid", minutesAgo: 10, expect: .init(nextTestPending: false))
            ]),
            ScenarioDefinition(id: "NT-skip", name: "Skipped Treatment Does Not Fake Retest", chemistry: .init(freeChlorine: 6.5, combinedChlorine: 0.5, pH: 7.5, totalAlkalinity: 50, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(nextTestPending: false)),
                .skipTreatment(nameContains: "Baking Soda", expect: .init(nextTestPending: false))
            ]),
            ScenarioDefinition(id: "NT-optional-chlorine-pending", name: "Optional Maintenance Chlorine Keeps Tomorrow While Pending", area: "NEXT POOL TEST", chemistry: optionalMaintenanceChlorineChemistry, state: optionalMaintenanceChlorineState, steps: [
                .generate(expect: .init(
                    treatmentCount: 1,
                    treatments: [.init(nameContains: "Liquid Chlorine 12.5%", amount: 0.1, unit: "gal", urgency: .recommended, badge: "Swim after ~1 hr", category: .poolCare, completionState: .plannedTreatment)],
                    v2State: .readyToSwim,
                    swimmingBlocked: false,
                    testingRequired: false,
                    verificationRequired: false,
                    nextTestPending: false
                ))
            ]),
            ScenarioDefinition(id: "NT-optional-chlorine-completed", name: "Optional Maintenance Chlorine Keeps Tomorrow After Completion", area: "NEXT POOL TEST", chemistry: optionalMaintenanceChlorineChemistry, state: optionalMaintenanceChlorineState, steps: [
                .generate(expect: .init(treatmentCount: 1, nextTestPending: false)),
                .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 10, expect: .init(
                    v2State: .readyToSwim,
                    swimmingBlocked: false,
                    testingRequired: false,
                    verificationRequired: false,
                    nextTestPending: false
                ))
            ]),
            ScenarioDefinition(id: "NT-optional-chlorine-skipped", name: "Optional Maintenance Chlorine Skip Does Not Create Verification", area: "NEXT POOL TEST", chemistry: optionalMaintenanceChlorineChemistry, state: optionalMaintenanceChlorineState, steps: [
                .generate(expect: .init(treatmentCount: 1, nextTestPending: false)),
                .skipTreatment(nameContains: "Liquid Chlorine", expect: .init(
                    v2State: .readyToSwim,
                    swimmingBlocked: false,
                    testingRequired: false,
                    verificationRequired: false,
                    treatmentStates: ["Liquid Chlorine": .skippedTreatment],
                    nextTestPending: false
                ))
            ]),
            ScenarioDefinition(id: "NT-low-fc-completed-verification", name: "Below Minimum Chlorine Completion Keeps Verification In Workflow", area: "NEXT POOL TEST", chemistry: .init(freeChlorine: 1.5, combinedChlorine: 0, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(nextTestPending: false)),
                .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 10, expect: .init(verificationRequired: true, nextTestPending: false))
            ]),
            ScenarioDefinition(id: "NT-elevated-cc-completed-verification", name: "Elevated CC Completion Keeps Verification In Workflow", area: "NEXT POOL TEST", chemistry: .init(freeChlorine: 2.5, combinedChlorine: 1, pH: 7.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60), steps: [
                .generate(expect: .init(nextTestPending: false)),
                .completeTreatment(nameContains: "Liquid Chlorine", minutesAgo: 10, expect: .init(verificationRequired: true, nextTestPending: false))
            ])
        ]
    }

    private static let optionalMaintenanceChlorineChemistry = ScenarioChemistry(
        freeChlorine: 2.5,
        combinedChlorine: 0,
        pH: 7.6,
        totalAlkalinity: 100,
        calciumHardness: 350,
        cyanuricAcid: 60
    )

    private static let optionalMaintenanceChlorineState = ScenarioPoolState(
        coverOpenTime: .twoToSixHours,
        organicDebrisLoad: .low,
        skimmedDebris: .yes,
        cleaningActivity: .multipleCycles,
        clarity: .clear,
        algae: .absent
    )
}

private struct ScenarioDefinition {
    let id: String
    let name: String
    var area: String = "CORE"
    var config: ScenarioConfig = .init()
    let chemistry: ScenarioChemistry
    var state: ScenarioPoolState = .normal()
    var history: [ScenarioHistoricalTest] = []
    var currentTestMinutesOld: Int = 60
    let steps: [ScenarioStep]
}

private struct ScenarioConfig {
    var volume: Double = 32_583
    var surfaceType: SurfaceType = .plaster
    var isSaltwater: Bool = false
    var chlorine: ChlorinePreference = .liquidChlorine12_5
    var pHIncreaser: PHIncreaserPreference = .sodaAsh
    var pHDecreaser: PHDecreaserPreference = .muriaticAcid
    var alkalinityIncreaser: AlkalinityIncreaserPreference = .sodiumBicarbonate
    var calciumIncreaser: CalciumIncreaserPreference = .calciumChloride
    var stabilizer: StabilizerPreference = .granularCYA

    func makePoolConfiguration() -> PoolConfiguration {
        PoolConfiguration(
            volumeGallons: volume,
            surfaceType: surfaceType,
            testMethod: .liquidDropKit,
            isSaltwater: isSaltwater,
            chlorinePreference: chlorine,
            pHIncreaserPreference: pHIncreaser,
            pHDecreaserPreference: pHDecreaser,
            alkalinityIncreaserPreference: alkalinityIncreaser,
            calciumIncreaserPreference: calciumIncreaser,
            stabilizerPreference: stabilizer
        )
    }
}

private struct ScenarioChemistry {
    let freeChlorine: Double
    let combinedChlorine: Double
    let pH: Double
    let totalAlkalinity: Double
    let calciumHardness: Double
    let cyanuricAcid: Double
    var salt: Double? = nil

    static let baseline = ScenarioChemistry(
        freeChlorine: 6,
        combinedChlorine: 0,
        pH: 7.5,
        totalAlkalinity: 100,
        calciumHardness: 330,
        cyanuricAcid: 60
    )
}

private struct ScenarioHistoricalTest {
    let daysBefore: Int
    let chemistry: ScenarioChemistry
    var state: ScenarioPoolState = .normal()
}

private struct ScenarioPoolState {
    var swimmingLoad: SwimmingLoad = .none
    var rainLoad: RainLoad = .none
    var coverOpenTime: CoverOpenTime = .mostlyOpen
    var organicDebrisLoad: OrganicDebrisLoad = .low
    var skimmedDebris: SkimmedDebris = .yes
    var backwashedFilter: BackwashedFilter = .no
    var waterAdded: WaterAdded = .none
    var cleaningActivity: CleaningActivity = .oneCycle
    var poolBrushed: PoolBrushed = .no
    var clarity: WaterClarityAssessment = .clear
    var algae: VisibleAlgaeAssessment = .absent
    var visualIndicators: [String] = []

    static func normal(
        clarity: WaterClarityAssessment = .clear,
        algae: VisibleAlgaeAssessment = .absent,
        visualIndicators: [String] = []
    ) -> ScenarioPoolState {
        ScenarioPoolState(clarity: clarity, algae: algae, visualIndicators: visualIndicators)
    }

    var poolConditions: PoolConditions {
        PoolConditions(swimmingLoad: swimmingLoad, petSwimmingLoad: .none, rainLoad: rainLoad, coverOpenTime: coverOpenTime, organicDebrisLoad: organicDebrisLoad, skimmedDebris: skimmedDebris, backwashedFilter: backwashedFilter, waterAdded: waterAdded, cleaningActivity: cleaningActivity, poolBrushed: poolBrushed)
    }
}

private enum ScenarioStep {
    case generate(expect: ScenarioExpectation)
    case completeTreatment(nameContains: String, minutesAgo: Int, expect: ScenarioExpectation)
    case skipTreatment(nameContains: String, expect: ScenarioExpectation)
    case restoreTreatment(nameContains: String, expect: ScenarioExpectation)
    case advance(minutes: Int, expect: ScenarioExpectation)
    case addVerificationTest(chemistry: ScenarioChemistry, expect: ScenarioExpectation)
}

private struct TreatmentExpectation {
    var nameContains: String
    var amount: Double?
    var amountMinimum: Double?
    var amountMaximum: Double?
    var unit: String?
    var urgency: TreatmentUrgency?
    var badge: String?
    var category: V2TreatmentClassificationCategory?
    var completionState: V2TreatmentCompletionState?
    var calculatedDose: Double?
    var calculatedMinimum: Double?
    var calculatedMaximum: Double?
    var calculatedUnit: String?
    var wasDoseCapped: Bool?
    var expectedDelta: Double?
    var expectedDeltaMinimum: Double?
    var expectedDeltaMaximum: Double?
}

private struct ScenarioExpectation {
    var treatmentCount: Int?
    var treatmentCountMinimum: Int?
    var treatmentCountMaximum: Int?
    var treatments: [TreatmentExpectation] = []
    var absentTreatment: String?
    var v2State: SwimabilityState?
    var swimmingBlocked: Bool?
    var testingRequired: Bool?
    var verificationRequired: Bool?
    var failedGates: [SwimReadinessGateIdentifier] = []
    var unknownGates: [SwimReadinessGateIdentifier] = []
    var treatmentStates: [String: V2TreatmentCompletionState] = [:]
    var pendingVerificationGates: [SwimReadinessGateIdentifier] = []
    var activeWaitsEmpty: Bool?
    var nextTestPending: Bool?
    var nextTestSource: NextTestRecommendation.Source?
    var nextTestMinutesFromCompletedAt: Int?
    var nextTestMinutesFromCurrentTest: Int?
}

private struct ScenarioStepResult {
    let name: String
    let expected: String
    let actual: String
    var assertionCount: Int
    var failures: [String]
}

private struct ScenarioResult {
    var stepResults: [(scenario: ScenarioDefinition, result: ScenarioStepResult)] = []

    var failures: [String] { stepResults.flatMap { $0.result.failures.map { "\($0)" } } }
    var assertionCount: Int { stepResults.reduce(0) { $0 + $1.result.assertionCount } }
    var failureSummary: String {
        failures.isEmpty ? "All scenario assertions passed." : failures.joined(separator: "\n")
    }
}

private final class ScenarioRunner {
    private let service = RuleBasedService()
    private let nextTestEngine = NextTestRecommendationEngine()
    private let swimabilityEngine = SwimabilityV2Engine()
    private let evaluationDate = ScenarioCatalog.baseDate.addingTimeInterval(60 * 60)

    func run(_ scenarios: [ScenarioDefinition]) async -> ScenarioResult {
        var result = ScenarioResult()
        for scenario in scenarios {
            var context = ScenarioExecutionContext(scenario: scenario, evaluationDate: evaluationDate)
            for (index, step) in scenario.steps.enumerated() {
                let stepResult = await run(step, index: index + 1, scenario: scenario, context: &context)
                result.stepResults.append((scenario, stepResult))
            }
        }
        return result
    }

    private func run(_ step: ScenarioStep, index: Int, scenario: ScenarioDefinition, context: inout ScenarioExecutionContext) async -> ScenarioStepResult {
        switch step {
        case .generate(let expectation):
            await generate(context: &context)
            return evaluate(name: "STEP \(index) - Generate", expectation: expectation, context: context, scenario: scenario)
        case .completeTreatment(let name, let minutesAgo, let expectation):
            let completedAt = context.evaluationDate.addingTimeInterval(TimeInterval(-minutesAgo * 60))
            mutateTreatment(nameContains: name, context: &context) { treatment in
                treatment.isCompleted = true
                treatment.isSkipped = false
                treatment.completedAt = completedAt
            }
            return evaluate(name: "STEP \(index) - Complete \(name)", expectation: expectation, context: context, scenario: scenario)
        case .skipTreatment(let name, let expectation):
            let skippedAt = context.evaluationDate
            mutateTreatment(nameContains: name, context: &context) { treatment in
                treatment.isSkipped = true
                treatment.skippedAt = skippedAt
                treatment.isCompleted = false
                treatment.completedAt = nil
            }
            return evaluate(name: "STEP \(index) - Skip \(name)", expectation: expectation, context: context, scenario: scenario)
        case .restoreTreatment(let name, let expectation):
            mutateTreatment(nameContains: name, context: &context) { treatment in
                treatment.isSkipped = false
                treatment.skippedAt = nil
                treatment.isCompleted = false
                treatment.completedAt = nil
            }
            return evaluate(name: "STEP \(index) - Restore \(name)", expectation: expectation, context: context, scenario: scenario)
        case .advance(let minutes, let expectation):
            context.evaluationDate = evaluationDate.addingTimeInterval(TimeInterval(minutes * 60))
            return evaluate(name: "STEP \(index) - Advance \(minutes) min", expectation: expectation, context: context, scenario: scenario)
        case .addVerificationTest(let chemistry, let expectation):
            let prior = context.currentTest
            context.history.insert(prior, at: 0)
            context.currentTest = Self.makeTest(chemistry: chemistry, state: scenario.state, date: context.evaluationDate.addingTimeInterval(60))
            context.evaluationDate = context.currentTest.date.addingTimeInterval(60)
            await generate(context: &context)
            return evaluate(name: "STEP \(index) - Add Verification Test", expectation: expectation, context: context, scenario: scenario)
        }
    }

    private func generate(context: inout ScenarioExecutionContext) async {
        context.currentTest.treatments.removeAll()
        let request = context.request
        guard let response = try? await service.generateRecommendations(for: request) else { return }
        let treatments = response.treatments.map { $0.toTreatment(linkedTo: context.currentTest) }
        treatments.forEach { context.currentTest.treatments.append($0) }
    }

    private func mutateTreatment(nameContains: String, context: inout ScenarioExecutionContext, mutation: (Treatment) -> Void) {
        guard let treatment = context.currentTest.treatments.first(where: { $0.chemicalName.localizedCaseInsensitiveContains(nameContains) && !$0.isWatchlistItem }) else {
            context.mutationFailures.append("Missing treatment containing \(nameContains)")
            return
        }
        mutation(treatment)
    }

    private func evaluate(name: String, expectation: ScenarioExpectation, context: ScenarioExecutionContext, scenario: ScenarioDefinition) -> ScenarioStepResult {
        var failures = context.mutationFailures.map { "\(scenario.id) \(name): \($0)" }
        var assertions = 0
        let treatments = context.currentTest.treatments.filter { !$0.isWatchlistItem }
        let request = context.request
        let assessment = swimabilityEngine.assess(request: request, evaluationDate: context.evaluationDate)
        let classifications = assessment.treatmentAwareContext?.classifications ?? []
        let next = nextTestEngine.routineSchedule(mostRecentFullTestDate: context.currentTest.date, now: context.evaluationDate).firstUpcoming

        func assert(_ condition: Bool, _ message: String) {
            assertions += 1
            if !condition { failures.append("\(scenario.id) \(name): \(message)") }
        }

        if let treatmentCount = expectation.treatmentCount {
            assert(treatments.count == treatmentCount, "expected treatment count \(treatmentCount), actual \(treatments.count)")
        }
        if let treatmentCountMinimum = expectation.treatmentCountMinimum {
            assert(treatments.count >= treatmentCountMinimum, "expected at least \(treatmentCountMinimum) treatments, actual \(treatments.count)")
        }
        if let treatmentCountMaximum = expectation.treatmentCountMaximum {
            assert(treatments.count <= treatmentCountMaximum, "expected at most \(treatmentCountMaximum) treatments, actual \(treatments.count)")
        }
        if let absent = expectation.absentTreatment {
            assert(!treatments.contains { $0.chemicalName.localizedCaseInsensitiveContains(absent) }, "expected no treatment containing \(absent), actual \(treatmentNames(treatments))")
        }
        for treatmentExpectation in expectation.treatments {
            guard let treatment = treatments.first(where: { $0.chemicalName.localizedCaseInsensitiveContains(treatmentExpectation.nameContains) }) else {
                assert(false, "missing expected treatment \(treatmentExpectation.nameContains); actual \(treatmentNames(treatments))")
                continue
            }
            if let amount = treatmentExpectation.amount { assert(abs(treatment.amount - amount) <= max(0.15, amount * 0.08), "\(treatment.chemicalName) amount expected ~\(amount), actual \(treatment.amount)") }
            if let amountMinimum = treatmentExpectation.amountMinimum { assert(treatment.amount >= amountMinimum, "\(treatment.chemicalName) amount expected >= \(amountMinimum), actual \(treatment.amount)") }
            if let amountMaximum = treatmentExpectation.amountMaximum { assert(treatment.amount <= amountMaximum, "\(treatment.chemicalName) amount expected <= \(amountMaximum), actual \(treatment.amount)") }
            if let unit = treatmentExpectation.unit { assert(treatment.unit == unit, "\(treatment.chemicalName) unit expected \(unit), actual \(treatment.unit)") }
            if let urgency = treatmentExpectation.urgency { assert(treatment.urgency == urgency, "\(treatment.chemicalName) urgency expected \(urgency.rawValue), actual \(treatment.urgency.rawValue)") }
            if let badge = treatmentExpectation.badge {
                let actualBadge = TreatmentTimingGuidance.cardTip(for: treatment, requiresVerificationBeforeSwimming: TreatmentTimingGuidance.requiresVerificationBeforeSwimming(for: treatment))
                assert(actualBadge == badge, "\(treatment.chemicalName) badge expected \(badge), actual \(actualBadge ?? "nil")")
            }
            let classification = classifications.first { $0.treatmentID == treatment.id }
            if let category = treatmentExpectation.category { assert(classification?.category == category, "\(treatment.chemicalName) category expected \(category.rawValue), actual \(classification?.category.rawValue ?? "nil")") }
            if let state = treatmentExpectation.completionState { assert(classification?.completionState == state, "\(treatment.chemicalName) completion expected \(state.rawValue), actual \(classification?.completionState.rawValue ?? "nil")") }
            if let calculatedDose = treatmentExpectation.calculatedDose { assert(abs(treatment.calculatedDoseBeforeCap - calculatedDose) <= max(0.2, calculatedDose * 0.12), "\(treatment.chemicalName) calculated dose expected ~\(calculatedDose), actual \(treatment.calculatedDoseBeforeCap)") }
            if let calculatedMinimum = treatmentExpectation.calculatedMinimum { assert(treatment.calculatedDoseBeforeCap >= calculatedMinimum, "\(treatment.chemicalName) calculated dose expected >= \(calculatedMinimum), actual \(treatment.calculatedDoseBeforeCap)") }
            if let calculatedMaximum = treatmentExpectation.calculatedMaximum { assert(treatment.calculatedDoseBeforeCap <= calculatedMaximum, "\(treatment.chemicalName) calculated dose expected <= \(calculatedMaximum), actual \(treatment.calculatedDoseBeforeCap)") }
            if let calculatedUnit = treatmentExpectation.calculatedUnit { assert(treatment.calculatedDoseBeforeCapUnit == calculatedUnit, "\(treatment.chemicalName) calculated unit expected \(calculatedUnit), actual \(treatment.calculatedDoseBeforeCapUnit)") }
            if let wasDoseCapped = treatmentExpectation.wasDoseCapped { assert(treatment.wasDoseCapped == wasDoseCapped, "\(treatment.chemicalName) wasDoseCapped expected \(wasDoseCapped), actual \(treatment.wasDoseCapped)") }
            if let expectedDelta = treatmentExpectation.expectedDelta { assert(abs(treatment.expectedDelta - expectedDelta) <= max(0.05, abs(expectedDelta) * 0.08), "\(treatment.chemicalName) expectedDelta expected ~\(expectedDelta), actual \(treatment.expectedDelta)") }
            if let expectedDeltaMinimum = treatmentExpectation.expectedDeltaMinimum { assert(treatment.expectedDelta >= expectedDeltaMinimum, "\(treatment.chemicalName) expectedDelta expected >= \(expectedDeltaMinimum), actual \(treatment.expectedDelta)") }
            if let expectedDeltaMaximum = treatmentExpectation.expectedDeltaMaximum { assert(treatment.expectedDelta <= expectedDeltaMaximum, "\(treatment.chemicalName) expectedDelta expected <= \(expectedDeltaMaximum), actual \(treatment.expectedDelta)") }
        }
        for (nameFragment, expectedState) in expectation.treatmentStates {
            let classification = classifications.first { $0.treatmentName.localizedCaseInsensitiveContains(nameFragment) }
            assert(classification?.completionState == expectedState, "\(nameFragment) completion expected \(expectedState.rawValue), actual \(classification?.completionState.rawValue ?? "nil")")
        }
        if let v2State = expectation.v2State { assert(assessment.state == v2State, "V2 state expected \(v2State.rawValue), actual \(assessment.state.rawValue)") }
        if let swimmingBlocked = expectation.swimmingBlocked { assert(assessment.swimmingBlocked == swimmingBlocked, "swimmingBlocked expected \(swimmingBlocked), actual \(assessment.swimmingBlocked)") }
        if let testingRequired = expectation.testingRequired { assert(assessment.testingRequired == testingRequired, "testingRequired expected \(testingRequired), actual \(assessment.testingRequired)") }
        if let verificationRequired = expectation.verificationRequired { assert(assessment.treatmentAwareContext?.verificationRequired == verificationRequired, "verificationRequired expected \(verificationRequired), actual \(assessment.treatmentAwareContext?.verificationRequired.description ?? "nil")") }
        for gate in expectation.failedGates { assert(assessment.failedGates.contains { $0.identifier == gate }, "expected failed gate \(gate.rawValue); actual \(assessment.failedGates.map(\.identifier.rawValue))") }
        for gate in expectation.unknownGates { assert(assessment.unknownGates.contains { $0.identifier == gate }, "expected unknown gate \(gate.rawValue); actual \(assessment.unknownGates.map(\.identifier.rawValue))") }
        for gate in expectation.pendingVerificationGates { assert(assessment.treatmentAwareContext?.pendingVerificationGateIdentifiers.contains(gate) == true, "expected pending verification gate \(gate.rawValue); actual \(assessment.treatmentAwareContext?.pendingVerificationGateIdentifiers.map(\.rawValue) ?? [])") }
        if let activeWaitsEmpty = expectation.activeWaitsEmpty { assert((assessment.treatmentAwareContext?.activeWaitDescriptions.isEmpty ?? true) == activeWaitsEmpty, "active waits empty expected \(activeWaitsEmpty), actual \(assessment.treatmentAwareContext?.activeWaitDescriptions ?? [])") }
        if let nextTestPending = expectation.nextTestPending { assert(next.isPendingTreatmentAction == nextTestPending, "next test pending expected \(nextTestPending), actual \(next.isPendingTreatmentAction) title \(next.title)") }
        if let source = expectation.nextTestSource { assert(next.source == source, "next test source expected \(source.rawValue), actual \(next.source.rawValue)") }
        if let minutes = expectation.nextTestMinutesFromCompletedAt {
            if let completedAt = treatments.compactMap(\.completedAt).first, let recommendedDate = next.recommendedDate {
                let actualMinutes = Int(round(recommendedDate.timeIntervalSince(completedAt) / 60))
                assert(abs(actualMinutes - minutes) <= 1, "next test expected completedAt + \(minutes)m, actual +\(actualMinutes)m")
            } else {
                assert(false, "next test completion anchor missing completedAt or recommendedDate")
            }
        }
        if let minutes = expectation.nextTestMinutesFromCurrentTest {
            if let recommendedDate = next.recommendedDate {
                let actualMinutes = Int(round(recommendedDate.timeIntervalSince(context.currentTest.date) / 60))
                assert(abs(actualMinutes - minutes) <= 1, "next test expected current test + \(minutes)m, actual +\(actualMinutes)m")
            } else {
                assert(false, "next test current-test anchor missing recommendedDate")
            }
        }

        return ScenarioStepResult(name: name, expected: describeExpectation(expectation), actual: describeActual(treatments: treatments, classifications: classifications, assessment: assessment, next: next), assertionCount: assertions, failures: failures)
    }

    static func makeTest(chemistry: ScenarioChemistry, state: ScenarioPoolState, date: Date) -> PoolTest {
        PoolTest(date: date, pH: chemistry.pH, freeChlorine: chemistry.freeChlorine, totalChlorine: chemistry.freeChlorine + chemistry.combinedChlorine, totalAlkalinity: chemistry.totalAlkalinity, calciumHardness: chemistry.calciumHardness, cyanuricAcid: chemistry.cyanuricAcid, saltLevel: chemistry.salt, testMethod: .liquidDropKit, poolConditions: state.poolConditions, visualIndicators: state.visualIndicators, waterClarityAssessment: state.clarity, visibleAlgaeAssessment: state.algae)
    }

    private func treatmentNames(_ treatments: [Treatment]) -> String { treatments.map(\.chemicalName).joined(separator: ", ") }

    private func describeExpectation(_ expectation: ScenarioExpectation) -> String {
        var parts: [String] = []
        if let count = expectation.treatmentCount { parts.append("treatments=\(count)") }
        if let state = expectation.v2State { parts.append("v2=\(state.rawValue)") }
        if let blocked = expectation.swimmingBlocked { parts.append("blocked=\(blocked)") }
        if let pending = expectation.nextTestPending { parts.append("nextPending=\(pending)") }
        return parts.isEmpty ? "see assertions" : parts.joined(separator: " | ")
    }

    private func describeActual(treatments: [Treatment], classifications: [V2TreatmentClassification], assessment: SwimabilityV2Assessment, next: NextTestRecommendation) -> String {
        let treatmentText = treatments.map { treatment in
            let classification = classifications.first { $0.treatmentID == treatment.id }
            return "\(treatment.chemicalName) \(treatment.amount) \(treatment.unit) \(treatment.urgency.rawValue) \(classification?.category.rawValue ?? "unclassified")/\(classification?.completionState.rawValue ?? "none")"
        }.joined(separator: "; ")
        return "treatments=[\(treatmentText)] | v2=\(assessment.state.rawValue) blocked=\(assessment.swimmingBlocked) testing=\(assessment.testingRequired) verification=\(assessment.treatmentAwareContext?.verificationRequired ?? false) failed=\(assessment.failedGates.map(\.identifier.rawValue).joined(separator: ",")) pendingVerification=\(assessment.treatmentAwareContext?.pendingVerificationGateIdentifiers.map(\.rawValue).sorted().joined(separator: ",") ?? "") next=\(next.isPendingTreatmentAction ? "pending" : next.source.rawValue)"
    }
}

private struct ScenarioExecutionContext {
    let scenario: ScenarioDefinition
    let config: PoolConfiguration
    var currentTest: PoolTest
    var history: [PoolTest] = []
    var evaluationDate: Date
    var mutationFailures: [String] = []

    init(scenario: ScenarioDefinition, evaluationDate: Date) {
        self.scenario = scenario
        self.config = scenario.config.makePoolConfiguration()
        self.currentTest = ScenarioRunner.makeTest(
            chemistry: scenario.chemistry,
            state: scenario.state,
            date: evaluationDate.addingTimeInterval(TimeInterval(-scenario.currentTestMinutesOld * 60))
        )
        self.history = scenario.history.map { historical in
            ScenarioRunner.makeTest(
                chemistry: historical.chemistry,
                state: historical.state,
                date: evaluationDate.addingTimeInterval(TimeInterval(-historical.daysBefore * 86_400))
            )
        }
        self.evaluationDate = evaluationDate
    }

    var request: AIRecommendationRequest {
        AIRecommendationRequest(currentTest: currentTest, recentHistory: history, poolConfig: config)
    }
}

private struct ScenarioReportFormatter {
    func format(_ result: ScenarioResult) -> String {
        var lines = ["===== POOL SIDE SCENARIO VALIDATION ====="]
        var currentScenarioID = ""
        for entry in result.stepResults {
            if entry.scenario.id != currentScenarioID {
                currentScenarioID = entry.scenario.id
                lines.append("")
                lines.append("SCENARIO: \(entry.scenario.id) — \(entry.scenario.name)")
                lines.append("VALIDATION AREA: \(entry.scenario.area)")
                lines.append("CONFIGURATION: \(configurationDescription(entry.scenario.config))")
                lines.append("HISTORY INPUT: \(historyDescription(entry.scenario.history))")
            }
            lines.append(entry.result.name)
            lines.append("Expected: \(entry.result.expected)")
            lines.append("Actual: \(entry.result.actual)")
            lines.append(entry.result.failures.isEmpty ? "RESULT: PASS" : "RESULT: FAIL")
            for failure in entry.result.failures { lines.append("- \(failure)") }
        }
        lines.append("")
        lines.append("===== SUMMARY =====")
        lines.append("Scenarios: \(Set(result.stepResults.map { $0.scenario.id }).count)")
        lines.append("Scenario steps: \(result.stepResults.count)")
        lines.append("Assertions: \(result.assertionCount)")
        lines.append("Passed: \(result.assertionCount - result.failures.count)")
        lines.append("Failed: \(result.failures.count)")
        lines.append("Failures by validation area:")
        let failuresByArea = Dictionary(grouping: result.stepResults, by: { $0.scenario.area })
            .mapValues { entries in entries.reduce(0) { $0 + $1.result.failures.count } }
            .filter { $0.value > 0 }
        if failuresByArea.isEmpty {
            lines.append("None")
        } else {
            for area in failuresByArea.keys.sorted() {
                lines.append("\(area): \(failuresByArea[area] ?? 0)")
            }
        }
        lines.append("FAILED SCENARIOS:")
        lines.append(result.failures.isEmpty ? "None" : result.failures.joined(separator: "\n"))
        lines.append("===== END POOL SIDE SCENARIO VALIDATION =====")
        return lines.joined(separator: "\n")
    }

    private func configurationDescription(_ config: ScenarioConfig) -> String {
        "volume \(Int(config.volume)) gal | surface \(config.surfaceType.rawValue) | salt \(config.isSaltwater ? "yes" : "no") | chlorine \(config.chlorine.displayName) | pH increaser \(config.pHIncreaser.displayName) | pH decreaser \(config.pHDecreaser.displayName) | alkalinity \(config.alkalinityIncreaser.displayName) | calcium \(config.calciumIncreaser.displayName) | stabilizer \(config.stabilizer.displayName)"
    }

    private func historyDescription(_ history: [ScenarioHistoricalTest]) -> String {
        guard !history.isEmpty else { return "prior tests 0 | prior treatments 0" }
        let pHValues = history.map { String(format: "%.1f", $0.chemistry.pH) }.joined(separator: ", ")
        return "prior tests \(history.count) | prior pH values \(pHValues) | prior treatments 0 | completed acid 0 | completed chlorine 0"
    }

    static func writeDebugReport(_ report: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PoolSideScenarioValidationReport.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
