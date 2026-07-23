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
        XCTAssertNotEqual(muriatic.unit, acidTreatment.unit)
        XCTAssertTrue(["fl oz", "qt", "gal"].contains(muriatic.unit))
        XCTAssertGreaterThan(muriatic.calculatedDoseBeforeCap, 0)
        XCTAssertTrue(["fl oz", "qt", "gal"].contains(muriatic.calculatedDoseBeforeCapUnit))
        XCTAssertEqual(
            muriatic.wasDoseCapped,
            ChemistryTestFixtures.ounces(amount: muriatic.calculatedDoseBeforeCap, unit: muriatic.calculatedDoseBeforeCapUnit) > ChemistryTestFixtures.ounces(amount: muriatic.amount, unit: muriatic.unit)
        )
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

    func testBakingSodaDoseUsesTenThousandGallonScaling() throws {
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 50,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let treatment = try actionableTreatment(
            target: "totalAlkalinity",
            config: ChemistryTestFixtures.config(volume: 32_583),
            test: test,
            history: []
        )

        XCTAssertEqual(treatment.chemicalName, "Baking Soda (Sodium Bicarbonate)")
        XCTAssertEqual(treatment.amount, 13.7, accuracy: 0.001)
        XCTAssertEqual(treatment.unit, "lbs")
        XCTAssertEqual(treatment.calculatedDoseBeforeCap, 13.7, accuracy: 0.001)
        XCTAssertFalse(treatment.wasDoseCapped)
        XCTAssertEqual(treatment.effectDelayHours, 8)
        let bakingSodaRepeatDelay = try XCTUnwrap(treatment.doNotRepeatBefore?.timeIntervalSince(treatment.createdAt))
        XCTAssertEqual(bakingSodaRepeatDelay, 28_800, accuracy: 1)
    }

    func testBakingSodaDoseScalesWithVolumeAndAlkalinityDeficit() throws {
        let tenThousandGallonTA50 = try actionableTreatment(
            target: "totalAlkalinity",
            config: ChemistryTestFixtures.config(volume: 10_000),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 50, cyanuricAcid: 60),
            history: []
        )
        let twentyThousandGallonTA50 = try actionableTreatment(
            target: "totalAlkalinity",
            config: ChemistryTestFixtures.config(volume: 20_000),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 50, cyanuricAcid: 60),
            history: []
        )
        let tenThousandGallonTA60 = try actionableTreatment(
            target: "totalAlkalinity",
            config: ChemistryTestFixtures.config(volume: 10_000),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 60, cyanuricAcid: 60),
            history: []
        )

        XCTAssertEqual(tenThousandGallonTA50.amount, 4.2, accuracy: 0.001)
        XCTAssertEqual(twentyThousandGallonTA50.amount, tenThousandGallonTA50.amount * 2, accuracy: 0.001)
        XCTAssertEqual(tenThousandGallonTA60.amount, 2.8, accuracy: 0.001)
        XCTAssertEqual(tenThousandGallonTA50.unit, "lbs")
    }

    func testTC7LowCYAGeneratesPlausibleStabilizerDoseOnly() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583, stabilizer: .granularCYA)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 20
        )
        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])
        let stabilizer = try XCTUnwrap(treatments.first { $0.targetParameter == "cyanuricAcid" && $0.amount > 0 })

        XCTAssertEqual(stabilizer.chemicalName, "Cyanuric Acid (Granular)")
        XCTAssertEqual(stabilizer.expectedDelta, 20, accuracy: 0.001)
        XCTAssertEqual(stabilizer.amount, 5.3, accuracy: 0.001)
        XCTAssertEqual(stabilizer.unit, "lbs")
        XCTAssertEqual(stabilizer.calculatedDoseBeforeCap, 5.3, accuracy: 0.001)
        XCTAssertFalse(stabilizer.wasDoseCapped)
        XCTAssertEqual(stabilizer.effectDelayHours, TreatmentApplicationPolicy.granularCYACanonicalRetestHours)
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Remove Chlorine Source" })
    }

    func testCYADoseScalesWithVolumeAndRequiredIncrease() throws {
        let tenThousandGallonCYA20 = try actionableTreatment(
            target: "cyanuricAcid",
            config: ChemistryTestFixtures.config(volume: 10_000, stabilizer: .granularCYA),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 100, cyanuricAcid: 20),
            history: []
        )
        let twentyThousandGallonCYA20 = try actionableTreatment(
            target: "cyanuricAcid",
            config: ChemistryTestFixtures.config(volume: 20_000, stabilizer: .granularCYA),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 100, cyanuricAcid: 20),
            history: []
        )
        let tenThousandGallonCYA10 = try actionableTreatment(
            target: "cyanuricAcid",
            config: ChemistryTestFixtures.config(volume: 10_000, stabilizer: .granularCYA),
            test: ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6.5, totalChlorine: 7.0, totalAlkalinity: 100, cyanuricAcid: 10),
            history: []
        )

        XCTAssertEqual(tenThousandGallonCYA20.amount, 1.6, accuracy: 0.001)
        XCTAssertEqual(twentyThousandGallonCYA20.amount, 3.3, accuracy: 0.001)
        XCTAssertEqual(tenThousandGallonCYA10.amount, 2.4, accuracy: 0.001)
    }

    func testElevatedButBelowShockChlorineDoesNotGenerateRemovalAction() {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 20
        )

        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])

        XCTAssertFalse(treatments.contains { $0.chemicalName == "Remove Chlorine Source" })
    }

    func testGenuinelyExcessiveChlorineStillGeneratesProtectionAction() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 10.5,
            totalChlorine: 10.5,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 20
        )

        let treatments = engine.validatedTreatments(for: test, config: config, recentHistory: [])
        let removal = try XCTUnwrap(treatments.first { $0.chemicalName == "Remove Chlorine Source" })

        XCTAssertEqual(removal.amount, 0)
        XCTAssertTrue(removal.actionDescription.contains("CYA-adjusted recovery level"))
    }

    func testPoolCareBakingSodaTimingDoesNotBlockSwimming() throws {
        let bakingSoda = timingTreatment(
            name: "Baking Soda (Sodium Bicarbonate)",
            target: "totalAlkalinity",
            amount: 13.7,
            productID: .bakingSoda,
            minutesBeforeNext: 240
        )
        let acid = timingTreatment(
            name: "Dry Acid (Sodium Bisulfate)",
            target: "pH",
            amount: 3.7,
            productID: .dryAcid
        )

        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: bakingSoda),
            "Retest TA after 6-8 hrs"
        )
        XCTAssertFalse(TreatmentTimingGuidance.cardTip(for: bakingSoda)?.contains("before swimming") ?? true)
        XCTAssertEqual(
            TreatmentTimingGuidance.timingGuidance(for: bakingSoda),
            "Allow 6-8 hrs to circulate before retesting alkalinity or making another alkalinity adjustment."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: bakingSoda, nextActionableTreatment: acid),
            "Wait ~4 hrs before next chemical"
        )
    }

    func testHighPHWithLowAlkalinityDoesNotGenerateConflictingBakingSoda() throws {
        let test = ChemistryTestFixtures.currentPool(
            pH: 8.1,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 50,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let treatments = engine.validatedTreatments(
            for: test,
            config: ChemistryTestFixtures.config(pHDecreaser: .muriaticAcid),
            recentHistory: []
        )

        XCTAssertNotNil(treatments.first { $0.targetParameter == "pH" && $0.amount > 0 })
        XCTAssertFalse(treatments.contains { $0.productID == .bakingSoda && $0.amount > 0 })
        let alkalinityAdvisory = try XCTUnwrap(treatments.first { $0.chemicalName == "Correct pH Before Raising Alkalinity" })
        XCTAssertEqual(alkalinityAdvisory.amount, 0)
        XCTAssertEqual(alkalinityAdvisory.urgency, .advisory)
    }

    func testHighPHWithHighAlkalinityDoesNotGenerateDuplicateAcidCorrections() throws {
        let test = ChemistryTestFixtures.currentPool(
            pH: 8.1,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 170,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let treatments = engine.validatedTreatments(
            for: test,
            config: ChemistryTestFixtures.config(pHDecreaser: .muriaticAcid),
            recentHistory: []
        )

        let acidTreatments = treatments.filter { $0.isAcidTreatment && $0.amount > 0 }
        XCTAssertEqual(acidTreatments.count, 1)
        XCTAssertEqual(acidTreatments.first?.targetParameter, "pH")
        XCTAssertFalse(treatments.contains { $0.targetParameter == "totalAlkalinity" && $0.isAcidTreatment && $0.amount > 0 })
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

    func testTC8CalciumHardnessDoseUsesTenThousandGallonScaling() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 100,
            cyanuricAcid: 60
        )
        let treatment = try actionableTreatment(target: "calciumHardness", config: config, test: test, history: [])

        XCTAssertEqual(treatment.chemicalName, "Calcium Hardness Increaser (Calcium Chloride)")
        XCTAssertEqual(treatment.expectedDelta, 100, accuracy: 0.001)
        XCTAssertEqual(treatment.amount, 40.7, accuracy: 0.001)
        XCTAssertEqual(treatment.unit, "lbs")
        XCTAssertEqual(treatment.calculatedDoseBeforeCap, 40.7, accuracy: 0.001)
        XCTAssertFalse(treatment.wasDoseCapped)
        XCTAssertEqual(treatment.effectDelayHours, TreatmentApplicationPolicy.calciumChlorideRetestHours)
        XCTAssertLessThan(treatment.amount, 60)
    }

    func testMuriaticAcidDoseForHighPHUsesAuditedLiquidUnits() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583, pHDecreaser: .muriaticAcid)
        let test = ChemistryTestFixtures.currentPool(
            pH: 8.0,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 140,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let treatment = try actionableTreatment(target: "pH", config: config, test: test, history: ChemistryTestFixtures.pHDriftHistory())

        XCTAssertEqual(treatment.chemicalName, "Muriatic Acid (31.45%)")
        XCTAssertEqual(treatment.expectedDelta, -0.5, accuracy: 0.001)
        XCTAssertEqual(treatment.amount, 1.5, accuracy: 0.001)
        XCTAssertEqual(treatment.unit, "qt")
        XCTAssertEqual(treatment.calculatedDoseBeforeCap, 4.0, accuracy: 0.001)
        XCTAssertTrue(treatment.wasDoseCapped)
        XCTAssertTrue(treatment.instructions.contains("repeat only after a new test still calls for acid"))
    }

    func testDryAcidDoseForHighPHUsesAuditedWeightUnits() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583, pHDecreaser: .dryAcid)
        let test = ChemistryTestFixtures.currentPool(
            pH: 8.0,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 140,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let treatment = try actionableTreatment(target: "pH", config: config, test: test, history: ChemistryTestFixtures.pHDriftHistory())

        XCTAssertEqual(treatment.chemicalName, "Dry Acid (Sodium Bisulfate)")
        XCTAssertEqual(treatment.expectedDelta, -0.5, accuracy: 0.001)
        XCTAssertEqual(treatment.amount, 2.9, accuracy: 0.001)
        XCTAssertEqual(treatment.unit, "lbs")
        XCTAssertEqual(treatment.calculatedDoseBeforeCap, 2.9, accuracy: 0.001)
        XCTAssertFalse(treatment.wasDoseCapped)
        XCTAssertLessThan(treatment.amount, 6)
    }

    func testSaltAdditionDoseUsesTenThousandGallonScaling() throws {
        var config = ChemistryTestFixtures.config(volume: 10_000, isSaltwater: true)
        config.setSaltwater(true)
        let test = PoolTest(
            date: ChemistryTestFixtures.baseDate,
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60,
            saltLevel: 2_500,
            testMethod: .liquidDropKit,
            visualIndicators: [VisualIndicator.crystalClear.rawValue]
        )
        let treatment = try actionableTreatment(target: "saltLevel", config: config, test: test, history: [])

        XCTAssertEqual(treatment.chemicalName, "Pool Salt")
        XCTAssertEqual(treatment.expectedDelta, 700, accuracy: 0.001)
        XCTAssertEqual(treatment.amount, 58.3, accuracy: 0.001)
        XCTAssertEqual(treatment.unit, "lbs")
        XCTAssertEqual(treatment.calculatedDoseBeforeCap, 58.3, accuracy: 0.001)
        XCTAssertFalse(treatment.wasDoseCapped)
    }

    func testDryChlorineSubstitutionsUseAuditedWeightUnits() throws {
        let config = ChemistryTestFixtures.config(volume: 10_000, chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 3.5,
            totalChlorine: 3.5,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        let chlorine = try actionableTreatment(target: "freeChlorine", config: config, test: test, history: [])
        let calHypo = try XCTUnwrap(engine.repricedTreatmentTemplate(from: chlorine, test: test, productID: .calHypoGranules, config: config))
        let dichlor = try XCTUnwrap(engine.repricedTreatmentTemplate(from: chlorine, test: test, productID: .dichlorGranules, config: config))

        XCTAssertEqual(chlorine.expectedDelta, 3.5, accuracy: 0.001)
        XCTAssertEqual(calHypo.amount, 0.44, accuracy: 0.001)
        XCTAssertEqual(calHypo.unit, "lbs")
        XCTAssertEqual(dichlor.amount, 0.55, accuracy: 0.001)
        XCTAssertEqual(dichlor.unit, "lbs")
    }

    func testAcuteFCDeficitWithTabletPreferenceUsesImmediateChlorineAndTrichlorRepriceUsesLabelDose() throws {
        let config = ChemistryTestFixtures.config(volume: 10_000, chlorine: .tablets)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 3.5,
            totalChlorine: 3.5,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 30
        )

        let treatment = try actionableTreatment(target: "freeChlorine", config: config, test: test, history: [])
        let trichlor = try XCTUnwrap(engine.repricedTreatmentTemplate(
            from: treatment,
            test: test,
            productID: .trichlorTablets,
            config: config
        ))

        XCTAssertEqual(treatment.productIdentifier, ChemicalProductID.liquidChlorine10.rawValue)
        XCTAssertEqual(treatment.unit, "gal")
        XCTAssertGreaterThan(treatment.expectedDelta, 0)
        XCTAssertEqual(trichlor.productID, .trichlorTablets)
        XCTAssertEqual(trichlor.amount, 1, accuracy: 0.001)
        XCTAssertEqual(trichlor.unit, "dose per label")
        XCTAssertEqual(trichlor.expectedDelta, 0, accuracy: 0.001)
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
            cyanuricAcid: 40
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
        let cya = timingTreatment(
            name: "Cyanuric Acid",
            target: "cyanuricAcid",
            amount: 2,
            productID: .granularCYA
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
            "Wait ~1 hr before acid",
            "Chlorine followed by acid should use compact acid-specific wait copy."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine),
            "Swim after ~1 hr",
            "Final or only routine chlorine should stay compact without mentioning an optional FC check."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: acid),
            "Swim after ~4 hrs",
            "Final acid treatment should communicate circulation/swim timing compactly when verification is not required."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: acid, requiresVerificationBeforeSwimming: true),
            "Test pH after ~4 hrs",
            "Corrective acid for unsafe pH should not imply elapsed circulation alone grants swim readiness."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: acid, nextActionableTreatment: calcium),
            "Wait ~4 hrs before next chemical",
            "Acid with a genuine following treatment should mention the next chemical compactly."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine, nextActionableTreatment: watchlist),
            "Swim after ~1 hr",
            "Watchlist rows must not be treated as subsequent actionable treatments."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: cya),
            "Retest CYA after 24-48 hrs",
            "Stabilizer should use compact pool-care timing copy."
        )
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(for: chlorine, requiresVerificationBeforeSwimming: true),
            "Test before swimming",
            "Recovery or mandatory-verification chlorine must not imply circulation alone grants swim readiness."
        )

        XCTAssertEqual(
            TreatmentTimingGuidance.timingGuidance(for: acid, requiresVerificationBeforeSwimming: true),
            "Circulate ~4 hrs, then test pH before swimming.",
            "Long-form timing guidance should remain explicit outside the compact badge."
        )
    }

    func testRecoveryChlorineAndCloudyWaterActionsDoNotDuplicateTestingAuthority() async throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 1,
            totalChlorine: 2,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60,
            visualIndicators: [
                VisualIndicator.cloudyWater.rawValue,
                VisualIndicator.algaeSpots.rawValue
            ]
        )
        let response = try await RuleBasedService().generateRecommendations(
            for: AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        )
        let treatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
        let chlorineTreatments = treatments.filter { $0.targetParameter == "freeChlorine" && $0.amount > 0 }
        let recovery = try XCTUnwrap(treatments.first {
            $0.targetParameter == "freeChlorine" && $0.actionDescription.contains("algae recovery")
        })
        let cloudy = try XCTUnwrap(treatments.first {
            $0.targetParameter == "visualIndicators" && $0.chemicalName.contains("Cloudy Water")
        })
        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: treatments.filter { !$0.isWatchlistItem },
            watchlist: treatments.filter { $0.isWatchlistItem },
            recentHistory: [],
            config: config
        )

        XCTAssertEqual(chlorineTreatments.count, 1)
        XCTAssertEqual(recovery.productIdentifier, ChemicalProductID.liquidChlorine12_5.rawValue)
        XCTAssertEqual(recovery.amount, 6)
        XCTAssertTrue(recovery.actionDescription.contains("low sanitizer"))
        XCTAssertTrue(recovery.actionDescription.contains("algae recovery"))
        XCTAssertTrue(recovery.actionDescription.contains("elevated combined chlorine"))
        XCTAssertTrue(recovery.actionDescription.contains("cloudy/problem water"))
        XCTAssertEqual(
            TreatmentTimingGuidance.cardTip(
                for: recovery,
                nextActionableTreatment: cloudy,
                requiresVerificationBeforeSwimming: true
            ),
            "Test before swimming"
        )
        XCTAssertNotEqual(
            TreatmentTimingGuidance.cardTip(for: recovery, nextActionableTreatment: cloudy),
            "Wait ~1 hr before next chemical"
        )
        XCTAssertFalse(recovery.instructions.localizedCaseInsensitiveContains("retest FC"))
        XCTAssertFalse(recovery.instructions.localizedCaseInsensitiveContains("retest FC and CC"))
        XCTAssertEqual(cloudy.chemicalName, "Keep Filtering Cloudy Water")
        XCTAssertEqual(cloudy.amount, 0)
        XCTAssertFalse(cloudy.chemicalName.localizedCaseInsensitiveContains("retest"))
        XCTAssertFalse(cloudy.instructions.localizedCaseInsensitiveContains("retest"))
        XCTAssertEqual(recommendation.source, .treatmentPlan)
        XCTAssertTrue(recommendation.isPendingTreatmentAction)
        XCTAssertNil(recommendation.recommendedDate)
        XCTAssertEqual(recommendation.title, "After treatment is completed")
    }

    func testMultipleRecoverySignalsProduceOneMergedChlorineTreatment() async throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 1,
            totalChlorine: 2,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60,
            visualIndicators: [
                VisualIndicator.cloudyWater.rawValue,
                VisualIndicator.algaeSpots.rawValue
            ]
        )
        test.poolConditions = PoolConditions(
            swimmingLoad: .none,
            rainLoad: .none,
            coverOpenTime: .twoToSixHours,
            organicDebrisLoad: .low,
            skimmedDebris: .no,
            backwashedFilter: .no,
            waterAdded: .none,
            cleaningActivity: .oneCycle,
            poolBrushed: .no
        )

        let response = try await RuleBasedService().generateRecommendations(
            for: AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        )
        let chlorineTreatments = response.treatments.filter { $0.targetParameter == "freeChlorine" && $0.amount > 0 }
        let cloudyActions = response.treatments.filter { $0.chemicalName == "Keep Filtering Cloudy Water" }

        XCTAssertEqual(chlorineTreatments.count, 1, "Overlapping low-FC, CC, algae, and cloudy-water signals should reconcile to one current chlorine dose.")
        XCTAssertEqual(chlorineTreatments.first?.amount, 6)
        XCTAssertEqual(chlorineTreatments.first?.productID, .liquidChlorine12_5)
        XCTAssertTrue(chlorineTreatments.first?.actionDescription.contains("low sanitizer") ?? false)
        XCTAssertTrue(chlorineTreatments.first?.actionDescription.contains("algae recovery") ?? false)
        XCTAssertTrue(chlorineTreatments.first?.actionDescription.contains("elevated combined chlorine") ?? false)
        XCTAssertTrue(chlorineTreatments.first?.actionDescription.contains("cloudy/problem water") ?? false)
        XCTAssertEqual(cloudyActions.count, 1)
        XCTAssertEqual(cloudyActions.first?.amount, 0)
    }

    func testLowFCWithoutCloudyOrAlgaeProducesSingleNormalChlorineTreatment() async throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let test = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 1,
            totalChlorine: 1,
            totalAlkalinity: 100,
            cyanuricAcid: 60,
            visualIndicators: [VisualIndicator.crystalClear.rawValue]
        )
        let response = try await RuleBasedService().generateRecommendations(
            for: AIRecommendationRequest(currentTest: test, recentHistory: [], poolConfig: config)
        )
        let chlorineTreatments = response.treatments.filter { $0.targetParameter == "freeChlorine" && $0.amount > 0 }

        XCTAssertEqual(chlorineTreatments.count, 1)
        XCTAssertFalse(chlorineTreatments.first?.actionDescription.contains("algae recovery") ?? true)
    }

    func testNextPoolTestSeparatesRoutineTestingFromSameDayVerification() {
        let config = ChemistryTestFixtures.config()
        let routineTest = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 4.5,
            totalChlorine: 5.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
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

        XCTAssertEqual(urgentRecommendation.source, .treatmentPlan)
        XCTAssertTrue(urgentRecommendation.isPendingTreatmentAction)
        XCTAssertNil(urgentRecommendation.recommendedDate)
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

        XCTAssertEqual(recommendation.source, .treatmentPlan)
        XCTAssertTrue(recommendation.isPendingTreatmentAction)
        XCTAssertNil(recommendation.recommendedDate)
    }

    func testRecentChlorineMixingWatchlistDoesNotCreateRetestFCActionWhenNoNewTestExists() {
        let config = ChemistryTestFixtures.config()
        let completedAt = Date().addingTimeInterval(-1_800)
        let current = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 4,
            totalChlorine: 4,
            totalAlkalinity: 100,
            cyanuricAcid: 60
        )
        current.date = completedAt.addingTimeInterval(-60)
        let previous = ChemistryTestFixtures.currentPool(
            pH: 7.6,
            freeChlorine: 2,
            totalChlorine: 2,
            totalAlkalinity: 100,
            cyanuricAcid: 60
        )
        previous.date = completedAt.addingTimeInterval(-1_800)
        previous.treatments = [completedChlorineTreatment(completedAt: completedAt, expectedDelta: 2)]

        let treatments = engine.validatedTreatments(for: current, config: config, recentHistory: [previous])
        let mixing = treatments.first { $0.actionDescription.contains("still mixing") }

        XCTAssertEqual(mixing?.chemicalName, "Chlorine Still Circulating")
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Retest Free Chlorine" })
        XCTAssertFalse(mixing?.instructions.localizedCaseInsensitiveContains("then retest") ?? true)
    }

    func testFreshPostTreatmentLowChlorineTestOverridesMixingSuppression() throws {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let completedAt = Date().addingTimeInterval(-1_800)
        let current = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 0.5,
            totalChlorine: 1.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        current.date = completedAt.addingTimeInterval(300)
        let previous = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 4.5,
            totalChlorine: 5.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        previous.date = completedAt.addingTimeInterval(-1_800)
        previous.treatments = [completedChlorineTreatment(completedAt: completedAt, expectedDelta: 2.5)]

        let treatments = engine.validatedTreatments(for: current, config: config, recentHistory: [previous])
        let chlorine = try XCTUnwrap(treatments.first { $0.targetParameter == "freeChlorine" && $0.amount > 0 })

        XCTAssertEqual(chlorine.productID, .liquidChlorine12_5)
        XCTAssertNotEqual(chlorine.urgency, .advisory)
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Chlorine Still Circulating" })
    }

    func testFreshPostTreatmentAdequateChlorineDoesNotCreateUnneededRepeatDose() {
        let config = ChemistryTestFixtures.config(chlorine: .liquidChlorine12_5)
        let completedAt = Date().addingTimeInterval(-1_800)
        let current = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 6.5,
            totalChlorine: 7.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        current.date = completedAt.addingTimeInterval(300)
        let previous = ChemistryTestFixtures.currentPool(
            pH: 7.5,
            freeChlorine: 4.5,
            totalChlorine: 5.0,
            totalAlkalinity: 100,
            calciumHardness: 330,
            cyanuricAcid: 60
        )
        previous.date = completedAt.addingTimeInterval(-1_800)
        previous.treatments = [completedChlorineTreatment(completedAt: completedAt, expectedDelta: 2.5)]

        let treatments = engine.validatedTreatments(for: current, config: config, recentHistory: [previous])

        XCTAssertFalse(treatments.contains { $0.targetParameter == "freeChlorine" && $0.amount > 0 })
        XCTAssertFalse(treatments.contains { $0.chemicalName == "Chlorine Still Circulating" })
    }

    func testPendingTreatmentRetestOwnersDoNotReceiveAbsoluteNextTestDates() {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(pH: 8.0, totalAlkalinity: 140)
        let acid = timingTreatment(
            name: "Muriatic Acid (31.45%)",
            target: "pH",
            amount: 1.5,
            productID: .muriaticAcid31,
            urgency: .immediate,
            expectedDelta: -0.5,
            effectDelayHours: 4
        )
        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [acid],
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertTrue(recommendation.isPendingTreatmentAction)
        XCTAssertNil(recommendation.recommendedDate)
        XCTAssertEqual(recommendation.title, "After treatment is completed")
        XCTAssertEqual(recommendation.body, "Complete or skip the recommended treatment to schedule your next test.")
    }

    func testCompletedAcidTreatmentAnchorsNextPoolTestToCompletedAt() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(pH: 8.0, totalAlkalinity: 140)
        let completedAt = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 10)))
        let acid = timingTreatment(
            name: "Muriatic Acid (31.45%)",
            target: "pH",
            amount: 1.5,
            productID: .muriaticAcid31,
            urgency: .immediate,
            expectedDelta: -0.5,
            effectDelayHours: 4
        )
        acid.isCompleted = true
        acid.completedAt = completedAt

        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [acid],
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertFalse(recommendation.isPendingTreatmentAction)
        XCTAssertEqual(recommendation.source, .pHCorrection)
        XCTAssertEqual(recommendation.title, "Retest pH")
        XCTAssertEqual(recommendation.recommendedDate, completedAt.addingTimeInterval(4 * 60 * 60))
    }

    func testPoolCareTreatmentRetestsArePendingUntilCompletionThenAnchorToCompletedAt() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(pH: 7.5, totalAlkalinity: 50, calciumHardness: 100, cyanuricAcid: 20)
        let completedAt = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 12)))
        let bakingSoda = timingTreatment(
            name: "Baking Soda (Sodium Bicarbonate)",
            target: "totalAlkalinity",
            amount: 13.7,
            productID: .bakingSoda,
            urgency: .optional,
            expectedDelta: 30,
            effectDelayHours: 8
        )
        let calcium = timingTreatment(
            name: "Calcium Hardness Increaser (Calcium Chloride)",
            target: "calciumHardness",
            amount: 40.7,
            productID: .calciumChloride,
            urgency: .optional,
            expectedDelta: 100,
            effectDelayHours: TreatmentApplicationPolicy.calciumChlorideRetestHours
        )
        let cya = timingTreatment(
            name: "Cyanuric Acid (Granular)",
            target: "cyanuricAcid",
            amount: 5.3,
            productID: .granularCYA,
            urgency: .optional,
            expectedDelta: 20,
            effectDelayHours: TreatmentApplicationPolicy.granularCYACanonicalRetestHours
        )

        let pendingRecommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [bakingSoda, calcium, cya],
            watchlist: [],
            recentHistory: [],
            config: config
        )
        XCTAssertTrue(pendingRecommendation.isPendingTreatmentAction)
        XCTAssertNil(pendingRecommendation.recommendedDate)

        bakingSoda.isCompleted = true
        bakingSoda.completedAt = completedAt
        calcium.isSkipped = true
        cya.isSkipped = true

        let completedRecommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [bakingSoda, calcium, cya],
            watchlist: [],
            recentHistory: [],
            config: config
        )
        XCTAssertEqual(completedRecommendation.title, "Retest TA")
        XCTAssertEqual(completedRecommendation.recommendedDate, completedAt.addingTimeInterval(8 * 60 * 60))

        bakingSoda.isSkipped = true
        bakingSoda.isCompleted = false
        bakingSoda.completedAt = nil
        let skippedRecommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [bakingSoda, calcium, cya],
            watchlist: [],
            recentHistory: [],
            config: config
        )
        XCTAssertFalse(skippedRecommendation.isPendingTreatmentAction)
        XCTAssertNotNil(skippedRecommendation.recommendedDate)
    }

    func testMultipleTreatmentPlanDoesNotScheduleFinalRetestBeforePendingStepCompletion() throws {
        let config = ChemistryTestFixtures.config(volume: 32_583)
        let test = ChemistryTestFixtures.currentPool(pH: 8.0, totalAlkalinity: 140, cyanuricAcid: 20)
        let completedAt = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 9)))
        let acid = timingTreatment(
            name: "Muriatic Acid (31.45%)",
            target: "pH",
            amount: 1.5,
            productID: .muriaticAcid31,
            urgency: .immediate,
            expectedDelta: -0.5,
            effectDelayHours: 4
        )
        acid.isCompleted = true
        acid.completedAt = completedAt
        let cya = timingTreatment(
            name: "Cyanuric Acid (Granular)",
            target: "cyanuricAcid",
            amount: 5.3,
            productID: .granularCYA,
            urgency: .optional,
            expectedDelta: 20,
            effectDelayHours: TreatmentApplicationPolicy.granularCYACanonicalRetestHours
        )

        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [acid, cya],
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertTrue(recommendation.isPendingTreatmentAction)
        XCTAssertNil(recommendation.recommendedDate)
    }

    func testRoutineNoTreatmentRecommendationStillHasAbsoluteDate() {
        let config = ChemistryTestFixtures.config()
        let test = ChemistryTestFixtures.currentPool(pH: 7.5, freeChlorine: 6, totalChlorine: 6.5, totalAlkalinity: 100, calciumHardness: 330, cyanuricAcid: 60)

        let recommendation = NextTestRecommendationEngine().recommendation(
            for: test,
            treatmentSteps: [],
            watchlist: [],
            recentHistory: [],
            config: config
        )

        XCTAssertFalse(recommendation.isPendingTreatmentAction)
        XCTAssertNotNil(recommendation.recommendedDate)
        XCTAssertEqual(recommendation.source, .stablePool)
    }

    func testWatchlistPresentationText() {
        XCTAssertFalse(WatchlistPresentationText.shouldShow(count: 0))
        XCTAssertEqual(WatchlistPresentationText.summary(count: 1), "1 item to monitor")
        XCTAssertEqual(WatchlistPresentationText.summary(count: 5), "5 items to monitor")
    }

    private func completedChlorineTreatment(completedAt: Date, expectedDelta: Double) -> Treatment {
        Treatment(
            createdAt: completedAt,
            chemicalName: "Liquid Chlorine 12.5%",
            actionDescription: "Recent chlorine correction",
            amount: 1,
            unit: "gal",
            productIdentifier: ChemicalProductID.liquidChlorine12_5.rawValue,
            globalPreferenceIdentifier: ChemicalProductID.liquidChlorine12_5.rawValue,
            instructions: "",
            urgency: .optional,
            isCompleted: true,
            completedAt: completedAt,
            targetParameter: "freeChlorine",
            expectedEffectParameter: "freeChlorine",
            expectedDelta: expectedDelta
        )
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
        expectedDelta: Double = 0,
        effectDelayHours: Int = 0
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
            expectedDelta: expectedDelta,
            effectDelayHours: effectDelayHours
        )
    }
}
