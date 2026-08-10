import Foundation

// MARK: - ChemistryPolicy
//
// Single production source of truth for Pool Side's chemistry-policy semantics, per the
// approved canonical ChemistryPolicy specification. This layer answers *domain* questions:
//
//   1. What action state is a measured value in, relative to the DESIRED OPERATING range?
//   2. What should be done about it (correction disposition), independent of swimability?
//   3. Does THIS parameter's state block swimming (evaluated per-side, independent of urgency)?
//   4. What is the correction target, and what user-facing urgency does that imply?
//
// It deliberately separates three orthogonal axes that older code conflated:
//   - ChemistryActionState        (classification vs operating range)
//   - CorrectionDisposition       (what to do about it)
//   - swim gate                   (does it block swimming, per side)
//
// All bands/targets are RESOLVERS (functions of CYA / sanitizer / surface / salt config /
// test method), never universal global constants. Downstream systems (treatment generation,
// urgency, explanations, focused verification, Swimability V2 gates, views) are intended to
// CONSUME this policy rather than re-deriving thresholds.
//
// This file is additive. Wiring existing services to consume it is a subsequent, test-verified
// step; nothing here changes current behavior on its own.

// MARK: Parameters

enum ChemistryParameter: String, CaseIterable, Sendable {
    case freeChlorine
    case combinedChlorine
    case pH
    case totalAlkalinity
    case calciumHardness
    case cyanuricAcid
    case saltLevel
}

// MARK: Action state (classification vs the desired OPERATING range)

enum ChemistryActionState: String, Sendable, Equatable {
    case actNowLow
    case recommendedLow
    case ideal
    case recommendedHigh
    case actNowHigh

    var isLow: Bool { self == .actNowLow || self == .recommendedLow }
    var isHigh: Bool { self == .actNowHigh || self == .recommendedHigh }
    var isActNow: Bool { self == .actNowLow || self == .actNowHigh }
    var isOutOfOperatingRange: Bool { self != .ideal }
}

// MARK: Correction disposition (what to do — independent of action state)

enum CorrectionDisposition: String, Sendable, Equatable {
    /// Add the appropriate corrective product now (staged by application policy).
    case treatNow
    /// Correction is warranted, but must wait for an interacting-chemistry condition
    /// (e.g. reduce TA only through pH/acid/aeration cycles as pH permits).
    case treatWhenChemicallyAppropriate
    /// Out of range but resolves on its own (e.g. moderately high FC decaying). No chemical.
    case allowNaturalCorrection
    /// Reduce by partial water replacement (e.g. very high CYA / very high salt).
    case dilute
    /// Watch only; no direct treatment is appropriate yet (e.g. manageable elevated CYA).
    case monitorOnly
    /// Nothing to do.
    case noAction
}

// MARK: Swim-gate semantics

/// Whether a parameter is *capable* of blocking swimming on each side. Independent of the
/// action state and of urgency. TA/CH/CYA/Salt never directly block swimming; they reach
/// safety only indirectly (CYA -> FC readiness, Salt -> FC generation).
struct SwimGateCapability: Sendable, Equatable {
    let lowCanBlock: Bool
    let highCanBlock: Bool

    static let never = SwimGateCapability(lowCanBlock: false, highCanBlock: false)
}

// MARK: Severity within an action band

/// How serious an out-of-range condition is *within* its action band. This is the single canonical axis that
/// splits an `actNow` state into "Needs Attention" (moderate — below a safety threshold / approaching unsafe)
/// versus "Act Now" (severe — significant risk or potential pool/equipment damage). `.none` is used for ideal
/// and for in-band (recommended) optimization states, where severity does not modulate urgency.
enum ChemistrySeverity: String, Sendable, Equatable {
    case none
    case moderate
    case severe
}

// MARK: User-facing urgency derivation

extension TreatmentUrgency {
    /// Derives the treatment-CARD urgency from action state + disposition + severity, per the approved policy.
    /// A card is produced only for dispositions that call for user action; informational / natural-correction
    /// states produce no card. Within an `actNow` band, severe → Act Now, moderate → Needs Attention.
    static func derived(
        state: ChemistryActionState,
        disposition: CorrectionDisposition,
        severity: ChemistrySeverity
    ) -> TreatmentUrgency? {
        switch disposition {
        case .noAction:
            return nil
        case .allowNaturalCorrection:
            // Informational guidance (e.g. high FC decaying), not a chemical treatment card.
            return nil
        case .monitorOnly:
            return .advisory
        case .treatNow, .treatWhenChemicallyAppropriate, .dilute:
            switch state {
            case .actNowLow, .actNowHigh:
                return severity == .severe ? .immediate : .needsAttention
            case .recommendedLow, .recommendedHigh:
                return .recommended
            case .ideal:
                return nil
            }
        }
    }
}

