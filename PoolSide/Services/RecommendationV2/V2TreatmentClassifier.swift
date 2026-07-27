import Foundation

struct V2TreatmentClassifier {
    func classify(treatments: [Treatment], evaluationDate: Date) -> V2TreatmentAwareContext {
        let classifications = treatments
            .filter { !$0.isWatchlistItem && !$0.isFocusedCheckStep }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map { classify(treatment: $0, evaluationDate: evaluationDate) }

        let activeWaits = classifications.compactMap { classification -> String? in
            guard classification.completionState == .completedWaiting, let readyAt = classification.readyAt else { return nil }
            return "\(classification.treatmentName) until \(shortTime(readyAt))"
        }
        let remainingBlockers = classifications
            .filter { $0.blocksCurrentSwimability || $0.verificationRequiredBeforeSwimming }
            .map { $0.reason }

        return V2TreatmentAwareContext(
            classifications: classifications,
            activeTreatmentCount: classifications.filter { $0.completionState == .plannedTreatment }.count,
            verificationRequired: classifications.contains { $0.verificationRequiredBeforeSwimming },
            earliestPredictedReadyTime: classifications.compactMap(\.readyAt).max(),
            activeWaitDescriptions: activeWaits,
            remainingBlockers: remainingBlockers
        )
    }

    private func classify(treatment: Treatment, evaluationDate: Date) -> V2TreatmentClassification {
        let category = category(for: treatment)
        let waitMinutes = waitMinutes(for: treatment, category: category)
        let pendingVerificationGateIdentifiers = pendingVerificationGateIdentifiers(for: treatment)
        let verificationRequired = verificationRequired(for: treatment, category: category, pendingVerificationGateIdentifiers: pendingVerificationGateIdentifiers)
        let completionState = completionState(
            for: treatment,
            category: category,
            waitMinutes: waitMinutes,
            verificationRequired: verificationRequired,
            evaluationDate: evaluationDate
        )
        let blocks = blocksCurrentSwimability(
            treatment: treatment,
            category: category,
            completionState: completionState,
            verificationRequired: verificationRequired
        )
        let readyAt = readyAt(for: treatment, waitMinutes: waitMinutes)

        return V2TreatmentClassification(
            treatmentID: treatment.id,
            treatmentName: treatment.chemicalName,
            targetParameter: treatment.targetParameter,
            category: category,
            completionState: completionState,
            blocksCurrentSwimability: blocks,
            startsWaitOnCompletion: waitMinutes != nil,
            verificationRequiredBeforeSwimming: verificationRequired,
            pendingVerificationGateIdentifiers: pendingVerificationGateIdentifiers,
            waitMinutes: waitMinutes,
            completedAt: treatment.completedAt,
            readyAt: completionState == .completedWaiting ? readyAt : nil,
            reason: reason(for: treatment, category: category, completionState: completionState, verificationRequired: verificationRequired)
        )
    }

    private func category(for treatment: Treatment) -> V2TreatmentClassificationCategory {
        if treatment.targetParameter == "visualIndicators" || treatment.amount == 0 {
            return .nonChemicalAction
        }

        switch treatment.targetParameter {
        case "freeChlorine":
            if isRecoveryChlorine(treatment) || !pendingVerificationGateIdentifiers(for: treatment).isEmpty {
                return .swimBlocking
            }
            return treatment.urgency == .optional ? .poolCare : .both
        case "pH":
            return .swimBlocking
        case "totalAlkalinity":
            return treatment.isAcidTreatment ? .swimBlocking : .poolCare
        case "calciumHardness", "cyanuricAcid", "saltLevel":
            return .poolCare
        default:
            return treatment.urgency == .immediate ? .both : .poolCare
        }
    }

    private func completionState(
        for treatment: Treatment,
        category: V2TreatmentClassificationCategory,
        waitMinutes: Int?,
        verificationRequired: Bool,
        evaluationDate: Date
    ) -> V2TreatmentCompletionState {
        if treatment.isSkipped {
            return .skippedTreatment
        }

        if category == .nonChemicalAction {
            return treatment.isCompleted ? .noActiveTreatment : .unresolvedRecoveryAction
        }

        guard treatment.isCompleted else {
            return .plannedTreatment
        }

        if category == .poolCare && !verificationRequired {
            return .noActiveTreatment
        }

        guard let waitMinutes, let completedAt = treatment.completedAt else {
            return verificationRequired ? .completedVerificationRequired : (waitMinutes == nil ? .noActiveTreatment : .plannedTreatment)
        }

        let readyAt = completedAt.addingTimeInterval(TimeInterval(waitMinutes * 60))
        if readyAt > evaluationDate {
            return .completedWaiting
        }

        return verificationRequired ? .completedVerificationRequired : .noActiveTreatment
    }

