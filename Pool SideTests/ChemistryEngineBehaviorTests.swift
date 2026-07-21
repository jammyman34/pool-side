import XCTest
@testable import Pool_Side

final class ChemistryEngineBehaviorTests: XCTestCase {
    private let engine = ChemistryEngine()

    func testTreatmentProductSubstitutionsRepriceWithoutChangingGlobalPreference() throws {
        let config = ChemistryTestFixtures.config(pHDecreaser: .dryAcid)
        let test = ChemistryTestFixtures.currentPool()
        let acidTreatment = try actionableTreatment(target: "pH", config: config, test: test, history: ChemistryTestFixtures.pHDriftHistory())
        XCTAssertEqual(acidTreatment.productIdentifier, ChemicalProductID.dryAcid.rawValue)

        let muriatic = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: acidTreatment,
            test: test,
            productID: .muriaticAcid31,
            config: config
        ))

        XCTAssertEqual(muriatic.productID, .muriaticAcid31)
        XCTAssertEqual(config.pHDecreaserPreference, .dryAcid, "One-off substitution must not overwrite the global preference.")
        XCTAssertNotEqual(muriatic.amount, acidTreatment.amount)
        XCTAssertNotEqual(muriatic.unit, acidTreatment.unit)
        XCTAssertTrue(["fl oz", "qt", "gal"].contains(muriatic.unit))
        XCTAssertEqual(muriatic.expectedDelta, acidTreatment.expectedDelta)
        XCTAssertTrue(muriatic.instructions.contains("Never pre-mix"))
        XCTAssertNotEqual(muriatic.productID, muriatic.globalPreferenceProductID, "Substitution flag should be derivable from selected/global product IDs.")

        let lowFume = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: muriatic.toTreatment(linkedTo: test),
            test: test,
            productID: .muriaticAcid20,
            config: ChemistryTestFixtures.config(pHDecreaser: .muriaticAcid)
        ))
        XCTAssertEqual(lowFume.productID, .muriaticAcid20)
        XCTAssertGreaterThan(
            ChemistryTestFixtures.ounces(amount: lowFume.amount, unit: lowFume.unit),
            ChemistryTestFixtures.ounces(amount: muriatic.amount, unit: muriatic.unit),
            "20% acid should require a larger liquid volume than 31.45% acid."
        )
        XCTAssertTrue(lowFume.instructions.contains("weaker than 31.45%"))
    }

    func testChlorineAndStabilizerSubstitutionsRepriceDoseAndUnits() throws {
        let chlorineConfig = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let chlorineTest = ChemistryTestFixtures.currentPool(pH: 7.6, freeChlorine: 1, totalAlkalinity: 100)
        let chlorine = try actionableTreatment(target: "freeChlorine", config: chlorineConfig, test: chlorineTest, history: [])
        let liquid10 = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: chlorine,
            test: chlorineTest,
            productID: .liquidChlorine10,
            config: chlorineConfig
        ))

        XCTAssertEqual(chlorine.productIdentifier, ChemicalProductID.liquidChlorine12_5.rawValue)
        XCTAssertEqual(liquid10.productID, .liquidChlorine10)
        XCTAssertEqual(liquid10.unit, "gal")
        XCTAssertGreaterThan(liquid10.amount, chlorine.amount)
        XCTAssertEqual(liquid10.expectedDelta, chlorine.expectedDelta)
        XCTAssertEqual(chlorineConfig.chlorinePreference, .liquidChlorine12_5)

        let stabilizerConfig = ChemistryTestFixtures.config(stabilizer: .granularCYA)
        let stabilizerTest = ChemistryTestFixtures.currentPool(pH: 7.6, freeChlorine: 4, totalAlkalinity: 100, cyanuricAcid: 20)
        let stabilizer = try actionableTreatment(target: "cyanuricAcid", config: stabilizerConfig, test: stabilizerTest, history: [])
        let liquid = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: stabilizer,
            test: stabilizerTest,
            productID: .liquidStabilizer,
            config: stabilizerConfig
        ))

        XCTAssertEqual(stabilizer.productIdentifier, ChemicalProductID.granularCYA.rawValue)
        XCTAssertEqual(liquid.productID, .liquidStabilizer)
        XCTAssertEqual(liquid.unit, "gal")
        XCTAssertNotEqual(liquid.unit, stabilizer.unit)
        XCTAssertEqual(liquid.expectedDelta, stabilizer.expectedDelta)
        XCTAssertTrue(liquid.instructions.contains("Liquid conditioner"))
    }

    func testAlgaeRecoveryChlorineUsesConfiguredLiquidStrengthAndCanBeRepriced() async throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 4,
            totalChlorine: 4,
            totalAlkalinity: 100,
            cyanuricAcid: 60,
            visualIndicators: [VisualIndicator.algaeSpots.rawValue]
        )
        let service = RuleBasedService()
        let response = try await service.generateRecommendations(
            for: AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        )
        let recovery = try XCTUnwrap(response.treatments.first {
            $0.actionDescription.contains("algae recovery")
        })

        XCTAssertEqual(recovery.productID, .liquidChlorine12_5)
        XCTAssertEqual(recovery.chemicalName, "Liquid Chlorine 12.5%")
        XCTAssertEqual(recovery.targetParameter, "freeChlorine")
        XCTAssertEqual(recovery.expectedEffectParameter, "freeChlorine")
        XCTAssertGreaterThan(recovery.expectedDelta, 0)

        let liquid10 = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: recovery.toTreatment(linkedTo: test),
            test: test,
            productID: .liquidChlorine10,
            config: config
        ))

        XCTAssertEqual(liquid10.productID, .liquidChlorine10)
        XCTAssertGreaterThan(liquid10.amount, recovery.amount)
        XCTAssertEqual(liquid10.expectedDelta, recovery.expectedDelta)
    }

    func testAcidDosingUsesProductUnitsPreCapAndConservativeTarget() throws {
        let test = ChemistryTestFixtures.currentPool()
        let history = ChemistryTestFixtures.pHDriftHistory()
        let dryConfig = ChemistryTestFixtures.config(pHDecreaser: .dryAcid)
        let dryAcid = try actionableTreatment(target: "pH", config: dryConfig, test: test, history: history)

        XCTAssertEqual(dryAcid.productIdentifier, ChemicalProductID.dryAcid.rawValue)
        XCTAssertEqual(dryAcid.unit, "lbs")
        XCTAssertFalse(dryAcid.wasDoseCapped)
        XCTAssertGreaterThan(dryAcid.calculatedDoseBeforeCap, 0)
        XCTAssertLessThan(dryAcid.amount, 6, "Dry acid should not reuse liquid-acid fluid ounces as dry-acid weight.")
        XCTAssertGreaterThanOrEqual(test.pH + dryAcid.expectedDelta, 7.5)
        XCTAssertLessThanOrEqual(test.pH + dryAcid.expectedDelta, 7.6)

        let muriatic = try XCTUnwrap(engine.repricedTreatmentTemplate(from: dryAcid, test: test, productID: .muriaticAcid31, config: dryConfig))
        let lowFume = try XCTUnwrap(engine.repricedTreatmentTemplate(from: dryAcid, test: test, productID: .muriaticAcid20, config: dryConfig))

        XCTAssertTrue(["fl oz", "qt", "gal"].contains(muriatic.unit))
        XCTAssertGreaterThan(lowFume.calculatedDoseBeforeCap, muriatic.calculatedDoseBeforeCap)
        XCTAssertGreaterThan(
            ChemistryTestFixtures.ounces(amount: lowFume.amount, unit: lowFume.unit),
            ChemistryTestFixtures.ounces(amount: muriatic.amount, unit: muriatic.unit)
        )
        XCTAssertEqual(muriatic.wasDoseCapped, ChemistryTestFixtures.ounces(amount: muriatic.calculatedDoseBeforeCap, unit: muriatic.calculatedDoseBeforeCapUnit) > ChemistryTestFixtures.ounces(amount: muriatic.amount, unit: muriatic.unit))
        XCTAssertEqual(lowFume.wasDoseCapped, ChemistryTestFixtures.ounces(amount: lowFume.calculatedDoseBeforeCap, unit: lowFume.calculatedDoseBeforeCapUnit) > ChemistryTestFixtures.ounces(amount: lowFume.amount, unit: lowFume.unit))
    }

    func testPHHistoryAllowsConservativeAcidAndAvoidsContradictoryWatchlist() throws {
        let test = ChemistryTestFixtures.currentPool()
        let treatments = engine.validatedTreatments(
            for: test,
            config: ChemistryTestFixtures.config(pHDecreaser: .dryAcid),
            recentHistory: ChemistryTestFixtures.pHDriftHistory()
        )

        let acid = try XCTUnwrap(treatments.first { $0.targetParameter == "pH" && $0.amount > 0 })
        XCTAssertTrue(acid.actionDescription.contains("gradually risen"))
        XCTAssertTrue(acid.actionDescription.contains("TA stayed elevated"))
        XCTAssertTrue(acid.actionDescription.contains("no acid treatment"))
        XCTAssertFalse(treatments.contains { $0.actionDescription == "TA is elevated, but pH does not currently justify acid." })
    }

    func testRecentCompletedAcidSuppressesDuplicateDoseDuringWaitWindow() throws {
        let test = ChemistryTestFixtures.currentPool()
        let recent = ChemistryTestFixtures.historicalTest(daysAgo: 1, pH: 7.8, totalAlkalinity: 170)
        recent.treatments.append(ChemistryTestFixtures.activeCompletedAcidTreatment())

        let treatments = engine.validatedTreatments(
            for: test,
            config: ChemistryTestFixtures.config(pHDecreaser: .muriaticAcid),
            recentHistory: [recent] + ChemistryTestFixtures.pHDriftHistory()
        )

        XCTAssertFalse(treatments.contains { $0.isAcidTreatment && $0.amount > 0 }, "Duplicate acid dose should be suppressed while the prior treatment is active.")
        let advisory = try XCTUnwrap(treatments.first { $0.chemicalName == "Wait for Acid Treatment" })
        XCTAssertTrue(advisory.actionDescription.contains("withheld"))
        XCTAssertTrue(advisory.instructions.contains("previous acid dose"))
    }

    func testSaltGeneratorUsesGeneratorForModestDeficitAndSupplementalChlorineForUrgentDeficit() throws {
        var config = ChemistryTestFixtures.config(volume: 20_000, chlorine: .liquidChlorine12_5)
        config.setSaltwater(true)

        let modest = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 3.7,
            totalChlorine: 3.7,
            totalAlkalinity: 100,
            cyanuricAcid: 40
        )
        let modestTreatments = engine.validatedTreatments(for: modest, config: config, recentHistory: [])
        let generator = try XCTUnwrap(modestTreatments.first { $0.productID == .saltGenerator })
        XCTAssertEqual(generator.amount, 0)
        XCTAssertTrue(generator.instructions.contains("Increase salt generator output"))
        XCTAssertTrue(generator.instructions.contains("depends on the generator capacity"))
        XCTAssertFalse(modestTreatments.contains { $0.chemicalName.contains("Liquid Chlorine") && $0.amount > 0 })

        let urgent = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 0.5,
            totalChlorine: 1.2,
            totalAlkalinity: 100,
            cyanuricAcid: 55,
            visualIndicators: [VisualIndicator.cloudyWater.rawValue]
        )
        let urgentTreatments = engine.validatedTreatments(for: urgent, config: config, recentHistory: [])
        let supplemental = try XCTUnwrap(urgentTreatments.first { $0.productID == .liquidChlorine12_5 })
        XCTAssertGreaterThan(supplemental.amount, 0)
        XCTAssertTrue(supplemental.actionDescription.contains("faster recovery than the salt generator"))
    }

    func testStatusLabelsAvoidRecoveryForMaintenanceCaseAndReserveRecoveryForProblemWater() {
        let config = ChemistryTestFixtures.config()
        let maintenance = ChemistryTestFixtures.currentPool()

        XCTAssertNotEqual(engine.currentStatusSummary(for: maintenance, config: config), "Recovery")
        XCTAssertEqual(engine.currentStatusSummary(for: ChemistryTestFixtures.currentPool(visualIndicators: [VisualIndicator.algaeSpots.rawValue]), config: config), "Recovery")
        XCTAssertEqual(engine.currentStatusSummary(for: ChemistryTestFixtures.currentPool(visualIndicators: [VisualIndicator.cloudyWater.rawValue]), config: config), "Recovery")
        XCTAssertEqual(engine.currentStatusSummary(for: ChemistryTestFixtures.currentPool(pH: 8.1), config: config), "Recovery")
        XCTAssertEqual(engine.currentStatusSummary(for: ChemistryTestFixtures.currentPool(totalChlorine: 2.3), config: config), "Recovery")
    }

    func testCombinedChlorineThresholdsUseSeverityAndPoolContext() {
        let config = ChemistryTestFixtures.config()
        let clearBalanced = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 6,
            totalChlorine: 6,
            totalAlkalinity: 100,
            cyanuricAcid: 55
        )

        clearBalanced.totalChlorine = 6.4
        XCTAssertNotEqual(engine.currentStatusSummary(for: clearBalanced, config: config), "Recovery", "CC below 0.5 should not trigger Recovery.")

        clearBalanced.totalChlorine = 6.5
        XCTAssertNotEqual(engine.currentStatusSummary(for: clearBalanced, config: config), "Recovery", "Borderline 0.5 CC should not become Recovery by itself.")

        clearBalanced.totalChlorine = 6.7
        XCTAssertEqual(engine.currentStatusSummary(for: clearBalanced, config: config), "Needs Attention", "Mildly elevated CC with clear water and adequate FC should be attention, not Recovery.")

        clearBalanced.totalChlorine = 7.2
        XCTAssertEqual(engine.currentStatusSummary(for: clearBalanced, config: config), "Needs Attention", "CC above 1.0 without problem-water context should not automatically be Recovery.")

        let lowFCWithHighCC = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 1,
            totalChlorine: 2.2,
            totalAlkalinity: 100,
            cyanuricAcid: 55
        )
        XCTAssertEqual(engine.currentStatusSummary(for: lowFCWithHighCC, config: config), "Recovery")

        let cloudyHighCC = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 6,
            totalChlorine: 7.2,
            totalAlkalinity: 100,
            cyanuricAcid: 55,
            visualIndicators: [VisualIndicator.cloudyWater.rawValue]
        )
        XCTAssertEqual(engine.currentStatusSummary(for: cloudyHighCC, config: config), "Recovery")

        let odorHighCC = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 6,
            totalChlorine: 7.2,
            totalAlkalinity: 100,
            cyanuricAcid: 55,
            visualIndicators: [VisualIndicator.crystalClear.rawValue, VisualIndicator.strongChlorineSmell.rawValue]
        )
        XCTAssertEqual(engine.currentStatusSummary(for: odorHighCC, config: config), "Recovery")
    }

    func testTimingTipsDistinguishNextTreatmentWaitFromSingleTreatmentVerification() throws {
        let chlorine = timingTreatment(
            name: "Liquid Chlorine 12.5%",
            target: "freeChlorine",
            amount: 1,
            productID: .liquidChlorine12_5,
            minutesBeforeNext: 60
        )
        let acid = timingTreatment(
            name: "Dry Acid (Sodium Bisulfate)",
            target: "pH",
            amount: 3.7,
            productID: .dryAcid,
            minutesBeforeNext: 240,
            expectedDelta: -0.2
        )
        let calcium = timingTreatment(
            name: "Calcium Chloride",
            target: "calciumHardness",
            amount: 4,
            productID: .calciumChloride
        )
        let watchlist = timingTreatment(
            name: "Monitor CYA",
            target: "cyanuricAcid",
            amount: 0,
            productID: .granularCYA,
            urgency: .advisory
        )

        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine, nextActionableTreatment: acid),
            "Wait ~1 hr before adding acid.",
            "Chlorine followed by acid should use the concise acid-specific wait copy."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine),
            "Circulate ~1 hr before swimming.",
            "Final or only chlorine treatment should not mention a next treatment or optional FC check."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: acid),
            "Circulate ~4 hrs before swimming.",
            "Final acid treatment should communicate circulation/swim timing without scheduling a pH test."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: acid, nextActionableTreatment: calcium),
            "Wait ~4 hr before the next chemical.",
            "Acid with a genuine following treatment should mention the next chemical."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine, nextActionableTreatment: watchlist),
            "Circulate ~1 hr before swimming.",
            "Watchlist rows must not be treated as subsequent actionable treatments."
        )
    }

    func testNextPoolTestSeparatesRoutineTestingFromSameDayVerification() {
        let config = ChemistryTestFixtures.config()
        let routineTest = ChemistryTestFixtures.currentPool(pH: 7.6, freeChlorine: 1, totalChlorine: 1, totalAlkalinity: 100)
        let routineTreatments = engine.validatedTreatments(for: routineTest, config: config, recentHistory: [])
            .map { $0.toTreatment(linkedTo: routineTest) }
        let routineRecommendation = NextTestRecommendationEngine().recommendation(
            for: routineTest,
            treatmentSteps: routineTreatments,
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertEqual(routineRecommendation.source, .treatmentPlan)
        XCTAssertEqual(routineRecommendation.title, "Next pool test")
        XCTAssertEqual(routineRecommendation.interval, 86_400)
        XCTAssertTrue(routineRecommendation.body.contains("Same-day checks are optional"))

        let urgentTest = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 0.5,
            totalChlorine: 1.2,
            totalAlkalinity: 100,
            visualIndicators: [VisualIndicator.cloudyWater.rawValue]
        )
        let urgentTreatments = engine.validatedTreatments(for: urgentTest, config: config, recentHistory: [])
            .map { $0.toTreatment(linkedTo: urgentTest) }
        let urgentRecommendation = NextTestRecommendationEngine().recommendation(
            for: urgentTest,
            treatmentSteps: urgentTreatments,
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertEqual(urgentRecommendation.source, .chlorineCorrection)
        XCTAssertLessThanOrEqual(urgentRecommendation.interval, 3_600)
    }

    func testScoreStatusLabelDoesNotUseRecoveryForLowScoreWithoutRecoveryContext() {
        let config = ChemistryTestFixtures.config()
        let maintenance = ChemistryTestFixtures.currentPool()
        let status = engine.currentStatusSummary(for: maintenance, config: config)

        XCTAssertNotEqual(status, "Recovery")
        XCTAssertNotEqual(ChemistryEngine.scoreStatusLabel(score: 43, status: status), "Problem Recovery")
        XCTAssertEqual(ChemistryEngine.scoreStatusLabel(score: 43, status: status), "Needs Attention")
        XCTAssertEqual(ChemistryEngine.scoreStatusLabel(score: 43, status: "Recovery"), "Problem Recovery")
    }

    func testTreatmentPlanHeroCountUsesActionableTreatmentCount() {
        XCTAssertEqual(TreatmentPlanSummaryText.heroTitle(actionableTreatmentCount: 2), "2 treatments")
        XCTAssertEqual(TreatmentPlanSummaryText.heroTitle(actionableTreatmentCount: 1), "1 treatment")
        XCTAssertEqual(TreatmentPlanSummaryText.heroTitle(actionableTreatmentCount: 0), "No treatments today")
    }

    func testTreatmentPlanDeveloperRecalculateActionEligibility() {
        XCTAssertTrue(TreatmentPlanDeveloperRecalculateAction.canPresent(isRecalculating: false))
        XCTAssertFalse(TreatmentPlanDeveloperRecalculateAction.canPresent(isRecalculating: true))
    }

    func testMaintenanceTopOffDoesNotCreateMandatorySameDayVerification() throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 4.5,
            totalChlorine: 5.0,
            totalAlkalinity: 170,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        test.poolConditions = PoolConditions(
            rainLoad: .light,
            waterAdded: .oneToTwoInches
        )

        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])
        let chlorine = try XCTUnwrap(treatments.first { $0.targetParameter == "freeChlorine" && $0.amount > 0 })
        XCTAssertEqual(chlorine.urgency, .optional)
        XCTAssertTrue(chlorine.actionDescription.contains("Maintenance top-off"))
        XCTAssertTrue(chlorine.instructions.contains("Circulate for 60 minutes before swimming."))

        let savedTreatments = treatments.map { $0.toTreatment(linkedTo: test) }
        let treatmentSteps = savedTreatments.filter { !$0.isWatchlistItem }
        let watchlist = savedTreatments.filter { $0.isWatchlistItem }
        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: treatmentSteps,
            watchlist: watchlist,
            recentHistory: [],
            config: config
        )

        XCTAssertEqual(recommendation.source, .treatmentPlan)
        XCTAssertEqual(recommendation.title, "Next pool test")
        XCTAssertEqual(recommendation.interval, 86_400)
        XCTAssertFalse(recommendation.reason.contains("same-day verification"))
    }

    func testDogfoodWatchlistCopyStaysNonurgentAndProportional() {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 4.5,
            totalChlorine: 5.0,
            totalAlkalinity: 170,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        test.poolConditions = PoolConditions(
            rainLoad: .light,
            waterAdded: .oneToTwoInches
        )

        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Monitor Elevated pH" })
        XCTAssertTrue(treatments.contains { $0.chemicalName == "Monitor pH Trend" })
        XCTAssertTrue(treatments.contains { $0.actionDescription.contains("pH is currently acceptable") })
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Manage Elevated CYA" })
        XCTAssertTrue(treatments.contains { $0.chemicalName == "Maintain Higher FC for Current CYA" })
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Possible Dilution" })
        XCTAssertFalse(treatments.contains { $0.instructions.localizedCaseInsensitiveContains("salt") })
    }

    func testGenuinelyLowChlorineStillRequiresSameDayVerification() {
        let config = ChemistryTestFixtures.config()
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 0.5,
            totalChlorine: 1.2,
            totalAlkalinity: 100,
            cyanuricAcid: 55,
            visualIndicators: [VisualIndicator.cloudyWater.rawValue]
        )
        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])
            .map { $0.toTreatment(linkedTo: test) }
        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: treatments.filter { !$0.isWatchlistItem },
            watchlist: treatments.filter { $0.isWatchlistItem },
            recentHistory: [],
            config: config
        )

        XCTAssertEqual(recommendation.source, .chlorineCorrection)
        XCTAssertLessThanOrEqual(recommendation.interval, 3_600)
    }

    func testWatchlistPresentationText() {
        XCTAssertFalse(WatchlistPresentationText.shouldShow(count: 0))
        XCTAssertEqual(WatchlistPresentationText.summary(count: 1), "1 item to monitor")
        XCTAssertEqual(WatchlistPresentationText.summary(count: 5), "5 items to monitor")
    }

    private func actionableTreatment(
        target: String,
        config: PoolConfiguration,
        test: PoolTest,
        history: [PoolTest]
    ) throws -> Treatment {
        let template = try XCTUnwrap(engine.validatedTreatments(for: test, config: config, recentHistory: history).first {
            $0.targetParameter == target && $0.amount > 0
        })
        return template.toTreatment(linkedTo: test)
    }

    private func timingTreatment(
        name: String,
        target: String,
        amount: Double,
        productID: ChemicalProductID,
        urgency: TreatmentUrgency = .recommended,
        minutesBeforeNext: Int = 0,
        expectedDelta: Double = 0
    ) -> Treatment {
        Treatment(
            chemicalName: name,
            actionDescription: "",
            amount: amount,
            unit: amount > 0 ? "lbs" : "",
            productIdentifier: productID.rawValue,
            globalPreferenceIdentifier: productID.rawValue,
            instructions: "",
            urgency: urgency,
            targetParameter: target,
            minutesBeforeNext: minutesBeforeNext,
            expectedEffectParameter: target,
            expectedDelta: expectedDelta
        )
    }
}