// MARK: Sanitizer kind (drives TA policy)

enum SanitizerKind: Sendable, Equatable {
    /// Sodium/calcium/lithium hypochlorite or SWG: prefers lower TA for pH stability.
    case hypochloriteOrSWG
    /// Acidic stabilized chlorine (trichlor/dichlor): prefers higher TA to buffer acidity.
    case acidicStabilized

    static func resolve(from preference: ChlorinePreference) -> SanitizerKind {
        switch preference {
        case .tablets, .dichlor:
            return .acidicStabilized
        case .saltGenerator, .calHypo, .liquidChlorine10, .liquidChlorine12_5:
            return .hypochloriteOrSWG
        }
    }
}

// MARK: Configurable salt range (SWG manufacturer / user override)

struct SaltRange: Sendable, Equatable {
    let minimum: Double
    let target: Double
    let maximum: Double

    /// Pool Side generic fallback used when the owner has not configured an SWG-specific range.
    static let genericFallback = SaltRange(minimum: 2700, target: 3200, maximum: 3400)
}

// MARK: Measurement resolution (first-class policy input)

/// Encodes how coarsely the selected test method can actually measure a parameter, so the
/// policy never manufactures distinctions the user cannot observe (e.g. a Taylor FAS-DPD
/// 10 mL sample cannot distinguish 0.2 from 0.4 ppm; strips read coarse bands).
struct MeasurementResolution: Sendable, Equatable {
    let testMethod: TestMethod
    let chlorineSampleSize: TaylorSampleSize?

    static let `default` = MeasurementResolution(testMethod: .liquidDropKit, chlorineSampleSize: .tenMl)

    /// Smallest reliably observable increment for a parameter under this method.
    func increment(for parameter: ChemistryParameter) -> Double {
        switch parameter {
        case .freeChlorine, .combinedChlorine:
            if let chlorineSampleSize { return chlorineSampleSize.ppmPerDrop }
            switch testMethod {
            case .liquidDropKit: return 0.5   // assume 10 mL FAS-DPD unless a sample size is known
            case .digitalTester: return 0.1
            case .poolStore:     return 0.2
            case .testStrips:    return 1.0   // coarse visual bands
            }
        case .pH:
            switch testMethod {
            case .testStrips: return 0.2
            default:          return 0.1
            }
        case .totalAlkalinity, .calciumHardness:
            switch testMethod {
            case .testStrips: return 40
            default:          return 10       // one titration drop
            }
        case .cyanuricAcid:
            switch testMethod {
            case .testStrips: return 30        // very coarse
            default:          return 10        // turbidity tests are coarse/nonlinear
            }
        case .saltLevel:
            return 200
        }
    }

    /// Whether two values are indistinguishable to this method (used for boundary tolerance and
    /// verification-success comparisons).
    func indistinguishable(_ a: Double, _ b: Double, for parameter: ChemistryParameter) -> Bool {
        abs(a - b) < increment(for: parameter) - 1e-9
    }
}

// MARK: Policy context

/// Everything a resolver may need. Interacting chemistry is optional so the policy can classify
/// with whatever evidence exists.
struct ChemistryPolicyContext: Sendable {
    var cyanuricAcid: Double?
    var sanitizer: SanitizerKind
    var surface: SurfaceType
    var isSaltwater: Bool
    var saltRange: SaltRange
    var measurement: MeasurementResolution

    // Interacting chemistry used for disposition decisions.
    var pH: Double?
    var totalAlkalinity: Double?
    var hasScalingEvidence: Bool

    init(
        cyanuricAcid: Double? = nil,
        sanitizer: SanitizerKind = .hypochloriteOrSWG,
        surface: SurfaceType = .plaster,
        isSaltwater: Bool = false,
        saltRange: SaltRange = .genericFallback,
        measurement: MeasurementResolution = .default,
        pH: Double? = nil,
        totalAlkalinity: Double? = nil,
        hasScalingEvidence: Bool = false
    ) {
        self.cyanuricAcid = cyanuricAcid
        self.sanitizer = sanitizer
        self.surface = surface
        self.isSaltwater = isSaltwater
        self.saltRange = saltRange
        self.measurement = measurement
        self.pH = pH
        self.totalAlkalinity = totalAlkalinity
        self.hasScalingEvidence = hasScalingEvidence
    }

