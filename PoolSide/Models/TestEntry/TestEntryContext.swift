import Foundation

struct TestEntryContext: Equatable {
    enum Kind: Equatable {
        case initialAssessment
        case maintenance
        case followUp
    }

    var kind: Kind
    var followUpReasons: [TestEntryFollowUpReason]

    static let initialAssessment = TestEntryContext(kind: .initialAssessment, followUpReasons: [])
    static let maintenance = TestEntryContext(kind: .maintenance, followUpReasons: [])

    static func followUp(_ reasons: [TestEntryFollowUpReason]) -> TestEntryContext {
        TestEntryContext(kind: .followUp, followUpReasons: reasons)
    }
}

enum TestEntryFollowUpReason: String, CaseIterable, Codable, Hashable, Identifiable {
    case previouslyReportedAlgae
    case previouslyCloudyWater
    case recentRecoveryTreatment
    case previousElevatedCombinedChlorineConcern
    case previousTreatmentRequiringFollowUp

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .previouslyReportedAlgae:
            return 0
        case .previouslyCloudyWater:
            return 1
        case .previousElevatedCombinedChlorineConcern:
            return 2
        case .recentRecoveryTreatment:
            return 3
        case .previousTreatmentRequiringFollowUp:
            return 4
        }
    }
}

enum VisualFollowUpResponse: String, Codable, CaseIterable, Identifiable, Equatable {
    case yes
    case mostly
    case no
    case cannotTell
    case notRecorded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yes: return "Yes"
        case .mostly: return "Mostly"
        case .no: return "No"
        case .cannotTell: return "Cannot tell"
        case .notRecorded: return "Not recorded"
        }
    }
}

struct MaintenanceVisualResponseMapper {
    enum Response: Equatable {
        case looksClearNormal
        case somethingLooksDifferent
        case cannotTell
    }

    static func mappedAssessments(for response: Response) -> (clarity: WaterClarityAssessment, algae: VisibleAlgaeAssessment, revealsDetailedObservations: Bool) {
        switch response {
        case .looksClearNormal:
            return (.clear, .absent, false)
        case .somethingLooksDifferent:
            return (.notRecorded, .notRecorded, true)
        case .cannotTell:
            return (.cannotTell, .cannotTell, false)
        }
    }
}

struct FollowUpVisualResponseMapper {
    static func algaeResponse(_ response: VisualFollowUpResponse) -> VisibleAlgaeAssessment {
        switch response {
        case .yes:
            return .absent
        case .mostly:
            return .present
        case .no:
            return .present
        case .cannotTell:
            return .cannotTell
        case .notRecorded:
            return .notRecorded
        }
    }

    static func cloudinessResponse(_ response: VisualFollowUpResponse) -> WaterClarityAssessment {
        switch response {
        case .yes:
            return .clear
        case .mostly:
            return .cloudy
        case .no:
            return .cloudy
        case .cannotTell:
            return .cannotTell
        case .notRecorded:
            return .notRecorded
        }
    }
}

struct TestEntryContextResolver {
    private enum Evidence {
        case present
        case resolved
        case unknown
        case none
    }

    func resolve(
        poolConfig: PoolConfiguration,
        recentHistory: [PoolTest]
    ) -> TestEntryContext {
        let orderedHistory = recentHistory.sorted { $0.date > $1.date }
        guard !orderedHistory.isEmpty else { return .initialAssessment }

        var reasons: [TestEntryFollowUpReason] = []
        if unresolvedAlgae(in: orderedHistory) {
            reasons.append(.previouslyReportedAlgae)
        }
        if unresolvedCloudiness(in: orderedHistory) {
            reasons.append(.previouslyCloudyWater)
        }
        if hasRecentElevatedCombinedChlorineConcern(in: orderedHistory) {
            reasons.append(.previousElevatedCombinedChlorineConcern)
        }
        if hasRecentRecoveryTreatment(in: orderedHistory) {
            reasons.append(.recentRecoveryTreatment)
        }
        if hasPreviousTreatmentRequiringFollowUp(in: orderedHistory) {
            reasons.append(.previousTreatmentRequiringFollowUp)
        }

        let uniqueReasons = Array(Set(reasons)).sorted { $0.priority < $1.priority }
        return uniqueReasons.isEmpty ? .maintenance : .followUp(uniqueReasons)
    }

    private func unresolvedAlgae(in history: [PoolTest]) -> Bool {
        switch firstDecisiveEvidence(in: history, evidence: algaeEvidence) {
        case .present, .unknown:
            return historyContainsPresentEvidence(history, evidence: algaeEvidence)
        case .resolved, .none:
            return false
        }
    }

    private func unresolvedCloudiness(in history: [PoolTest]) -> Bool {
        switch firstDecisiveEvidence(in: history, evidence: cloudinessEvidence) {
        case .present, .unknown:
            return historyContainsPresentEvidence(history, evidence: cloudinessEvidence)
        case .resolved, .none:
            return false
        }
    }

    private func firstDecisiveEvidence(in history: [PoolTest], evidence: (PoolTest) -> Evidence) -> Evidence {
        history.map(evidence).first { $0 != .none } ?? .none
    }

    private func historyContainsPresentEvidence(_ history: [PoolTest], evidence: (PoolTest) -> Evidence) -> Bool {
        history.contains { evidence($0) == .present }
    }

    private func algaeEvidence(for test: PoolTest) -> Evidence {
        switch test.visibleAlgaeAssessment {
        case .present:
            return .present
        case .absent:
            return .resolved
        case .cannotTell:
            return .unknown
        case .notRecorded:
            let indicators = Set(test.visualIndicators)
            if indicators.contains(VisualIndicator.algaeSpots.rawValue) || indicators.contains(VisualIndicator.greenWater.rawValue) {
                return .present
            }
            return .none
        }
    }

    private func cloudinessEvidence(for test: PoolTest) -> Evidence {
        switch test.waterClarityAssessment {
        case .cloudy:
            return .present
        case .clear:
            return .resolved
        case .cannotTell:
            return .unknown
        case .notRecorded:
            let indicators = Set(test.visualIndicators)
            if indicators.contains(VisualIndicator.cloudyWater.rawValue) || indicators.contains(VisualIndicator.greenWater.rawValue) {
                return .present
            }
            if indicators.contains(VisualIndicator.crystalClear.rawValue) {
                return .resolved
            }
            return .none
        }
    }

    private func hasRecentElevatedCombinedChlorineConcern(in history: [PoolTest]) -> Bool {
        guard let latest = history.first else { return false }
        if algaeEvidence(for: latest) == .resolved && cloudinessEvidence(for: latest) == .resolved && latest.combinedChlorine <= 0.5 {
            return false
        }
        return latest.combinedChlorine > 0.5
    }

    private func hasRecentRecoveryTreatment(in history: [PoolTest]) -> Bool {
        history.prefix(3).flatMap(\.treatments).contains { treatment in
            treatment.urgency == .immediate && !treatment.isSkipped
        }
    }

    private func hasPreviousTreatmentRequiringFollowUp(in history: [PoolTest]) -> Bool {
        history.prefix(3).flatMap(\.treatments).contains { treatment in
            !treatment.isSkipped && treatment.doNotRepeatBefore != nil
        }
    }
}
