import Foundation

// MARK: - Protocol

protocol AIService: Sendable {
    var isAvailable: Bool { get }
    func generateRecommendations(for request: AIRecommendationRequest) async throws -> AIRecommendationResponse
}

// MARK: - Request

struct AIRecommendationRequest {
    let currentTest: PoolTest
    let recentHistory: [PoolTest]   // Up to 14 most recent tests, newest first
    let poolConfig: PoolConfiguration

    /// Formats context for the AI prompt
    func contextString() -> String {
        var parts: [String] = []

        parts.append("POOL: \(poolConfig.name), \(Int(poolConfig.volumeGallons)) gallons, \(poolConfig.poolType.displayName), \(poolConfig.surfaceType.displayName) surface\(poolConfig.isSaltwater ? ", saltwater system" : "")")

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

        let historyToShow = recentHistory.prefix(7)
        if !historyToShow.isEmpty {
            parts.append("\nRECENT HISTORY (newest first):")
            for test in historyToShow {
                parts.append("  \(df.string(from: test.date)): pH \(String(format: "%.1f", test.pH)), Cl \(String(format: "%.1f", test.freeChlorine)) ppm, Alk \(String(format: "%.0f", test.totalAlkalinity)) ppm")
                let completedForTest = test.treatments.filter { $0.isCompleted }
                if !completedForTest.isEmpty {
                    let names = completedForTest.map { $0.chemicalName }.joined(separator: ", ")
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
