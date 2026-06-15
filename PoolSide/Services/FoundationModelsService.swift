import Foundation
import FoundationModels

// MARK: - Foundation Models Service (iOS 26.0+, Apple Intelligence devices)

@available(iOS 26.0, *)
final class FoundationModelsService: AIService, @unchecked Sendable {

    var isAvailable: Bool {
        // FoundationModels requires Apple Intelligence — A17 Pro / M-series chips
        SystemLanguageModel.default.isAvailable
    }

    func generateRecommendations(for request: AIRecommendationRequest) async throws -> AIRecommendationResponse {
        guard isAvailable else {
            throw AIServiceError.notAvailable
        }

        let engine = ChemistryEngine()
        let treatments = engine.validatedTreatments(
            for: request.currentTest,
            config: request.poolConfig,
            recentHistory: request.recentHistory
        )
        let session = LanguageModelSession()
        let prompt = buildAssessmentPrompt(from: request, treatments: treatments)

        let response = try await session.respond(to: prompt)
        return AIRecommendationResponse(
            treatments: treatments,
            assessmentText: response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Prompt

    private func buildPrompt(from request: AIRecommendationRequest) -> String {
        """
        You are an expert pool chemistry advisor. Analyze the following pool test data and provide precise treatment recommendations.

        \(request.contextString())

        IDEAL RANGES:
        - pH: 7.2 – 7.6
        - Free Chlorine: 1 – 3 ppm
        - Total Alkalinity: 80 – 120 ppm
        - Calcium Hardness: 200 – 400 ppm (plaster), 150 – 250 ppm (vinyl/fiberglass)
        - Cyanuric Acid: 30 – 50 ppm (outdoor), 0 ppm (indoor)
        - Salt (if saltwater): 2700 – 3400 ppm

        Respond ONLY in this exact format — no extra text:

        ASSESSMENT: [2-3 sentence summary of pool condition and any notable trends]

        TREATMENTS:
        [For each needed treatment, use this format]
        CHEMICAL: [chemical name]
        ACTION: [brief description]
        AMOUNT: [number] [unit]
        URGENCY: [immediate|recommended|optional]
        PARAMETER: [pH|freeChlorine|totalAlkalinity|calciumHardness|cyanuricAcid|saltLevel]
        INSTRUCTIONS: [step-by-step instructions in 1-3 sentences]
        ---

        If the pool is in ideal condition, respond:
        ASSESSMENT: Pool chemistry is balanced and in excellent condition. No treatments are needed at this time.
        TREATMENTS:
        NONE
        """
    }

    private func buildAssessmentPrompt(from request: AIRecommendationRequest, treatments: [TreatmentTemplate]) -> String {
        let treatmentSummary: String
        if treatments.isEmpty {
            treatmentSummary = "No treatment steps were recommended by the deterministic chemistry engine."
        } else {
            treatmentSummary = treatments
                .map { "- \($0.chemicalName): \($0.amount.formatted()) \($0.unit) for \($0.targetParameter)" }
                .joined(separator: "\n")
        }

        return """
        You are helping explain a pool treatment plan. Do not add, remove, or change treatment steps or doses.
        The app's deterministic chemistry engine has already calculated and validated the plan.

        \(request.contextString())

        VALIDATED PLAN:
        \(treatmentSummary)

        Write a concise 2-3 sentence assessment for the user. Mention relevant context such as recent completed treatments, pool cover, or location only if it is present in the data. Do not invent additional chemicals, amounts, or timing.
        """
    }

    // MARK: - Parser

    private func parseResponse(_ text: String, request: AIRecommendationRequest) -> AIRecommendationResponse {
        var assessmentText = "Assessment complete."
        var treatments: [TreatmentTemplate] = []

        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        // Extract assessment
        if let assessmentLine = lines.first(where: { $0.hasPrefix("ASSESSMENT:") }) {
            assessmentText = String(assessmentLine.dropFirst("ASSESSMENT:".count)).trimmingCharacters(in: .whitespaces)
        }

        // Parse treatments
        if !text.contains("TREATMENTS:\nNONE") && !text.contains("TREATMENTS:\r\nNONE") {
            let treatmentBlocks = text.components(separatedBy: "---")
            for block in treatmentBlocks {
                if let treatment = parseTreatmentBlock(block) {
                    treatments.append(treatment)
                }
            }
        }

        // Fallback: if AI returned nothing parseable, use rule engine
        if treatments.isEmpty && text.contains("TREATMENTS:") && !text.contains("NONE") {
            let engine = ChemistryEngine()
            treatments = engine.ruleTreatments(for: request.currentTest, config: request.poolConfig)
        }

        return AIRecommendationResponse(treatments: treatments, assessmentText: assessmentText)
    }

    private func parseTreatmentBlock(_ block: String) -> TreatmentTemplate? {
        let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        func value(for prefix: String) -> String? {
            lines.first(where: { $0.hasPrefix(prefix) }).map {
                String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard
            let chemical = value(for: "CHEMICAL:"),
            let action = value(for: "ACTION:"),
            let amountStr = value(for: "AMOUNT:"),
            let instructions = value(for: "INSTRUCTIONS:"),
            !chemical.isEmpty
        else { return nil }

        // Parse amount + unit
        let amountParts = amountStr.components(separatedBy: " ")
        let amount = Double(amountParts.first ?? "0") ?? 0
        let unit = amountParts.dropFirst().joined(separator: " ")

        let urgencyStr = value(for: "URGENCY:") ?? "recommended"
        let urgency = TreatmentUrgency(rawValue: urgencyStr) ?? .recommended

        let parameter = value(for: "PARAMETER:") ?? ""

        return TreatmentTemplate(
            chemicalName: chemical,
            actionDescription: action,
            amount: amount,
            unit: unit,
            instructions: instructions,
            targetParameter: parameter,
            urgency: urgency
        )
    }
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case notAvailable
    case parseFailure
    case modelError(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:      return "On-device AI requires an Apple Intelligence-capable device (iPhone 15 Pro or newer)."
        case .parseFailure:      return "Could not parse AI response. Using rule-based recommendations instead."
        case .modelError(let m): return "AI model error: \(m)"
        }
    }
}