    private func blocksCurrentSwimability(
        treatment: Treatment,
        category: V2TreatmentClassificationCategory,
        completionState: V2TreatmentCompletionState,
        verificationRequired: Bool
    ) -> Bool {
        switch completionState {
        case .noActiveTreatment:
            return false
        case .plannedTreatment:
            return category == .swimBlocking || category == .both
        case .completedWaiting, .completedVerificationRequired:
            return true
        case .skippedTreatment:
            return category == .swimBlocking || category == .both
        case .unresolvedRecoveryAction:
            return false
        }
    }

    private func waitMinutes(for treatment: Treatment, category: V2TreatmentClassificationCategory) -> Int? {
        guard category != .nonChemicalAction else { return nil }
        if treatment.minutesBeforeNext > 0 {
            return treatment.minutesBeforeNext
        }

        switch treatment.targetParameter {
        case "freeChlorine":
            return 60
        case "pH":
            return 240
        case "totalAlkalinity":
            return treatment.isAcidTreatment ? 240 : nil
        default:
            return nil
        }
    }

    private func verificationRequired(
        for treatment: Treatment,
        category: V2TreatmentClassificationCategory,
        pendingVerificationGateIdentifiers: Set<SwimReadinessGateIdentifier>
    ) -> Bool {
        guard category != .nonChemicalAction else { return false }
        if isRecoveryChlorine(treatment) {
            return true
        }
        if !pendingVerificationGateIdentifiers.isEmpty {
            return true
        }
        return treatment.urgency == .immediate
            && (treatment.targetParameter == "freeChlorine" || treatment.targetParameter == "pH")
    }

    private func pendingVerificationGateIdentifiers(for treatment: Treatment) -> Set<SwimReadinessGateIdentifier> {
        guard let test = treatment.poolTest else { return [] }
        let chemistryEngine = ChemistryEngine()
        var identifiers = Set<SwimReadinessGateIdentifier>()

        switch treatment.targetParameter {
        case "freeChlorine":
            if test.freeChlorine < chemistryEngine.freeChlorineSwimReadinessMinimum(cyanuricAcid: test.cyanuricAcid) {
                identifiers.insert(.sanitizerAdequacy)
            }
            if test.combinedChlorine > 0.5 {
                identifiers.insert(.combinedChlorine)
            }
        case "pH":
            if !(7.2...7.8).contains(test.pH) {
                identifiers.insert(.pH)
            }
        default:
            break
        }

        return identifiers
    }

    private func readyAt(for treatment: Treatment, waitMinutes: Int?) -> Date? {
        guard let waitMinutes, let completedAt = treatment.completedAt else { return nil }
        return completedAt.addingTimeInterval(TimeInterval(waitMinutes * 60))
    }

    private func isRecoveryChlorine(_ treatment: Treatment) -> Bool {
        guard treatment.targetParameter == "freeChlorine" else { return false }
        if treatment.urgency == .immediate { return true }
        if treatment.wasDoseCapped { return true }

        let text = [treatment.chemicalName, treatment.actionDescription, treatment.instructions]
            .joined(separator: " ")
            .lowercased()
        return text.contains("recovery")
            || text.contains("algae")
            || text.contains("cloudy")
            || text.contains("combined chlorine")
            || text.contains("cc")
    }

    private func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func reason(
        for treatment: Treatment,
        category: V2TreatmentClassificationCategory,
        completionState: V2TreatmentCompletionState,
        verificationRequired: Bool
    ) -> String {
        switch completionState {
        case .noActiveTreatment:
            return "\(treatment.chemicalName) has no active v2 swim-readiness hold."
        case .plannedTreatment:
            return "\(treatment.chemicalName) is planned and classified as \(category.rawValue)."
        case .completedWaiting:
            return "\(treatment.chemicalName) is complete and its circulation/re-entry wait is still active."
        case .completedVerificationRequired:
            return "\(treatment.chemicalName) is complete but verification is required before swimming."
        case .skippedTreatment:
            return "\(treatment.chemicalName) was skipped; underlying observed gates determine whether readiness remains blocked."
        case .unresolvedRecoveryAction:
            return "\(treatment.chemicalName) is a non-chemical recovery action; observed clarity/algae gates determine readiness."
        }
    }

}
