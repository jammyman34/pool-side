import Foundation

struct SwimabilityV2Comparison: Equatable, Sendable {
    let existingStatus: String
    let existingScore: Int
    let v2Assessment: SwimabilityV2Assessment
    let meaningfulDifferences: [String]
    let generatedAt: Date
    let actualEvaluationTimestamp: Date?
    let normalizedPoolState: NormalizedPoolState?
    let evaluationContext: String

    init(
        existingStatus: String,
        existingScore: Int,
        v2Assessment: SwimabilityV2Assessment,
        meaningfulDifferences: [String],
        generatedAt: Date,
        actualEvaluationTimestamp: Date? = nil,
        normalizedPoolState: NormalizedPoolState? = nil,
        evaluationContext: String = "Unspecified"
    ) {
        self.existingStatus = existingStatus
        self.existingScore = existingScore
        self.v2Assessment = v2Assessment
        self.meaningfulDifferences = meaningfulDifferences
        self.generatedAt = generatedAt
        self.actualEvaluationTimestamp = actualEvaluationTimestamp
        self.normalizedPoolState = normalizedPoolState
        self.evaluationContext = evaluationContext
    }

    var developerDescription: String {
        var lines = [
            "===== POOL SIDE V2 SWIMABILITY =====",
            "Evaluation Context: \(evaluationContext)"
        ]

        if let actualEvaluationTimestamp {
            lines += [
                "Actual Evaluation Timestamp: \(formattedDate(actualEvaluationTimestamp))",
                "Simulated Evaluation Timestamp: \(formattedDate(generatedAt))"
            ]
        } else {
            lines.append("Evaluation Timestamp: \(formattedDate(generatedAt))")
        }

        if let normalizedPoolState {
            lines += normalizedContextLines(for: normalizedPoolState)
        }

        lines += [
            "V1 Score: \(existingScore)",
            "V1 Status: \(existingStatus)",
            "V2 Swimability: \(displayName(for: v2Assessment.state))",
            "Evidence Type: \(displayName(for: v2Assessment.evidenceType))",
            "Confidence: \(displayName(for: v2Assessment.confidence))",
            "Treatment-Aware Swimability: \(displayName(for: v2Assessment.state))",
            "Prediction Confidence: \(v2Assessment.predictionConfidence.map(displayName(for:)) ?? "N/A")",
            "Earliest Predicted Ready Time: \(v2Assessment.earliestPredictedReadyTime.map(formattedDate) ?? "None")",
            "Testing Required: \(yesNo(v2Assessment.testingRequired))",
            "Swimming Blocked: \(yesNo(v2Assessment.swimmingBlocked))",
            "Swim Readiness Gates:"
        ]

        lines += v2Assessment.gateResults.map(formattedGateLine)
        lines += treatmentAwareLines()

        lines += [
            "Failed Gates: \(formattedGateList(v2Assessment.failedGates))",
            "Unknown Gates: \(formattedGateList(v2Assessment.unknownGates))",
            "Invalidation Reasons: \(formattedList(v2Assessment.invalidationReasons))",
            "Meaningful V1/V2 Differences: \(formattedList(meaningfulDifferences))",
            "===== END POOL SIDE V2 SWIMABILITY ====="
        ]

        return lines.joined(separator: "\n")
    }

    private func treatmentAwareLines() -> [String] {
        guard let context = v2Assessment.treatmentAwareContext else {
            return [
                "Active Treatment Count: 0",
                "Treatment Classifications: None",
                "Treatment Completion States: None",
                "Active Waits: None",
                "Verification Required: No",
                "Remaining Blockers: None"
            ]
        }

        return [
            "Active Treatment Count: \(context.activeTreatmentCount)",
            "Treatment Classifications: \(formattedTreatmentClassifications(context.classifications))",
            "Treatment Completion States: \(formattedTreatmentCompletionStates(context.classifications))",
            "Active Waits: \(formattedList(context.activeWaitDescriptions))",
            "Verification Required: \(yesNo(context.verificationRequired))",
            "Remaining Blockers: \(formattedList(context.remainingBlockers))"
        ]
    }

    private func formattedTreatmentClassifications(_ classifications: [V2TreatmentClassification]) -> String {
        guard !classifications.isEmpty else { return "None" }
        return classifications
            .map { "\($0.treatmentName)=\($0.category.rawValue)" }
            .joined(separator: "; ")
    }