    /// Convenience builder from production config + the test being evaluated.
    static func make(config: PoolConfiguration, cyanuricAcid: Double?, pH: Double?, totalAlkalinity: Double?, hasScalingEvidence: Bool, chlorineSampleSize: TaylorSampleSize?) -> ChemistryPolicyContext {
        ChemistryPolicyContext(
            cyanuricAcid: cyanuricAcid,
            sanitizer: .resolve(from: config.chlorinePreference),
            surface: config.surfaceType,
            isSaltwater: config.isSaltwater,
            saltRange: .genericFallback,
            measurement: MeasurementResolution(testMethod: config.testMethod, chlorineSampleSize: chlorineSampleSize),
            pH: pH,
            totalAlkalinity: totalAlkalinity,
            hasScalingEvidence: hasScalingEvidence
        )
    }
}

// MARK: Classification result

struct ParameterClassification: Sendable, Equatable {
    let parameter: ChemistryParameter
    let value: Double
    let actionState: ChemistryActionState
    let disposition: CorrectionDisposition
    let blocksSwimming: Bool
    /// Severity within the action band — the canonical axis that splits `actNow` into Needs Attention
    /// (moderate) vs Act Now (severe). `.none` for ideal / in-band recommended states.
    let severity: ChemistrySeverity
    /// Where a correction should aim (nil for ideal/noAction or dilution-only states).
    let correctionTarget: Double?
    /// Derived treatment-CARD urgency (nil = no treatment card). Disposition-gated.
    let derivedUrgency: TreatmentUrgency?

    /// Canonical STATUS urgency for the parameter — a function of action state + severity only (independent
    /// of disposition), so status/color/score wording is consistent even where no treatment card is produced
    /// (e.g. high FC awaiting natural decline). Views and Pool Score consume this, never re-deriving color.
    var statusUrgency: TreatmentUrgency? {
        switch actionState {
        case .ideal:
            return nil
        case .recommendedLow, .recommendedHigh:
            return .recommended
        case .actNowLow, .actNowHigh:
            return severity == .severe ? .immediate : .needsAttention
        }
    }
}

// MARK: - ChemistryPolicy façade

enum ChemistryPolicy {

    // Direct swim-gate parameters are FC, CC, pH only. Everything else is pool-care.
    static func swimGateCapability(for parameter: ChemistryParameter) -> SwimGateCapability {
        switch parameter {
        case .freeChlorine:     return SwimGateCapability(lowCanBlock: true, highCanBlock: true)
        case .combinedChlorine: return SwimGateCapability(lowCanBlock: false, highCanBlock: true)
        case .pH:               return SwimGateCapability(lowCanBlock: true, highCanBlock: true)
        case .totalAlkalinity, .calciumHardness, .cyanuricAcid, .saltLevel:
            return .never
        }
    }

    static func classify(_ parameter: ChemistryParameter, value: Double, context: ChemistryPolicyContext) -> ParameterClassification {
        switch parameter {
        case .freeChlorine:     return FreeChlorinePolicy.classify(value, context)
        case .combinedChlorine: return CombinedChlorinePolicy.classify(value, context)
        case .pH:               return PHPolicy.classify(value, context)
        case .totalAlkalinity:  return TotalAlkalinityPolicy.classify(value, context)
        case .calciumHardness:  return CalciumHardnessPolicy.classify(value, context)
        case .cyanuricAcid:     return CyanuricAcidPolicy.classify(value, context)
        case .saltLevel:        return SaltPolicy.classify(value, context)
        }
    }
}

// MARK: - Free Chlorine (CYA-aware; direct swim gate). Coefficients kept at parity with ChemistryEngine.

enum FreeChlorinePolicy {
    /// CYA-adjusted swim-readiness minimum. Parity with ChemistryEngine.freeChlorineMinimum.
    static func readinessMinimum(cyanuricAcid: Double?) -> Double {
        guard let cya = cyanuricAcid, cya >= 20 else { return 1.0 }
        return max(1.0, (cya * 0.075).rounded(toPlaces: 1))
    }

