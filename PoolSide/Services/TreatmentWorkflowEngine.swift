import Foundation

struct TreatmentWorkflowEngine {
    enum StepState: Equatable {
        case current
        case waiting(availableAt: Date)
        case upcoming
        case completed
        case skipped
    }

    struct FocusedCheckDescriptor: Equatable {
        let parameters: [String]
        let title: String
        let timingText: String
        let body: String
        let delayMinutes: Int
        let optional: Bool
    }

    private let nextTestEngine = NextTestRecommendationEngine()

    func workflowSteps(from treatments: [Treatment]) -> [Treatment] {
        treatments
            .filter { !$0.isWatchlistItem }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder { return lhs.createdAt < rhs.createdAt }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func checkDescriptor(for treatment: Treatment) -> FocusedCheckDescriptor? {
        guard !treatment.isWatchlistItem, !treatment.isFocusedCheckStep else { return nil }

        if treatment.targetParameter == "freeChlorine" {
            let optional = treatment.urgency == .optional
            return FocusedCheckDescriptor(
                parameters: ["freeChlorine", "combinedChlorine"],
                title: "Check FC & CC",
                timingText: "\(waitText(minutes: chlorineDelayMinutes(for: treatment))) after adding chlorine",
                body: optional
                    ? "Optional: test FC and CC after circulation if you want to confirm the chlorine top-off."
                    : "Test FC and CC to confirm chlorine is safe before swimming.",
                delayMinutes: chlorineDelayMinutes(for: treatment),
                optional: optional
            )
        }

        if treatment.targetParameter == "pH", treatment.effectDelayHours >= 4 {
            return FocusedCheckDescriptor(
                parameters: ["pH"],
                title: "Check pH",
                timingText: "4 hours after adding \(shortChemicalName(treatment.chemicalName))",
                body: "Test pH to confirm it is back in the safe range.",
                delayMinutes: 240,
                optional: false
            )
        }

        if treatment.targetParameter == "totalAlkalinity", !treatment.isAcidTreatment, treatment.effectDelayHours > 0 {
            return FocusedCheckDescriptor(
                parameters: ["totalAlkalinity"],
                title: "Check TA",
                timingText: "6-8 hours after adding alkalinity increaser",
                body: "Test TA before making another alkalinity adjustment.",
                delayMinutes: treatment.effectDelayHours * 60,
                optional: false
            )
        }

        if treatment.targetParameter == "cyanuricAcid" {
            return FocusedCheckDescriptor(
                parameters: ["cyanuricAcid"],
                title: "Check CYA",
                timingText: "24-48 hours after adding stabilizer",
                body: "Test CYA after circulation before adding more stabilizer.",
                delayMinutes: TreatmentApplicationPolicy.granularCYACanonicalRetestHours * 60,
                optional: false
            )
        }

        if treatment.targetParameter == "calciumHardness", treatment.effectDelayHours > 0 {
            return FocusedCheckDescriptor(
                parameters: ["calciumHardness"],
                title: "Check CH",
                timingText: "About 24 hours after adding calcium",
                body: "Test calcium hardness before adding more calcium increaser.",
                delayMinutes: treatment.effectDelayHours * 60,
                optional: false
            )
        }

        return nextTestEngine.treatmentRetestRecommendation(for: treatment, completedAt: treatment.createdAt).map { recommendation in
            FocusedCheckDescriptor(
                parameters: parameters(for: treatment.targetParameter),
                title: recommendation.title.replacingOccurrences(of: "Retest", with: "Check"),
                timingText: recommendation.relativeLabel,
                body: recommendation.body,
                delayMinutes: Int(recommendation.interval / 60),
                optional: false
            )
        }
    }

    func makeCheckStep(after treatment: Treatment, sortOrder: Int) -> Treatment? {
        guard let descriptor = checkDescriptor(for: treatment) else { return nil }
        let check = Treatment(
            chemicalName: descriptor.title,
            actionDescription: descriptor.timingText,
            amount: 0,
            unit: "",
            instructions: descriptor.body,
            urgency: descriptor.optional ? .optional : .recommended,
            isAIGenerated: true,
            targetParameter: descriptor.parameters.first ?? treatment.targetParameter,
            minutesBeforeNext: 0,
            sortOrder: sortOrder,
            expectedEffectParameter: descriptor.parameters.joined(separator: ","),
            effectDelayHours: max(1, descriptor.delayMinutes / 60),
            poolTest: treatment.poolTest
        )
        check.workflowStepKind = .focusedCheck
        check.checkParameters = descriptor.parameters
        check.parentTreatmentID = treatment.id
        return check
    }

    func state(for step: Treatment, in steps: [Treatment], evaluationDate: Date = Date()) -> StepState {
        if step.isCompleted { return .completed }
        if step.isSkipped { return .skipped }
        if step.isFocusedCheckStep, let availableAt = availableDate(for: step, in: steps) {
            if evaluationDate < availableAt { return .waiting(availableAt: availableAt) }
        }

        for candidate in steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if candidate.id == step.id { return .current }
            if !candidate.isCompleted && !candidate.isSkipped {
                if candidate.isFocusedCheckStep, let availableAt = availableDate(for: candidate, in: steps), evaluationDate >= availableAt {
                    return .upcoming
                }
                if !candidate.isFocusedCheckStep {
                    return .upcoming
                }
            }
        }
        return .upcoming
    }

