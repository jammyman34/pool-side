import Foundation

/// Rule-based fallback AI service — no device AI required.
/// Produces deterministic, chemistry-accurate treatment plans from the ChemistryEngine.
final class RuleBasedService: AIService, @unchecked Sendable {

    var isAvailable: Bool { true }

    private let engine = ChemistryEngine()

    func generateRecommendations(for request: AIRecommendationRequest) async throws -> AIRecommendationResponse {
        let treatments = engine.ruleTreatments(for: request.currentTest, config: request.poolConfig)
        let assessment = buildAssessment(for: request, treatments: treatments)
        return AIRecommendationResponse(treatments: treatments, assessmentText: assessment)
    }

    // MARK: - Assessment Builder

    private func buildAssessment(for request: AIRecommendationRequest, treatments: [TreatmentTemplate]) -> String {
        let test = request.currentTest
        let readings = engine.allReadings(for: test, config: request.poolConfig)

        let criticals = readings.filter { $0.status == .critical }
        let outOfRange = readings.filter { $0.status != .ideal && $0.status != .testing }

        if criticals.isEmpty && outOfRange.isEmpty {
            return "Pool chemistry is well balanced. All parameters are within ideal ranges — no treatments needed. Keep up the great work! 🌊"
        }

        var parts: [String] = []

        if !criticals.isEmpty {
            let names = criticals.map { $0.parameter }.joined(separator: " and ")
            parts.append("⚠️ \(names) \(criticals.count == 1 ? "is" : "are") at critical levels requiring immediate attention.")
        }

        if !outOfRange.isEmpty {
            let count = outOfRange.count
            parts.append("\(count) parameter\(count == 1 ? "" : "s") \(count == 1 ? "is" : "are") outside ideal range.")
        }

        // Check for history trends
        let recentTests = request.recentHistory.prefix(3)
        if recentTests.count >= 2 {
            let prevpH = recentTests.dropFirst().first?.pH
            if let prev = prevpH, abs(test.pH - prev) > 0.3 {
                let direction = test.pH > prev ? "risen" : "dropped"
                parts.append("pH has \(direction) significantly since your last test.")
            }
        }

        parts.append("\(treatments.count) treatment\(treatments.count == 1 ? "" : "s") recommended.")

        return parts.joined(separator: " ")
    }
}
