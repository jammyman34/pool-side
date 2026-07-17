import Foundation

// MARK: - Protocol

protocol AIService: Sendable {
    var isAvailable: Bool { get }
    func generateRecommendations(for request: AIRecommendationRequest) async throws -> AIRecommendationResponse
}

// MARK: - Request

struct AIRecommendationRequest: @unchecked Sendable {
    let currentTest: PoolTest
    let recentHistory: [PoolTest]   // Up to 14 most recent tests, newest first
    let poolConfig: PoolConfiguration

    /// Formats context for the AI prompt
    func contextString() -> String {
        var parts: [String] = []

        var poolLine = "POOL: \(poolConfig.name), \(Int(poolConfig.volumeGallons)) gallons, \(poolConfig.poolType.displayName), \(poolConfig.surfaceType.displayName) surface, testing with \(poolConfig.testMethod.displayName)\(poolConfig.isSaltwater ? ", saltwater system" : "")"
        if poolConfig.hasCover {
            poolLine += ", has a pool cover"
        }
        if !poolConfig.location.isEmpty {
            poolLine += ", location: \(poolConfig.location)"
        }
        parts.append(poolLine)
        parts.append("PREFERENCES: chlorine \(poolConfig.chlorinePreference.displayName); pH increaser \(poolConfig.pHIncreaserPreference.displayName); pH decreaser \(poolConfig.pHDecreaserPreference.displayName); alkalinity increaser \(poolConfig.alkalinityIncreaserPreference.displayName); calcium increaser \(poolConfig.calciumIncreaserPreference.displayName); stabilizer \(poolConfig.stabilizerPreference.displayName)")

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none

        parts.append("\nCURRENT TEST (\(df.string(from: currentTest.date))):")
        parts.append("  pH: \(String(format: "%.1f", currentTest.pH))")
        parts.append("  Free Chlorine: \(String(format: "%.1f", currentTest.freeChlorine)) ppm")
        parts.append("  Total Chlorine: \(String(format: "%.1f", currentTest.totalChlorine)) ppm")
        parts.append("  Total Alkalinity: \(String(format: "%.0f", currentTest.totalAlkalinity)) ppm")
        parts.append("  Calcium Hardness: \(String(format: "%.0f", currentTest.calciumHardness)) ppm")
        parts.append("  Cyanuric Acid: \(String(format: "%.0f", currentTest.cyanuricAcid)) ppm")
        if let temp = currentTest.temperatureFahrenheit {
            parts.append("  Water Temp: \(String(format: "%.0f", temp))°F")
        }
        if let salt = currentTest.saltLevel {
            parts.append("  Salt: \(String(format: "%.0f", salt)) ppm")
        }
        if !currentTest.notes.isEmpty {
            parts.append("  Notes: \(currentTest.notes)")
        }
        let conditions = currentTest.resolvedPoolConditions
        if conditions.hasAnyKnownCondition {
            parts.append("  Pool Conditions Since Last Test:")
            parts.append("    Chlorine demand score: \(conditions.chlorineDemandContribution)")
            parts.append("    Water change score: \(conditions.waterChangeContribution)")
            parts.append("    Swimming: \(conditions.swimmingLoad.rawValue)")
            parts.append("    Pet swimming: \(conditions.petSwimmingLoad.rawValue)")
            parts.append("    Rain: \(conditions.rainLoad.rawValue)")
            parts.append("    Cover open time: \(conditions.coverOpenTime.rawValue)")
            parts.append("    Organic debris: \(conditions.organicDebrisLoad.rawValue)")
            parts.append("    Skimmed debris: \(conditions.skimmedDebris.rawValue)")
            parts.append("    Backwashed filter: \(conditions.backwashedFilter.rawValue)")
            parts.append("    Water added: \(conditions.waterAdded.rawValue)")
            parts.append("    Cleaning: \(conditions.cleaningActivity.rawValue)")
            parts.append("    Pool brushed: \(conditions.poolBrushed.rawValue)")
        }
        let indicators = currentTest.visualIndicators.compactMap(VisualIndicator.init(rawValue:))
        let positives = indicators.filter { $0.isPositive }
        let issues = indicators.filter { !$0.isPositive }
        if !positives.isEmpty {
            parts.append("  Positive Signs: \(positives.map(\.rawValue).joined(separator: ", "))")
        }
        if !issues.isEmpty {
            parts.append("  Issues Noted: \(issues.map(\.rawValue).joined(separator: ", "))")
        }

        let historyToShow = recentHistory.prefix(7)
        if !historyToShow.isEmpty {
            parts.append("\nRECENT HISTORY (newest first):")
            for test in historyToShow {
                parts.append("  \(df.string(from: test.date)): pH \(String(format: "%.1f", test.pH)), Cl \(String(format: "%.1f", test.freeChlorine)) ppm, Alk \(String(format: "%.0f", test.totalAlkalinity)) ppm")
                let completedForTest = test.treatments.filter { $0.isCompleted }
                if !completedForTest.isEmpty {
                    let names = completedForTest.map { treatment in
                        let completedDate = treatment.completedAt.map { df.string(from: $0) } ?? "date unknown"
                        return "\(treatment.chemicalName) \(treatment.amount.formatted()) \(treatment.unit), completed \(completedDate)"
                    }.joined(separator: "; ")
                    parts.append("    Treatments completed: \(names)")
                }
            }
        }

        return parts.joined(separator: "\n")
    }
}

// MARK: - Response

struct AIRecommendationResponse {
    var treatments: [TreatmentTemplate]
    var assessmentText: String
}
