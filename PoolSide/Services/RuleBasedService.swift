import Foundation

/// Rule-based fallback AI service — no device AI required.
/// Produces deterministic, chemistry-accurate treatment plans from the ChemistryEngine.
final class RuleBasedService: AIService, @unchecked Sendable {

    var isAvailable: Bool { true }

    private let engine = ChemistryEngine()

    func generateRecommendations(for request: AIRecommendationRequest) async throws -> AIRecommendationResponse {
        var treatments = engine.validatedTreatments(
            for: request.currentTest,
            config: request.poolConfig,
            recentHistory: request.recentHistory
        )
        treatments.append(contentsOf: visualIndicatorTreatments(for: request.currentTest))
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
            var balanced = "Pool chemistry is well balanced. All parameters are within ideal ranges — no treatments needed."
            if let testingNote = request.poolConfig.testMethod.confidenceNote {
                balanced += " \(testingNote)"
            }
            return balanced
        }

        var parts: [String] = []
        if let testingNote = request.poolConfig.testMethod.confidenceNote {
            parts.append(testingNote)
        }

        if request.poolConfig.testMethod.shouldSuppressOptionalTreatments {
            let optionalReadings = readings.filter { $0.status == .slightlyLow || $0.status == .slightlyHigh }
            if !optionalReadings.isEmpty {
                let names = optionalReadings.map { $0.parameter }.joined(separator: ", ")
                parts.append("Because these readings came from test strips, borderline values for \(names) should be confirmed before adding optional chemicals.")
            }
        }

        if !criticals.isEmpty {
            let names = criticals.map { $0.parameter }.joined(separator: " and ")
            parts.append("⚠️ \(names) \(criticals.count == 1 ? "is" : "are") at critical levels requiring immediate attention.")
        }

        if !outOfRange.isEmpty {
            let count = outOfRange.count
            parts.append("\(count) parameter\(count == 1 ? "" : "s") \(count == 1 ? "is" : "are") outside ideal range.")
        }

        let indicators = test.visualIndicators.compactMap(VisualIndicator.init(rawValue:))
        let positives = indicators.filter { $0.isPositive }
        let issues = indicators.filter { !$0.isPositive }
        if !positives.isEmpty {
            parts.append("Positive signs observed: \(positives.map(\.rawValue).joined(separator: ", ")).")
        }
        if !issues.isEmpty {
            parts.append("Issues noted: \(issues.map(\.rawValue).joined(separator: ", ")).")
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

    private func visualIndicatorTreatments(for test: PoolTest) -> [TreatmentTemplate] {
        var treatments: [TreatmentTemplate] = []
        let indicators = Set(test.visualIndicators)
        let hasCrystalClear = indicators.contains(VisualIndicator.crystalClear.rawValue)

        // Algae/green water still triggers a shock even if the user marked Crystal Clear too —
        // visible algae is hard to misobserve and the chemistry impact is severe.
        if indicators.contains(VisualIndicator.greenWater.rawValue) || indicators.contains(VisualIndicator.algaeSpots.rawValue) {
            treatments.append(TreatmentTemplate(
                chemicalName: "Chlorine Shock",
                actionDescription: "Shock pool to address visible algae",
                amount: 1,
                unit: "dose per label",
                instructions: "Brush affected surfaces, run the pump continuously, and add chlorine shock according to the product label for your pool volume. Retest chlorine and pH after circulation clears.",
                targetParameter: "visualIndicators",
                urgency: .immediate,
                minutesBeforeNext: 480,
                sortOrder: 900
            ))
        }

        // Clarifier only when cloudy and NOT contradicted by Crystal Clear.
        if indicators.contains(VisualIndicator.cloudyWater.rawValue) && !hasCrystalClear {
            treatments.append(TreatmentTemplate(
                chemicalName: "Clarifier",
                actionDescription: "Improve water clarity",
                amount: 1,
                unit: "dose per label",
                instructions: "Clean or backwash the filter, run circulation, and add clarifier according to the label. Avoid adding more clarifier than directed.",
                targetParameter: "visualIndicators",
                urgency: .recommended,
                minutesBeforeNext: 0,
                sortOrder: 901
            ))
        }

        return treatments
    }
}