    private func formattedTreatmentCompletionStates(_ classifications: [V2TreatmentClassification]) -> String {
        guard !classifications.isEmpty else { return "None" }
        return classifications
            .map { "\($0.treatmentName)=\($0.completionState.rawValue)" }
            .joined(separator: "; ")
    }

    private func normalizedContextLines(for state: NormalizedPoolState) -> [String] {
        var chemistry = [
            "FC \(format(state.freeChlorine))",
            "CC \(format(state.combinedChlorine))"
        ]
        if state.totalChlorine != nil {
            chemistry.append("TC \(format(state.totalChlorine))")
        }
        chemistry += [
            "pH \(format(state.pH))",
            "TA \(format(state.totalAlkalinity))",
            "CH \(format(state.calciumHardness))",
            "CYA \(format(state.cyanuricAcid))"
        ]
        if state.saltSystemEnabled {
            chemistry.append("Salt \(format(state.saltLevel))")
        }
        if state.waterTemperature != nil {
            chemistry.append("Water Temp \(format(state.waterTemperature))")
        }

        return [
            "Current Test Timestamp: \(formattedDate(state.testDate))",
            "Current Test ID: \(state.currentTestID.uuidString)",
            "Test Method: \(state.actualTestMethod.displayName)",
            "Test Age Minutes: \(state.ageInMinutes)",
            "Chemistry: \(chemistry.joined(separator: " | "))",
            "Water Clarity: \(state.normalizedWaterClarity.rawValue)",
            "Visible Algae: \(state.normalizedVisibleAlgae.rawValue)",
            "Odor: \(state.odorReported.rawValue)",
            "Foam: \(state.foamReported.rawValue)",
            "Recent Rain: \(state.recentRain.rawValue)",
            "Recent Refill: \(state.recentRefill.rawValue)",
            "Recent Backwash: \(state.recentBackwash.rawValue)",
            "Recent Heavy Bather Load: \(state.recentHeavyBatherLoad.rawValue)",
            "Contamination Concern: \(state.recentContaminationConcern.rawValue)",
            "Active Treatments: \(state.activeTreatmentCount)",
            "Completed Treatments: \(state.completedTreatmentCount)",
            "Skipped Treatments: \(state.skippedTreatmentCount)",
            "Circulation Status: \(state.circulationStatus.rawValue)"
        ]
    }

    private func formattedGateLine(_ gate: SwimReadinessGateResult) -> String {
        "\(displayName(for: gate.identifier)): \(displayName(for: gate.state)) | Blocks: \(yesNo(gate.blocksSwimming)) | Test: \(yesNo(gate.requiresTesting)) | \(gate.reason)"
    }

    private func formattedGateList(_ gates: [SwimReadinessGateResult]) -> String {
        guard !gates.isEmpty else { return "None" }
        return gates.map { displayName(for: $0.identifier) }.joined(separator: ", ")
    }

    private func formattedList(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: "; ")
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "notRecorded" }
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func displayName(for state: SwimabilityState) -> String {
        switch state {
        case .readyToSwim: return "Ready to Swim"
        case .expectedReadyAfterTreatment: return "Expected Ready After Treatment"
        case .expectedReadyAroundTime: return "Expected Ready Around Time"
        case .testBeforeSwimming: return "Test Before Swimming"
        case .doNotSwim: return "Do Not Swim"
        case .moreInformationNeeded: return "More Information Needed"
        }
    }

    private func displayName(for evidenceType: SwimabilityEvidenceType) -> String {
        switch evidenceType {
        case .observed: return "Observed"
        case .predicted: return "Predicted"
        case .confirmed: return "Confirmed"
        case .unknown: return "Unknown"
        }
    }

    private func displayName(for confidence: SwimabilityConfidence) -> String {
        switch confidence {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .insufficient: return "Insufficient"
        }
    }

    private func displayName(for gateState: SwimReadinessGateState) -> String {
        switch gateState {
        case .pass: return "PASS"
        case .fail: return "FAIL"
        case .unknown: return "UNKNOWN"
        case .notApplicable: return "N/A"
        }
    }

    private func displayName(for identifier: SwimReadinessGateIdentifier) -> String {
        switch identifier {
        case .sanitizerAdequacy: return "Sanitizer Adequacy"
        case .pH: return "pH"
        case .combinedChlorine: return "Combined Chlorine"
        case .waterClarity: return "Water Clarity"
        case .visibleAlgae: return "Visible Algae"
        case .testFreshness: return "Test Freshness"
        case .treatmentCompletion: return "Treatment Completion"
        case .circulation: return "Circulation"
        case .productReentry: return "Product Re-entry"
        }
    }
}