    func availableDate(for checkStep: Treatment, in steps: [Treatment]) -> Date? {
        guard checkStep.isFocusedCheckStep, let parentID = checkStep.parentTreatmentID else { return nil }
        guard let parent = steps.first(where: { $0.id == parentID }), let completedAt = parent.completedAt else { return nil }
        let minutes = checkDelayMinutes(for: checkStep, parent: parent)
        return completedAt.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func checkDelayMinutes(for checkStep: Treatment, parent: Treatment) -> Int {
        if parent.targetParameter == "freeChlorine" { return chlorineDelayMinutes(for: parent) }
        if parent.targetParameter == "pH" { return 240 }
        if parent.targetParameter == "cyanuricAcid" { return TreatmentApplicationPolicy.granularCYACanonicalRetestHours * 60 }
        if parent.targetParameter == "totalAlkalinity" { return max(60, parent.effectDelayHours * 60) }
        if parent.targetParameter == "calciumHardness" { return max(60, parent.effectDelayHours * 60) }
        return max(0, parent.effectDelayHours * 60)
    }

    private func parameters(for targetParameter: String) -> [String] {
        switch targetParameter {
        case "freeChlorine": return ["freeChlorine", "combinedChlorine"]
        case "pH": return ["pH"]
        case "totalAlkalinity": return ["totalAlkalinity"]
        case "cyanuricAcid": return ["cyanuricAcid"]
        case "calciumHardness": return ["calciumHardness"]
        default: return [targetParameter]
        }
    }

    private func chlorineDelayMinutes(for treatment: Treatment) -> Int {
        if treatment.chemicalName.localizedCaseInsensitiveContains("tablet") { return 24 * 60 }
        if treatment.chemicalName.localizedCaseInsensitiveContains("granule")
            || treatment.chemicalName.localizedCaseInsensitiveContains("dichlor") { return 240 }
        return 60
    }

    private func waitText(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private func shortChemicalName(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("muriatic") { return "acid" }
        if name.localizedCaseInsensitiveContains("dry acid") { return "dry acid" }
        return name
    }
}

// MARK: - Focused Check outcome (explicit closure interpretation)

/// The user-relevant conclusion of a focused Check for one parameter, derived from the POST-check
/// reassessment (ChemistryPolicy for operating state, treatment generation for whether another
/// correction is required). Never determined by comparing to a hard-coded range in a View.
enum FocusedCheckOutcomeKind: String, Sendable, Equatable {
    /// In the operating range and no further correction for the parameter is generated.
    case resolved
    /// Moved toward target (observably) but still out of range; a fresh correction was generated.
    case improvedMoreCorrectionNeeded
    /// Still out of range with little/no observable movement; the engine recomputed an action.
    case stillOutOfRange
    /// Crossed to the opposite side of the operating range (now needs a correction the other way).
    case movedPastRange
    /// Out of the ideal range but the canonical disposition is non-chemical (natural correction /
    /// monitor / dilute) — do NOT claim "in range".
    case noChemicalActionNeeded
}

struct FocusedCheckParameterOutcome: Sendable, Equatable {
    let parameter: String
    let displayName: String
    let measuredValue: Double
    let kind: FocusedCheckOutcomeKind
    let inOperatingRange: Bool
    /// Canonical per-parameter swim gate (ChemistryPolicy). NOT an independent readiness computation.
    let blocksSwimming: Bool
    let hasFollowUpTreatment: Bool
    let operatingRangeText: String?
}

/// Aggregate result of a focused Check, supporting multi-parameter checks. Swim readiness is consumed
/// from Swimability V2 (`swimState`), never recomputed here.
struct FocusedCheckResult: Sendable, Equatable {
    let parameterOutcomes: [FocusedCheckParameterOutcome]
    let swimState: SwimabilityState?

    var hasFollowUpTreatment: Bool { parameterOutcomes.contains { $0.hasFollowUpTreatment } }
    var allResolved: Bool { !parameterOutcomes.isEmpty && parameterOutcomes.allSatisfy { $0.kind == .resolved } }
    var anyBlocksSwimming: Bool { parameterOutcomes.contains { $0.blocksSwimming } }

    /// The outcome that should dominate the headline (worst-first).
    var primaryOutcome: FocusedCheckParameterOutcome? {
        func rank(_ k: FocusedCheckOutcomeKind) -> Int {
            switch k {
            case .movedPastRange: return 0
            case .stillOutOfRange: return 1
            case .improvedMoreCorrectionNeeded: return 2
            case .noChemicalActionNeeded: return 3
            case .resolved: return 4
            }
        }
        return parameterOutcomes.min { rank($0.kind) < rank($1.kind) }
    }

    var title: String {
        guard let primary = primaryOutcome else { return "Check recorded" }
        let name = primary.displayName
        if allResolved {
            return parameterOutcomes.count == 1 ? "\(name) is now in range" : "Your check is in range"
        }
        switch primary.kind {
        case .resolved:
            return "\(name) is in range"
        case .improvedMoreCorrectionNeeded:
            return "\(name) improved — one more step"
        case .stillOutOfRange:
            return "\(name) needs another correction"
        case .movedPastRange:
            return "\(name) moved past the range"
        case .noChemicalActionNeeded:
            return "\(name) recorded"
        }
    }

    var interpretation: String {
        var lines: [String] = []
        for outcome in orderedForDisplay {
            lines.append(Self.interpretationLine(for: outcome))
        }
        return lines.joined(separator: " ")
    }

    var nextAction: String {
        var parts: [String] = []
        if hasFollowUpTreatment {
            parts.append("Pool Side recalculated from this reading and updated your plan with the next step — this is a fresh calculation, not a leftover dose.")
        } else if allResolved {
            parts.append("No further correction is needed for now. Continue normal monitoring — Pool Side will tell you when your next pool test is due.")
        } else {
            parts.append("Pool Side updated your plan based on this reading.")
        }
        // Swim readiness is owned by Swimability V2; surface it separately from the chemistry outcome.
        switch swimState {
        case .some(.readyToSwim):
            parts.append("The pool is currently ready for swimming.")
        case .some(.doNotSwim):
            parts.append("Swimming is not recommended right now — see the plan for what's needed.")
        case .some(.testBeforeSwimming):
            parts.append("Test again before swimming to confirm readiness.")
        default:
            break
        }
        return parts.joined(separator: " ")
    }

    private var orderedForDisplay: [FocusedCheckParameterOutcome] {
        parameterOutcomes.sorted { $0.parameter < $1.parameter }
    }

    private static func interpretationLine(for outcome: FocusedCheckParameterOutcome) -> String {
        let value = outcome.measuredValue.formattedTreatmentAmount
        let rangeClause = outcome.operatingRangeText.map { " (operating range \($0))" } ?? ""
        switch outcome.kind {
        case .resolved:
            return "\(outcome.displayName) is \(value), within its operating range\(rangeClause). No more \(outcome.displayName) correction is needed right now."
        case .improvedMoreCorrectionNeeded:
            return "\(outcome.displayName) is \(value) — it moved in the right direction but is still outside the operating range\(rangeClause)."
        case .stillOutOfRange:
            return "\(outcome.displayName) is \(value) and is still outside the operating range\(rangeClause)."
        case .movedPastRange:
            return "\(outcome.displayName) is \(value), which is now on the other side of the operating range\(rangeClause)."
        case .noChemicalActionNeeded:
            return "\(outcome.displayName) is \(value); it's outside the ideal range but does not need a chemical correction right now."
        }
    }
}

/// Derives a `FocusedCheckResult` from post-Check evidence and the regenerated treatment plan.
/// Pure and deterministic: ChemistryPolicy decides operating state and swim gate; the regenerated
/// treatments decide whether another correction is required; MeasurementResolution decides whether a
/// change is observable. Swim readiness (`swimState`) is supplied by the caller from Swimability V2.
struct FocusedCheckOutcomeEvaluator {

    func result(
        checkedParameters: [String],
        priorValues: [String: Double],
        measuredValues: [String: Double],
        postCheckTest: PoolTest,
        postCheckTreatments: [Treatment],
        config: PoolConfiguration,
        swimState: SwimabilityState?
    ) -> FocusedCheckResult {
        let outcomes = checkedParameters.compactMap { parameter -> FocusedCheckParameterOutcome? in
            guard let measured = measuredValues[parameter] ?? currentValue(of: parameter, in: postCheckTest) else { return nil }
            return outcome(
                parameter: parameter,
                priorValue: priorValues[parameter],
                measuredValue: measured,
                postCheckTest: postCheckTest,
                postCheckTreatments: postCheckTreatments,
                config: config
            )
        }
        return FocusedCheckResult(parameterOutcomes: outcomes, swimState: swimState)
    }

    func outcome(
        parameter: String,
        priorValue: Double?,
        measuredValue: Double,
        postCheckTest: PoolTest,
        postCheckTreatments: [Treatment],
        config: PoolConfiguration
    ) -> FocusedCheckParameterOutcome {
        guard let chemParameter = ChemistryParameter(rawValue: parameter) else {
            return FocusedCheckParameterOutcome(
                parameter: parameter, displayName: displayName(parameter), measuredValue: measuredValue,
                kind: .noChemicalActionNeeded, inOperatingRange: false, blocksSwimming: false,
                hasFollowUpTreatment: false, operatingRangeText: nil
            )
        }

        // Measurement resolution must reflect how the Check itself was measured (the test's method),
        // not the global config default, so we never manufacture or dismiss a change the actual reading
        // could/couldn't observe.
        var effectiveConfig = config
        effectiveConfig.testMethod = postCheckTest.testMethod
        let context = ChemistryPolicyContext.make(
            config: effectiveConfig,
            cyanuricAcid: postCheckTest.cyanuricAcid,
            pH: postCheckTest.pH,
            totalAlkalinity: postCheckTest.totalAlkalinity,
            hasScalingEvidence: false,
            chlorineSampleSize: postCheckTest.taylorSampleSize
        )
        let newClass = ChemistryPolicy.classify(chemParameter, value: measuredValue, context: context)
        let inRange = newClass.actionState == .ideal
        let followUp = hasFollowUpTreatment(for: parameter, in: postCheckTreatments)

        let kind: FocusedCheckOutcomeKind
        if inRange && !followUp {
            kind = .resolved
        } else {
            let increment = context.measurement.increment(for: chemParameter)
            let observableChange = priorValue.map { abs(measuredValue - $0) >= increment - 1e-9 } ?? true
            let priorClass = priorValue.map { ChemistryPolicy.classify(chemParameter, value: $0, context: context) }
            let crossedPast: Bool = {
                guard let priorClass else { return false }
                return (priorClass.actionState.isHigh && newClass.actionState.isLow)
                    || (priorClass.actionState.isLow && newClass.actionState.isHigh)
            }()
            let movedToward: Bool = {
                guard let priorClass, let priorValue, observableChange else { return false }
                if priorClass.actionState.isHigh { return measuredValue < priorValue }
                if priorClass.actionState.isLow { return measuredValue > priorValue }
                return false
            }()

            if inRange {
                kind = .resolved
            } else if crossedPast {
                kind = .movedPastRange
            } else if followUp {
                kind = movedToward ? .improvedMoreCorrectionNeeded : .stillOutOfRange
            } else {
                kind = .noChemicalActionNeeded
            }
        }

        return FocusedCheckParameterOutcome(
            parameter: parameter,
            displayName: displayName(parameter),
            measuredValue: measuredValue,
            kind: kind,
            inOperatingRange: inRange,
            blocksSwimming: newClass.blocksSwimming,
            hasFollowUpTreatment: followUp,
            operatingRangeText: operatingRangeText(for: chemParameter, context: context)
        )
    }

    // MARK: - Helpers

    private func hasFollowUpTreatment(for parameter: String, in treatments: [Treatment]) -> Bool {
        let family = parameterFamily(parameter)
        return treatments.contains { treatment in
            !treatment.isCompleted && !treatment.isSkipped && !treatment.isFocusedCheckStep
                && !treatment.isWatchlistItem
                && parameterFamily(treatment.targetParameter) == family
                && (treatment.urgency == .immediate || treatment.urgency == .recommended)
                && treatment.amount > 0
        }
    }

    private func parameterFamily(_ parameter: String) -> String {
        switch parameter {
        case "freeChlorine", "combinedChlorine", "totalChlorine": return "chlorine"
        default: return parameter
        }
    }

    private func currentValue(of parameter: String, in test: PoolTest) -> Double? {
        switch parameter {
        case "freeChlorine": return test.freeChlorine
        case "combinedChlorine": return test.combinedChlorine
        case "pH": return test.pH
        case "totalAlkalinity": return test.totalAlkalinity
        case "calciumHardness": return test.calciumHardness
        case "cyanuricAcid": return test.cyanuricAcid
        case "saltLevel": return test.saltLevel
        default: return nil
        }
    }

    private func displayName(_ parameter: String) -> String {
        switch parameter {
        case "freeChlorine": return "FC"
        case "combinedChlorine": return "CC"
        case "pH": return "pH"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        case "saltLevel": return "Salt"
        default: return parameter
        }
    }

    private func operatingRangeText(for parameter: ChemistryParameter, context: ChemistryPolicyContext) -> String? {
        switch parameter {
        case .pH:
            return "\(PHPolicy.operatingRange.lowerBound.formattedTreatmentAmount)–\(PHPolicy.operatingRange.upperBound.formattedTreatmentAmount)"
        case .freeChlorine:
            let range = FreeChlorinePolicy.operatingRange(cyanuricAcid: context.cyanuricAcid)
            return "\(range.lowerBound.formattedTreatmentAmount)–\(range.upperBound.formattedTreatmentAmount) ppm"
        case .combinedChlorine:
            return "at or below \(CombinedChlorinePolicy.readinessThreshold.formattedTreatmentAmount) ppm"
        default:
            return nil
        }
    }
}
