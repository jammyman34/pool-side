import Foundation

enum SwimabilityEvidenceType: String, Codable, Equatable, Sendable {
    case observed
    case predicted
    case confirmed
    case unknown
}

enum SwimabilityState: String, Codable, Equatable, Sendable {
    case readyToSwim
    case expectedReadyAfterTreatment
    case expectedReadyAroundTime
    case testBeforeSwimming
    case doNotSwim
    case moreInformationNeeded
}

enum SwimabilityConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case insufficient
}

enum SwimReadinessGateState: String, Codable, Equatable, Sendable {
    case pass
    case fail
    case unknown
    case notApplicable
}

enum SwimReadinessGateIdentifier: String, Codable, Equatable, Sendable {
    case sanitizerAdequacy
    case pH
    case combinedChlorine
    case waterClarity
    case visibleAlgae
    case testFreshness
    case treatmentCompletion
    case circulation
    case productReentry
}

struct SwimReadinessGateResult: Codable, Equatable, Sendable {
    let identifier: SwimReadinessGateIdentifier
    let state: SwimReadinessGateState
    let reason: String
    let blocksSwimming: Bool
    let requiresTesting: Bool
}

struct SwimabilityV2Assessment: Codable, Equatable, Sendable {
    let state: SwimabilityState
    let evidenceType: SwimabilityEvidenceType
    let confidence: SwimabilityConfidence
    let gateResults: [SwimReadinessGateResult]
    let invalidationReasons: [String]
    let testingRequired: Bool
    let summary: String

    var failedGates: [SwimReadinessGateResult] {
        gateResults.filter { $0.state == .fail }
    }

    var unknownGates: [SwimReadinessGateResult] {
        gateResults.filter { $0.state == .unknown }
    }

    var swimmingBlocked: Bool {
        gateResults.contains { $0.blocksSwimming } || state == .doNotSwim || state == .testBeforeSwimming || state == .moreInformationNeeded
    }
}
