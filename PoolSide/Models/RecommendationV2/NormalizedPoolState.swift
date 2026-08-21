import Foundation

enum NormalizedWaterClarity: String, Codable, Equatable, Sendable {
    case clear
    case cloudy
    case cannotTell
    case notRecorded
    case unknown
}

enum NormalizedVisibleAlgae: String, Codable, Equatable, Sendable {
    case present
    case absent
    case cannotTell
    case notRecorded
    case unknown
}

enum NormalizedTestMethodConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
    case unknown
}

enum NormalizedCirculationStatus: String, Codable, Equatable, Sendable {
    case running
    case stopped
    case unknown
    case notRecorded
}

enum NormalizedReportedState: String, Codable, Equatable, Sendable {
    case reportedPresent
    case reportedAbsent
    case unknown
    case notRecorded
}

struct NormalizedPoolState: Codable, Equatable, Sendable {
    let currentTestID: UUID
    let testDate: Date
    let ageInMinutes: Int
    let evaluationDate: Date

    let poolVolumeGallons: Double
    let surfaceType: SurfaceType
    let saltSystemEnabled: Bool
    let configuredTestMethod: TestMethod

    let freeChlorine: Double?
    let totalChlorine: Double?
    let combinedChlorine: Double?
    let pH: Double?
    let totalAlkalinity: Double?
    let calciumHardness: Double?
    let cyanuricAcid: Double?
    let saltLevel: Double?
    let waterTemperature: Double?

    let unavailableReadingIdentifiers: [String]
    let internallyConflictingReadingIdentifiers: [String]

    let actualTestMethod: TestMethod
    let testMethodConfidence: NormalizedTestMethodConfidence

    let normalizedWaterClarity: NormalizedWaterClarity
    let normalizedVisibleAlgae: NormalizedVisibleAlgae
    let odorReported: NormalizedReportedState
    let foamReported: NormalizedReportedState
    let visualConditionsComplete: Bool

    let recentRain: NormalizedReportedState
    let recentRefill: NormalizedReportedState
    let recentBackwash: NormalizedReportedState
    let recentHeavyBatherLoad: NormalizedReportedState
    let recentContaminationConcern: NormalizedReportedState

    let activeTreatmentCount: Int
    let completedTreatmentCount: Int
    let skippedTreatmentCount: Int
    let mostRecentTreatmentCompletionDate: Date?
    let circulationStatus: NormalizedCirculationStatus
    let knownPumpRunningSince: Date?

    let recentTestCount: Int
    let latestPreviousTestDate: Date?
    let hasConflictingRecentTest: Bool
    let hasRecentTreatmentHistory: Bool
}
