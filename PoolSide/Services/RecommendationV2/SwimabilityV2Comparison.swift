import Foundation

struct SwimabilityV2Comparison: Equatable, Sendable {
    let existingStatus: String
    let existingScore: Int
    let v2Assessment: SwimabilityV2Assessment
    let meaningfulDifferences: [String]
    let generatedAt: Date

    var developerDescription: String {
        let failed = formattedGateList(v2Assessment.failedGates)
        let unknown = formattedGateList(v2Assessment.unknownGates)
        let differences = meaningfulDifferences.isEmpty ? "None" : meaningfulDifferences.joined(separator: "; ")

        return [
            "Pool Side Swimability v2 comparison",
            "Current status: \(existingStatus)",
            "Current score: \(existingScore)",
            "V2 state: \(v2Assessment.state.rawValue)",
            "V2 evidence type: \(v2Assessment.evidenceType.rawValue)",
            "V2 confidence: \(v2Assessment.confidence.rawValue)",
            "Failed gates: \(failed)",
            "Unknown gates: \(unknown)",
            "Testing required: \(v2Assessment.testingRequired ? "yes" : "no")",
            "Differences: \(differences)"
        ].joined(separator: "\n")
    }

    private func formattedGateList(_ gates: [SwimReadinessGateResult]) -> String {
        guard !gates.isEmpty else { return "None" }
        return gates.map { $0.identifier.rawValue }.joined(separator: ", ")
    }
}