    /// Desired operating range. Parity with ChemistryEngine.freeChlorineTargetRange.
    static func operatingRange(cyanuricAcid: Double?) -> ClosedRange<Double> {
        guard let cya = cyanuricAcid, cya >= 20 else { return 1.0...3.0 }
        let minimum = readinessMinimum(cyanuricAcid: cya)
        let target = max(minimum + 1.5, cya * 0.10)
        let upper = max(target + 2.0, cya * 0.12)
        return target...upper
    }

    /// Recovery/shock target. Parity with ChemistryEngine.freeChlorineShockLevel. NOT a re-entry ceiling.
    static func shockLevel(cyanuricAcid: Double?) -> Double {
        guard let cya = cyanuricAcid, cya >= 20 else { return 10 }
        return max(cya * 0.40, 10)
    }

    /// High-FC re-entry ceiling. Deliberately a policy HOOK, not a universal 10 ppm rule.
    /// Kept conservative (matches the prior Dashboard "readyAfterWait" boundary) until a
    /// CYA/product-specific re-entry relationship is independently validated.
    static func reentryCeiling(cyanuricAcid: Double?) -> Double {
        max(10, operatingRange(cyanuricAcid: cyanuricAcid).upperBound)
    }

    /// Explicit "severely high FC" boundary — the point at which high FC escalates from Needs Attention to
    /// Act Now. Deliberately NOT the shock level (which is a recovery target). Independently replaceable.
    static func severeHighThreshold(cyanuricAcid: Double?) -> Double {
        max(15, reentryCeiling(cyanuricAcid: cyanuricAcid))
    }

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let cya = context.cyanuricAcid
        let minimum = readinessMinimum(cyanuricAcid: cya)
        let range = operatingRange(cyanuricAcid: cya)
        let ceiling = reentryCeiling(cyanuricAcid: cya)
        let severeHigh = severeHighThreshold(cyanuricAcid: cya)

        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let blocks: Bool
        let target: Double?
        let severity: ChemistrySeverity

        if value < 0.5 * minimum {
            // Severely low: significant sanitizer risk.
            state = .actNowLow; disposition = .treatNow; blocks = true; target = range.lowerBound; severity = .severe
        } else if value < minimum {
            // Below the swim-readiness minimum but not severe: correct before swimming, not an emergency.
            state = .actNowLow; disposition = .treatNow; blocks = true; target = range.lowerBound; severity = .moderate
        } else if value < range.lowerBound {
            // >= readiness minimum but below operating target: Recommended optimization (pool is swim-safe).
            state = .recommendedLow; disposition = .treatNow; blocks = false; target = range.lowerBound; severity = .none
        } else if value <= range.upperBound {
            state = .ideal; disposition = .noAction; blocks = false; target = nil; severity = .none
        } else if value < ceiling {
            // Above operating target but below the re-entry ceiling: informational, allow natural decline.
            state = .recommendedHigh; disposition = .allowNaturalCorrection; blocks = false; target = nil; severity = .none
        } else if value < severeHigh {
            // Above the re-entry ceiling but not severe: swim-blocking, Needs Attention (let it decline).
            state = .actNowHigh; disposition = .allowNaturalCorrection; blocks = true; target = nil; severity = .moderate
        } else {
            // Severely high FC.
            state = .actNowHigh; disposition = .allowNaturalCorrection; blocks = true; target = nil; severity = .severe
        }

