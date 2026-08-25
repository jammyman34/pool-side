import Foundation

struct SwimabilityV2Engine {
    private let normalizer = PoolStateNormalizer()
    private let gateEvaluator = SwimReadinessGateEvaluator()
    private let treatmentClassifier = V2TreatmentClassifier()

    func assess(request: AIRecommendationRequest) -> SwimabilityV2Assessment {
        assess(request: request, evaluationDate: Date())
    }

    func assess(request: AIRecommendationRequest, evaluationDate: Date) -> SwimabilityV2Assessment {
        let state = normalizer.normalize(request: request, evaluationDate: evaluationDate)
        let treatmentContext = treatmentClassifier.classify(treatments: request.currentTest.treatments, evaluationDate: evaluationDate)
        let gateResults = gateEvaluator.evaluate(state: state, treatmentContext: treatmentContext)
        let invalidationReasons = invalidationReasons(for: state)
        let observedConfidence = confidence(for: state, gateResults: gateResults, invalidationReasons: invalidationReasons)
        let predictionConfidence = predictionConfidence(for: treatmentContext, gateResults: gateResults)
        let swimabilityState = swimabilityState(
            for: gateResults,
            observedConfidence: observedConfidence,
            predictionConfidence: predictionConfidence,
            treatmentContext: treatmentContext
        )
        let evidenceType = evidenceType(for: swimabilityState, treatmentContext: treatmentContext)
        let confidence = evidenceType == .predicted ? (predictionConfidence ?? observedConfidence) : observedConfidence
        let testingRequired = swimabilityState == .testBeforeSwimming
            || gateResults.contains { ($0.state == .fail || $0.state == .unknown) && $0.requiresTesting }

        return SwimabilityV2Assessment(
            state: swimabilityState,
            evidenceType: evidenceType,
            confidence: confidence,
            predictionConfidence: predictionConfidence,
            gateResults: gateResults,
            invalidationReasons: invalidationReasons,
            testingRequired: testingRequired,
            earliestPredictedReadyTime: predictedReadyTime(for: swimabilityState, treatmentContext: treatmentContext),
            treatmentAwareContext: treatmentContext,
            summary: summary(for: swimabilityState, evidenceType: evidenceType, confidence: confidence, gateResults: gateResults)
        )
    }

    private func swimabilityState(
        for gateResults: [SwimReadinessGateResult],
        observedConfidence: SwimabilityConfidence,
        predictionConfidence: SwimabilityConfidence?,
        treatmentContext: V2TreatmentAwareContext
    ) -> SwimabilityState {
        if hardObservedGateFailureExists(in: gateResults, treatmentContext: treatmentContext) {
            return .doNotSwim
        }

        let blockingUnknowns = hardObservedUnknowns(in: gateResults)
        if !blockingUnknowns.isEmpty {
            return blockingUnknowns.contains(where: \.requiresTesting) ? .testBeforeSwimming : .moreInformationNeeded
        }

        if treatmentContext.hasCompletedVerificationRequiredTreatment {
            return .testBeforeSwimming
        }

        if treatmentContext.hasCompletedWaitingTreatment {
            guard let predictionConfidence, predictionConfidence == .high || predictionConfidence == .medium else {
                return .moreInformationNeeded
            }
            return treatmentContext.earliestPredictedReadyTime == nil ? .expectedReadyAfterTreatment : .expectedReadyAroundTime
        }

        if treatmentContext.hasUnknownReentryRequirement {
            return .moreInformationNeeded
        }

        if treatmentContext.hasSwimBlockingActiveTreatment {
            return .expectedReadyAfterTreatment
        }

        if observedConfidence == .high || observedConfidence == .medium {
            return .readyToSwim
        }

        return .moreInformationNeeded
    }

    private func confidence(
        for state: NormalizedPoolState,
        gateResults: [SwimReadinessGateResult],
        invalidationReasons: [String]
    ) -> SwimabilityConfidence {
        if !state.internallyConflictingReadingIdentifiers.isEmpty
            || gateResults.contains(where: { $0.state == .unknown && $0.blocksSwimming }) {
            return .insufficient
        }

        switch state.testMethodConfidence {
        case .high:
            return invalidationReasons.isEmpty ? .high : .medium
        case .medium:
            return .medium
        case .low:
            return .low
        case .unknown:
            return .insufficient
        }
    }

