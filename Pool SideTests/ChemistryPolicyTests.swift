import XCTest
@testable import Pool_Side

final class ChemistryPolicyTests: XCTestCase {

    private func context(
        cya: Double? = 60,
        sanitizer: SanitizerKind = .hypochloriteOrSWG,
        surface: SurfaceType = .plaster,
        isSaltwater: Bool = false,
        pH: Double? = 7.4,
        chlorineSampleSize: TaylorSampleSize? = .tenMl,
        testMethod: TestMethod = .liquidDropKit,
        hasScaling: Bool = false
    ) -> ChemistryPolicyContext {
        ChemistryPolicyContext(
            cyanuricAcid: cya,
            sanitizer: sanitizer,
            surface: surface,
            isSaltwater: isSaltwater,
            saltRange: .genericFallback,
            measurement: MeasurementResolution(testMethod: testMethod, chlorineSampleSize: chlorineSampleSize),
            pH: pH,
            totalAlkalinity: nil,
            hasScalingEvidence: hasScaling
        )
    }

    // MARK: - Swim-gate capability (only FC, CC, pH are direct gates)

    func testSwimGateCapabilityMatchesApprovedPolicy() {
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .freeChlorine), SwimGateCapability(lowCanBlock: true, highCanBlock: true))
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .combinedChlorine), SwimGateCapability(lowCanBlock: false, highCanBlock: true))
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .pH), SwimGateCapability(lowCanBlock: true, highCanBlock: true))
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .totalAlkalinity), .never)
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .calciumHardness), .never)
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .cyanuricAcid), .never)
        XCTAssertEqual(ChemistryPolicy.swimGateCapability(for: .saltLevel), .never)
    }

    // MARK: - FC resolver parity with ChemistryEngine

    func testFreeChlorineResolversMatchEngineCoefficients() {
        XCTAssertEqual(FreeChlorinePolicy.readinessMinimum(cyanuricAcid: 60), 4.5, accuracy: 0.0001)
        XCTAssertEqual(FreeChlorinePolicy.readinessMinimum(cyanuricAcid: nil), 1.0, accuracy: 0.0001)
        let range = FreeChlorinePolicy.operatingRange(cyanuricAcid: 60)
        XCTAssertEqual(range.lowerBound, 6.0, accuracy: 0.0001)
        XCTAssertEqual(range.upperBound, 8.0, accuracy: 0.0001)
        XCTAssertEqual(FreeChlorinePolicy.shockLevel(cyanuricAcid: 60), 24, accuracy: 0.0001)
        // Re-entry ceiling is a conservative hook, NOT the shock level.
        XCTAssertEqual(FreeChlorinePolicy.reentryCeiling(cyanuricAcid: 60), 10, accuracy: 0.0001)
        XCTAssertNotEqual(FreeChlorinePolicy.reentryCeiling(cyanuricAcid: 60), FreeChlorinePolicy.shockLevel(cyanuricAcid: 60))
    }

    func testFreeChlorineClassificationBands() {
        let ctx = context()
        // Below readiness minimum but not severe -> Needs Attention, blocks, targets the operating range.
        let low = ChemistryPolicy.classify(.freeChlorine, value: 4.0, context: ctx)
        XCTAssertEqual(low.actionState, .actNowLow)
        XCTAssertEqual(low.severity, .moderate)
        XCTAssertTrue(low.blocksSwimming)
        XCTAssertEqual(low.correctionTarget, 6.0)
        XCTAssertEqual(low.derivedUrgency, .needsAttention)

        // Severely low FC (below half the readiness minimum) -> Act Now.
        let severeLow = ChemistryPolicy.classify(.freeChlorine, value: 1.0, context: ctx)
        XCTAssertEqual(severeLow.actionState, .actNowLow)
        XCTAssertEqual(severeLow.severity, .severe)
        XCTAssertEqual(severeLow.derivedUrgency, .immediate)

        // At/above readiness minimum but below operating target -> Recommended (NOT Optional), does not block.
        for fc in [4.5, 5.0] {
            let rec = ChemistryPolicy.classify(.freeChlorine, value: fc, context: ctx)
            XCTAssertEqual(rec.actionState, .recommendedLow, "FC \(fc)")
            XCTAssertFalse(rec.blocksSwimming, "FC \(fc)")
            XCTAssertEqual(rec.derivedUrgency, .recommended, "FC \(fc) must be Recommended, not Optional")
            XCTAssertEqual(rec.disposition, .treatNow, "FC \(fc)")
        }

        // Within operating range -> ideal.
        let ideal = ChemistryPolicy.classify(.freeChlorine, value: 7.0, context: ctx)
        XCTAssertEqual(ideal.actionState, .ideal)
        XCTAssertNil(ideal.derivedUrgency)
        XCTAssertFalse(ideal.blocksSwimming)

        // Above operating range but below re-entry ceiling -> allow natural decay, no chemical, no block.
        let high = ChemistryPolicy.classify(.freeChlorine, value: 9.0, context: ctx)
        XCTAssertEqual(high.actionState, .recommendedHigh)
        XCTAssertEqual(high.disposition, .allowNaturalCorrection)
        XCTAssertFalse(high.blocksSwimming)
        XCTAssertNil(high.derivedUrgency)

        // Above re-entry ceiling but below the severe-high threshold (15) -> Needs Attention, blocks, decays.
        let ceiling = ChemistryPolicy.classify(.freeChlorine, value: 12.0, context: ctx)
        XCTAssertEqual(ceiling.actionState, .actNowHigh)
        XCTAssertEqual(ceiling.severity, .moderate)
        XCTAssertTrue(ceiling.blocksSwimming)
        XCTAssertEqual(ceiling.disposition, .allowNaturalCorrection)

        // At/above the severe-high threshold (max(15, ceiling)) -> Act Now.
        let severeHigh = ChemistryPolicy.classify(.freeChlorine, value: 16.0, context: ctx)
        XCTAssertEqual(severeHigh.actionState, .actNowHigh)
        XCTAssertEqual(severeHigh.severity, .severe)
        XCTAssertTrue(severeHigh.blocksSwimming)
    }

    // MARK: - Combined chlorine (asymmetric; measurement-resolution aware)

    func testCombinedChlorineBandsAndResolution() {
        let tenMl = context()   // 0.5 ppm increment
        XCTAssertEqual(ChemistryPolicy.classify(.combinedChlorine, value: 0, context: tenMl).actionState, .ideal)

        // Sub-increment CC on a 10 mL FAS-DPD test is treated as zero (no false precision).
        let subIncrement = ChemistryPolicy.classify(.combinedChlorine, value: 0.3, context: tenMl)
        XCTAssertEqual(subIncrement.actionState, .ideal)
        XCTAssertFalse(subIncrement.blocksSwimming)

        // Observable 0.2 on a 25 mL sample is detectable.
        let fineCtx = context(chlorineSampleSize: .twentyFiveMl)
        let fine = ChemistryPolicy.classify(.combinedChlorine, value: 0.2, context: fineCtx)
        XCTAssertEqual(fine.actionState, .recommendedHigh)
        XCTAssertEqual(fine.disposition, .monitorOnly)
        XCTAssertFalse(fine.blocksSwimming)

        // At readiness threshold: monitor toward zero, still swimmable.
        let atThreshold = ChemistryPolicy.classify(.combinedChlorine, value: 0.5, context: tenMl)
        XCTAssertEqual(atThreshold.actionState, .recommendedHigh)
        XCTAssertFalse(atThreshold.blocksSwimming)
        XCTAssertEqual(atThreshold.derivedUrgency, .advisory)

        // 0.5–1.0: corrective, blocks, Needs Attention (fix before swimming, not an emergency).
        let over = ChemistryPolicy.classify(.combinedChlorine, value: 0.6, context: tenMl)
        XCTAssertTrue(over.blocksSwimming)
        XCTAssertEqual(over.disposition, .treatNow)
        XCTAssertEqual(over.derivedUrgency, .needsAttention)
        XCTAssertEqual(over.correctionTarget, 0)

        // Severe CC -> Act Now.
        let severe = ChemistryPolicy.classify(.combinedChlorine, value: 1.5, context: tenMl)
        XCTAssertEqual(severe.actionState, .actNowHigh)
        XCTAssertEqual(severe.derivedUrgency, .immediate)
        XCTAssertTrue(severe.blocksSwimming)
    }

    // MARK: - pH (settled)

    func testPHSettledBandsAndSwimRange() {
        let ctx = context()
        func s(_ v: Double) -> ParameterClassification { ChemistryPolicy.classify(.pH, value: v, context: ctx) }

        XCTAssertEqual(s(6.9).actionState, .actNowLow); XCTAssertTrue(s(6.9).blocksSwimming)
        XCTAssertEqual(s(7.0).actionState, .recommendedLow); XCTAssertFalse(s(7.0).blocksSwimming)
        XCTAssertEqual(s(7.1).actionState, .recommendedLow); XCTAssertFalse(s(7.1).blocksSwimming)
        XCTAssertEqual(s(7.2).actionState, .ideal); XCTAssertNil(s(7.2).derivedUrgency)
        XCTAssertEqual(s(7.4).actionState, .ideal)
        XCTAssertEqual(s(7.6).actionState, .ideal)
        XCTAssertEqual(s(7.7).actionState, .recommendedHigh); XCTAssertFalse(s(7.7).blocksSwimming)
        XCTAssertEqual(s(7.8).actionState, .recommendedHigh); XCTAssertFalse(s(7.8).blocksSwimming) // 7.8 swimmable
        XCTAssertEqual(s(7.9).actionState, .actNowHigh); XCTAssertTrue(s(7.9).blocksSwimming)
        XCTAssertEqual(s(8.0).actionState, .actNowHigh); XCTAssertTrue(s(8.0).blocksSwimming)

        // All non-ideal pH bands target ~7.4 and are treatNow (no monitor-only for out-of-range pH).
        for v in [6.9, 7.0, 7.1, 7.7, 7.8, 7.9] {
            XCTAssertEqual(s(v).correctionTarget, 7.4, "pH \(v)")
            XCTAssertEqual(s(v).disposition, .treatNow, "pH \(v)")
        }
    }

    // MARK: - Total Alkalinity (sanitizer-aware; never blocks)

    func testTotalAlkalinitySanitizerAwareBands() {
        let hypo = context(sanitizer: .hypochloriteOrSWG)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 55, context: hypo).actionState, .actNowLow)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 70, context: hypo).actionState, .recommendedLow)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 90, context: hypo).actionState, .ideal)

        // TA 160, pH 7.4 -> Recommended High, swim allowed, treatWhenChemicallyAppropriate (no acid dump).
        let ta160 = ChemistryPolicy.classify(.totalAlkalinity, value: 160, context: hypo)
        XCTAssertEqual(ta160.actionState, .recommendedHigh)
        XCTAssertFalse(ta160.blocksSwimming)
        XCTAssertEqual(ta160.disposition, .treatWhenChemicallyAppropriate)
        XCTAssertEqual(ta160.derivedUrgency, .recommended)   // not "watch forever", not Optional
        XCTAssertEqual(ta160.correctionTarget, 90)

        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 200, context: hypo).actionState, .actNowHigh)
        XCTAssertFalse(ChemistryPolicy.classify(.totalAlkalinity, value: 200, context: hypo).blocksSwimming)

        // The 101–120 band is Recommended High for a hypochlorite pool (legacy status called this "ideal").
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 100, context: hypo).actionState, .ideal)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 101, context: hypo).actionState, .recommendedHigh)
        let hypo110 = ChemistryPolicy.classify(.totalAlkalinity, value: 110, context: hypo)
        XCTAssertEqual(hypo110.actionState, .recommendedHigh)
        XCTAssertEqual(hypo110.disposition, .treatWhenChemicallyAppropriate)
        XCTAssertFalse(hypo110.blocksSwimming)

        // Acidic sanitizer prefers higher TA.
        let acidic = context(sanitizer: .acidicStabilized)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 90, context: acidic).actionState, .recommendedLow)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 110, context: acidic).actionState, .ideal)
        XCTAssertEqual(ChemistryPolicy.classify(.totalAlkalinity, value: 110, context: acidic).correctionTarget ?? -1, -1) // ideal -> nil
    }

    // MARK: - Calcium Hardness (surface-aware; never blocks; no chemical reducer)

    func testCalciumHardnessSurfaceAwareBands() {
        let plaster = context(surface: .plaster, pH: 7.4)
        XCTAssertEqual(ChemistryPolicy.classify(.calciumHardness, value: 100, context: plaster).actionState, .actNowLow)
        let recLow = ChemistryPolicy.classify(.calciumHardness, value: 175, context: plaster)
        XCTAssertEqual(recLow.actionState, .recommendedLow)
        XCTAssertEqual(recLow.correctionTarget, 275) // aims into range, not the 150 boundary
        XCTAssertEqual(ChemistryPolicy.classify(.calciumHardness, value: 300, context: plaster).actionState, .ideal)

        let high = ChemistryPolicy.classify(.calciumHardness, value: 600, context: plaster)
        XCTAssertEqual(high.actionState, .recommendedHigh)
        XCTAssertEqual(high.disposition, .treatWhenChemicallyAppropriate)
        XCTAssertFalse(high.blocksSwimming)

        // Scaling/high-pH escalates high CH to Act Now before 1000.
        let scaling = context(surface: .plaster, pH: 7.9)
        XCTAssertEqual(ChemistryPolicy.classify(.calciumHardness, value: 600, context: scaling).actionState, .actNowHigh)

        // >=1000 -> Act Now, dilute.
        let ceiling = ChemistryPolicy.classify(.calciumHardness, value: 1000, context: plaster)
        XCTAssertEqual(ceiling.actionState, .actNowHigh)
        XCTAssertEqual(ceiling.disposition, .dilute)
        XCTAssertFalse(ceiling.blocksSwimming)

        // Vinyl resolves a lower ideal range.
        let vinyl = context(surface: .vinyl, pH: 7.4)
        XCTAssertEqual(ChemistryPolicy.classify(.calciumHardness, value: 175, context: vinyl).actionState, .ideal)
    }

    // MARK: - Cyanuric Acid (modulates FC; never blocks)

    func testCyanuricAcidBands() {
        let ctx = context()
        XCTAssertEqual(ChemistryPolicy.classify(.cyanuricAcid, value: 10, context: ctx).actionState, .actNowLow)
        XCTAssertEqual(ChemistryPolicy.classify(.cyanuricAcid, value: 20, context: ctx).actionState, .recommendedLow)
        XCTAssertEqual(ChemistryPolicy.classify(.cyanuricAcid, value: 40, context: ctx).actionState, .ideal)

        let elevated = ChemistryPolicy.classify(.cyanuricAcid, value: 70, context: ctx)
        XCTAssertEqual(elevated.actionState, .recommendedHigh)
        XCTAssertEqual(elevated.disposition, .monitorOnly)
        XCTAssertFalse(elevated.blocksSwimming)
        XCTAssertEqual(elevated.derivedUrgency, .advisory)

        let veryHigh = ChemistryPolicy.classify(.cyanuricAcid, value: 100, context: ctx)
        XCTAssertEqual(veryHigh.actionState, .actNowHigh)
        XCTAssertEqual(veryHigh.disposition, .dilute)
        XCTAssertFalse(veryHigh.blocksSwimming)
    }

    // MARK: - Salt (configurable; never blocks)

    func testSaltBandsUseConfiguredRange() {
        let ctx = context(isSaltwater: true)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 2300, context: ctx).actionState, .actNowLow)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 2500, context: ctx).actionState, .recommendedLow)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 3200, context: ctx).actionState, .ideal)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 3500, context: ctx).actionState, .recommendedHigh)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 3700, context: ctx).actionState, .actNowHigh)
        XCTAssertFalse(ChemistryPolicy.classify(.saltLevel, value: 3700, context: ctx).blocksSwimming)

        // Configured override takes precedence. Values chosen so the override changes the outcome
        // versus the generic fallback: 2800 is ideal under the generic range (min 2700) but
        // recommendedLow under the override (min 3000); 3500 is recommendedHigh under generic
        // (max 3400) but ideal under the override (max 4000).
        var override = ctx
        override.saltRange = SaltRange(minimum: 3000, target: 3500, maximum: 4000)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 2800, context: ctx).actionState, .ideal)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 2800, context: override).actionState, .recommendedLow)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 3500, context: ctx).actionState, .recommendedHigh)
        XCTAssertEqual(ChemistryPolicy.classify(.saltLevel, value: 3500, context: override).actionState, .ideal)
    }

    // MARK: - Urgency derivation rules

    func testDerivedUrgencyMapping() {
        // Severe actNow → Act Now; moderate actNow → Needs Attention.
        XCTAssertEqual(TreatmentUrgency.derived(state: .actNowLow, disposition: .treatNow, severity: .severe), .immediate)
        XCTAssertEqual(TreatmentUrgency.derived(state: .actNowLow, disposition: .treatNow, severity: .moderate), .needsAttention)
        XCTAssertEqual(TreatmentUrgency.derived(state: .actNowHigh, disposition: .dilute, severity: .severe), .immediate)
        XCTAssertEqual(TreatmentUrgency.derived(state: .actNowHigh, disposition: .treatNow, severity: .moderate), .needsAttention)
        XCTAssertEqual(TreatmentUrgency.derived(state: .recommendedLow, disposition: .treatNow, severity: .none), .recommended)
        XCTAssertEqual(TreatmentUrgency.derived(state: .recommendedHigh, disposition: .treatWhenChemicallyAppropriate, severity: .none), .recommended)
        XCTAssertEqual(TreatmentUrgency.derived(state: .recommendedHigh, disposition: .monitorOnly, severity: .none), .advisory)
        XCTAssertNil(TreatmentUrgency.derived(state: .recommendedHigh, disposition: .allowNaturalCorrection, severity: .none))
        XCTAssertNil(TreatmentUrgency.derived(state: .ideal, disposition: .noAction, severity: .none))
        // Optional is never derived for normal chemistry correction.
        XCTAssertNotEqual(TreatmentUrgency.derived(state: .recommendedLow, disposition: .treatNow, severity: .none), .optional)
    }
}
