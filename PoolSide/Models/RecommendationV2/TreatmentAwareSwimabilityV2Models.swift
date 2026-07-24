import Foundation

enum V2TreatmentClassificationCategory: String, Codable, Equatable, Sendable {
    case swimBlocking
    case poolCare
    case both
    case nonChemicalAction
}

enum V2TreatmentCompletionState: String, Codable, Equatable, Sendable {
    case noActiveTreatment
    case plannedTreatment
    case completedWaiting
    case completedVerificationRequired
    case skippedTreatment
    case unresolvedRecoveryAction
}

struct V2TreatmentClassification: Codable, Equatable, Sendable {
    let treatmentID: UUID
    let treatmentName: String
    let targetParameter: String
    let category: V2TreatmentClassificationCategory
    let completionState: V2TreatmentCompletionState
    let blocksCurrentSwimability: Bool
    let startsWaitOnCompletion: Bool
    let verificationRequiredBeforeSwimming: Bool
    let pendingVerificationGateIdentifiers: Set<SwimReadinessGateIdentifier>
    let waitMinutes: Int?
    let completedAt: Date?
    let readyAt: Date?
    let reason: String
}

struct V2TreatmentAwareContext: Codable, Equatable, Sendable {
    let classifications: [V2TreatmentClassification]
    let activeTreatmentCount: Int
    let verificationRequired: Bool
    let earliestPredictedReadyTime: Date?
    let activeWaitDescriptions: [String]
    let remainingBlockers: [String]

    var hasSwimBlockingActiveTreatment: Bool {
        classifications.contains { $0.blocksCurrentSwimability && $0.completionState == .plannedTreatment }
    }

    var hasActivePoolCareOnlyTreatment: Bool {
        classifications.contains { !$0.blocksCurrentSwimability && $0.completionState == .plannedTreatment }
    }

    var hasCompletedWaitingTreatment: Bool {
        classifications.contains { $0.completionState == .completedWaiting }
    }

    var hasCompletedVerificationRequiredTreatment: Bool {
        classifications.contains { $0.completionState == .completedVerificationRequired }
    }

    var pendingVerificationGateIdentifiers: Set<SwimReadinessGateIdentifier> {
        Set(classifications
            .filter { $0.completionState == .completedVerificationRequired }
            .flatMap(\.pendingVerificationGateIdentifiers))
    }

    var hasUnresolvedRecoveryAction: Bool {
        classifications.contains { $0.completionState == .unresolvedRecoveryAction }
    }

    var hasUnknownReentryRequirement: Bool {
        classifications.contains { classification in
            classification.blocksCurrentSwimability
                && classification.waitMinutes == nil
                && !classification.verificationRequiredBeforeSwimming
                && classification.category != .nonChemicalAction
        }
    }
}