    private func predictionConfidence(
        for treatmentContext: V2TreatmentAwareContext,
        gateResults: [SwimReadinessGateResult]
    ) -> SwimabilityConfidence? {
        guard !treatmentContext.classifications.isEmpty else { return nil }

        if hardObservedGateFailureExists(in: gateResults, treatmentContext: treatmentContext)
            || treatmentContext.hasCompletedVerificationRequiredTreatment
            || treatmentContext.hasUnresolvedRecoveryAction {
            return .insufficient
        }

        if treatmentContext.hasUnknownReentryRequirement {
            return .low
        }

        if treatmentContext.hasCompletedWaitingTreatment {
            return treatmentContext.earliestPredictedReadyTime == nil ? .low : .medium
        }

        if treatmentContext.hasSwimBlockingActiveTreatment {
            return .medium
        }

        return .medium
    }

    private func evidenceType(
        for state: SwimabilityState,
        treatmentContext: V2TreatmentAwareContext
    ) -> SwimabilityEvidenceType {
        if treatmentContext.classifications.isEmpty {
            return .observed
        }

        switch state {
        case .expectedReadyAfterTreatment, .expectedReadyAroundTime:
            return .predicted
        case .readyToSwim where treatmentContext.classifications.contains(where: { $0.completedAt != nil }):
            return .predicted
        default:
            return .observed
        }
    }

    private func predictedReadyTime(
        for state: SwimabilityState,
        treatmentContext: V2TreatmentAwareContext
    ) -> Date? {
        state == .expectedReadyAroundTime ? treatmentContext.earliestPredictedReadyTime : nil
    }

    private func hardObservedGateFailureExists(
        in gateResults: [SwimReadinessGateResult],
        treatmentContext: V2TreatmentAwareContext
    ) -> Bool {
        gateResults.contains { gate in
            gate.state == .fail
                && gate.blocksSwimming
                && !treatmentAwareGateIdentifiers.contains(gate.identifier)
                && !treatmentContext.pendingVerificationGateIdentifiers.contains(gate.identifier)
        }
    }

    private func hardObservedUnknowns(in gateResults: [SwimReadinessGateResult]) -> [SwimReadinessGateResult] {
        gateResults.filter { gate in
            gate.state == .unknown
                && gate.blocksSwimming
                && !treatmentAwareGateIdentifiers.contains(gate.identifier)
        }
    }

    private var treatmentAwareGateIdentifiers: Set<SwimReadinessGateIdentifier> {
        [.treatmentCompletion, .circulation, .productReentry]
    }

    private func invalidationReasons(for state: NormalizedPoolState) -> [String] {
        var reasons = [String]()

        if state.recentRain == .reportedPresent {
            reasons.append("recent rain")
        }
        if state.recentRefill == .reportedPresent {
            reasons.append("recent refill")
        }
        if state.recentBackwash == .reportedPresent {
            reasons.append("recent backwash")
        }
        if state.recentHeavyBatherLoad == .reportedPresent {
            reasons.append("recent heavy bather load")
        }
        if state.activeTreatmentCount > 0 {
            reasons.append("active treatment activity")
        }
        if !state.internallyConflictingReadingIdentifiers.isEmpty {
            reasons.append("internally conflicting readings: \(state.internallyConflictingReadingIdentifiers.joined(separator: ", "))")
        }

        return reasons
    }

    private func summary(
        for state: SwimabilityState,
        evidenceType: SwimabilityEvidenceType,
        confidence: SwimabilityConfidence,
        gateResults: [SwimReadinessGateResult]
    ) -> String {
        let failed = gateResults.filter { $0.state == .fail }.map(\.identifier.rawValue)
        let unknown = gateResults.filter { $0.state == .unknown }.map(\.identifier.rawValue)

        // The explanation must name the same evidence basis reported by `evidenceType` (observed /
        // predicted / confirmed / unknown) so the two never disagree.
        return state.rawValue
            + " \(evidenceType.rawValue) assessment with "
            + confidence.rawValue
            + " confidence. Failed gates: "
            + (failed.isEmpty ? "none" : failed.joined(separator: ", "))
            + ". Unknown gates: "
            + (unknown.isEmpty ? "none" : unknown.joined(separator: ", "))
            + "."
    }
}