        return ParameterClassification(
            parameter: .freeChlorine, value: value, actionState: state, disposition: disposition,
            blocksSwimming: blocks, severity: severity, correctionTarget: target,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - Combined Chlorine (asymmetric; no low state; direct high swim gate)

enum CombinedChlorinePolicy {
    static let readinessThreshold = 0.5

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let blocks: Bool

        let severity: ChemistrySeverity

        // Respect measurement resolution: values below one observable increment are treated as 0.
        let increment = context.measurement.increment(for: .combinedChlorine)
        let observable = value >= increment - 1e-9

        if !observable {
            state = .ideal; disposition = .noAction; blocks = false; severity = .none
        } else if value <= readinessThreshold + 1e-9 {
            // Detectable but within the readiness threshold: drive toward zero opportunistically.
            state = .recommendedHigh; disposition = .monitorOnly; blocks = false; severity = .none
        } else if value <= 1.0 + 1e-9 {
            // 0.5–1.0: elevated combined chlorine — Needs Attention (correct before swimming).
            state = .actNowHigh; disposition = .treatNow; blocks = true; severity = .moderate
        } else {
            // Above 1.0: significant chloramine load — Act Now.
            state = .actNowHigh; disposition = .treatNow; blocks = true; severity = .severe
        }

        return ParameterClassification(
            parameter: .combinedChlorine, value: value, actionState: state, disposition: disposition,
            blocksSwimming: blocks, severity: severity, correctionTarget: state == .ideal ? nil : 0,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - pH (settled). Operating 7.2–7.6; swim 7.0–7.8 inclusive; target ~7.4.

enum PHPolicy {
    static let operatingRange = 7.2...7.6
    static let swimRange = 7.0...7.8
    static let correctionTarget = 7.4

    /// Severe pH boundaries — outside these, pH is Act Now; between them and the swim range, Needs Attention.
    static let severeLowThreshold = 6.8
    static let severeHighThreshold = 8.0

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let blocks: Bool
        let severity: ChemistrySeverity

        if value < severeLowThreshold {
            state = .actNowLow; disposition = .treatNow; blocks = true; severity = .severe
        } else if value < 7.0 {
            // 6.8–7.0: below the swim-safe range but not severe.
            state = .actNowLow; disposition = .treatNow; blocks = true; severity = .moderate
        } else if value < 7.2 {
            state = .recommendedLow; disposition = .treatNow; blocks = false; severity = .none
        } else if value <= 7.6 {
            state = .ideal; disposition = .noAction; blocks = false; severity = .none
        } else if value <= 7.8 {
            state = .recommendedHigh; disposition = .treatNow; blocks = false; severity = .none
        } else if value <= severeHighThreshold {
            // 7.8–8.0: above the swim-safe range but not severe.
            state = .actNowHigh; disposition = .treatNow; blocks = true; severity = .moderate
        } else {
            state = .actNowHigh; disposition = .treatNow; blocks = true; severity = .severe
        }

        return ParameterClassification(
            parameter: .pH, value: value, actionState: state, disposition: disposition,
            blocksSwimming: blocks, severity: severity, correctionTarget: state == .ideal ? nil : correctionTarget,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - Total Alkalinity (sanitizer-aware; never a direct swim gate)

enum TotalAlkalinityPolicy {
    static func idealRange(sanitizer: SanitizerKind) -> ClosedRange<Double> {
        switch sanitizer {
        case .hypochloriteOrSWG: return 80...100
        case .acidicStabilized:  return 100...120
        }
    }

    static func correctionTarget(sanitizer: SanitizerKind) -> Double {
        switch sanitizer {
        case .hypochloriteOrSWG: return 90
        case .acidicStabilized:  return 110
        }
    }

    static let actNowLowBoundary = 60.0
    static let actNowHighBoundary = 180.0

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let ideal = idealRange(sanitizer: context.sanitizer)
        let target = correctionTarget(sanitizer: context.sanitizer)

        let state: ChemistryActionState
        let disposition: CorrectionDisposition

        if value < actNowLowBoundary {
            state = .actNowLow; disposition = .treatNow
        } else if value < ideal.lowerBound {
            state = .recommendedLow; disposition = .treatNow
        } else if value <= ideal.upperBound {
            state = .ideal; disposition = .noAction
        } else if value <= actNowHighBoundary {
            state = .recommendedHigh
            // High TA is corrected via pH/acid/aeration as pH permits — not an immediate acid dump.
            disposition = .treatWhenChemicallyAppropriate
        } else {
            state = .actNowHigh; disposition = .treatWhenChemicallyAppropriate
        }

        // Non-swim parameter: an out-of-band extreme can drive scaling/corrosion, so `actNow` is Act Now.
        let severity: ChemistrySeverity = state.isActNow ? .severe : .none

        return ParameterClassification(
            parameter: .totalAlkalinity, value: value, actionState: state, disposition: disposition,
            blocksSwimming: false, severity: severity, correctionTarget: state == .ideal ? nil : target,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - Calcium Hardness (surface-aware; never a direct swim gate; no chemical reducer)

enum CalciumHardnessPolicy {
    static func idealRange(surface: SurfaceType) -> ClosedRange<Double> {
        switch surface {
        case .plaster, .pebble:   return 200...400
        case .vinyl, .fiberglass: return 150...300
        }
    }

    /// Where a low-CH correction should aim: comfortably inside the range, not the boundary.
    static func lowCorrectionTarget(surface: SurfaceType) -> Double {
        switch surface {
        case .plaster, .pebble:   return 275   // ~250–300
        case .vinyl, .fiberglass: return 225
        }
    }

    static func actNowLowBoundary(surface: SurfaceType) -> Double {
        idealRange(surface: surface).lowerBound - 50   // plaster 150, vinyl/fiberglass 100
    }

    /// Unconditional high ceiling; scaling/LSI evidence can escalate earlier (see disposition).
    static let actNowHighCeiling = 1000.0

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let ideal = idealRange(surface: context.surface)
        let actNowLow = actNowLowBoundary(surface: context.surface)

        let scalingEscalation = context.hasScalingEvidence || ((context.pH ?? 0) >= 7.8)

        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let target: Double?

        if value < actNowLow {
            state = .actNowLow; disposition = .treatNow; target = lowCorrectionTarget(surface: context.surface)
        } else if value < ideal.lowerBound {
            state = .recommendedLow; disposition = .treatNow; target = lowCorrectionTarget(surface: context.surface)
        } else if value <= ideal.upperBound {
            state = .ideal; disposition = .noAction; target = nil
        } else if value >= actNowHighCeiling {
            state = .actNowHigh; disposition = .dilute; target = nil
        } else if value > ideal.upperBound && scalingEscalation {
            // Water-balance / scaling risk escalates high CH before 1000.
            state = .actNowHigh; disposition = .treatWhenChemicallyAppropriate; target = nil
        } else {
            state = .recommendedHigh; disposition = .treatWhenChemicallyAppropriate; target = nil
        }

        let severity: ChemistrySeverity = state.isActNow ? .severe : .none

        return ParameterClassification(
            parameter: .calciumHardness, value: value, actionState: state, disposition: disposition,
            blocksSwimming: false, severity: severity, correctionTarget: target,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - Cyanuric Acid (system-aware resolver; modulates FC; never a direct swim gate)

enum CyanuricAcidPolicy {
    /// System-aware hook. Same range for SWG/non-SWG for now, per approved spec, but resolver-shaped.
    static func idealRange(isSaltwater: Bool) -> ClosedRange<Double> {
        30...50
    }

    static let correctionTarget = 40.0
    static let veryLowBoundary = 15.0
    static let diluteBoundary = 90.0

    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let ideal = idealRange(isSaltwater: context.isSaltwater)

        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let target: Double?

        if value < veryLowBoundary {
            // Extremely low CYA -> UV chlorine-loss risk -> stronger pool-care urgency.
            state = .actNowLow; disposition = .treatNow; target = correctionTarget
        } else if value < ideal.lowerBound {
            state = .recommendedLow; disposition = .treatNow; target = correctionTarget
        } else if value <= ideal.upperBound {
            state = .ideal; disposition = .noAction; target = nil
        } else if value < diluteBoundary {
            // Manageable elevated CYA: maintain higher CYA-adjusted FC, avoid stabilized chlorine.
            state = .recommendedHigh; disposition = .monitorOnly; target = nil
        } else {
            state = .actNowHigh; disposition = .dilute; target = nil
        }

        let severity: ChemistrySeverity = state.isActNow ? .severe : .none

        return ParameterClassification(
            parameter: .cyanuricAcid, value: value, actionState: state, disposition: disposition,
            blocksSwimming: false, severity: severity, correctionTarget: target,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}

// MARK: - Salt / SWG (configurable range; never a direct swim gate)

enum SaltPolicy {
    static func classify(_ value: Double, _ context: ChemistryPolicyContext) -> ParameterClassification {
        let range = context.saltRange
        let recommendedLowFloor = range.minimum - 300   // generic: 2400

        let state: ChemistryActionState
        let disposition: CorrectionDisposition
        let target: Double?

        if value < recommendedLowFloor {
            state = .actNowLow; disposition = .treatNow; target = range.target
        } else if value < range.minimum {
            state = .recommendedLow; disposition = .treatNow; target = range.target
        } else if value <= range.maximum {
            state = .ideal; disposition = .noAction; target = nil
        } else if value <= range.maximum + 200 {
            state = .recommendedHigh; disposition = .dilute; target = nil
        } else {
            state = .actNowHigh; disposition = .dilute; target = nil
        }

        let severity: ChemistrySeverity = state.isActNow ? .severe : .none

        return ParameterClassification(
            parameter: .saltLevel, value: value, actionState: state, disposition: disposition,
            blocksSwimming: false, severity: severity, correctionTarget: target,
            derivedUrgency: TreatmentUrgency.derived(state: state, disposition: disposition, severity: severity)
        )
    }
}
