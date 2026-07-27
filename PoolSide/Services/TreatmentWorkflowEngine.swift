import Foundation

struct TreatmentWorkflowEngine {
    enum StepState: Equatable {
        case current
        case waiting(availableAt: Date)
        case upcoming
        case completed
        case skipped
    }

    struct FocusedCheckDescriptor: Equatable {
        let parameters: [String]
        let title: String
        let timingText: String
        let body: String
        let delayMinutes: Int
        let optional: Bool
    }

    private let nextTestEngine = NextTestRecommendationEngine()

    func workflowSteps(from treatments: [Treatment]) -> [Treatment] {
        treatments
            .filter { !$0.isWatchlistItem }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder { return lhs.createdAt < rhs.createdAt }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func checkDescriptor(for treatment: Treatment) -> FocusedCheckDescriptor? {
        guard !treatment.isWatchlistItem, !treatment.isFocusedCheckStep else { return nil }

        if treatment.targetParameter == "freeChlorine" {
            let optional = treatment.urgency == .optional
            return FocusedCheckDescriptor(
                parameters: ["freeChlorine", "combinedChlorine"],
                title: "Check FC & CC",
                timingText: "\(waitText(minutes: chlorineDelayMinutes(for: treatment))) after adding chlorine",
                body: optional
                    ? "Optional: test FC and CC after circulation if you want to confirm the chlorine top-off."
                    : "Test FC and CC to confirm chlorine is safe before swimming.",
                delayMinutes: chlorineDelayMinutes(for: treatment),
                optional: optional
            )
        }

        if treatment.targetParameter == "pH", treatment.effectDelayHours >= 4 {
            return FocusedCheckDescriptor(
                parameters: ["pH"],
                title: "Check pH",
                timingText: "4 hours after adding \(shortChemicalName(treatment.chemicalName))",
                body: "Test pH to confirm it is back in the safe range.",
                delayMinutes: 240,
                optional: false
            )
        }

        if treatment.targetParameter == "totalAlkalinity", !treatment.isAcidTreatment, treatment.effectDelayHours > 0 {
            return FocusedCheckDescriptor(
                parameters: ["totalAlkalinity"],
                title: "Check TA",
                timingText: "6-8 hours after adding alkalinity increaser",
                body: "Test TA before making another alkalinity adjustment.",
                delayMinutes: treatment.effectDelayHours * 60,
                optional: false
            )
        }

        if treatment.targetParameter == "cyanuricAcid" {
            return FocusedCheckDescriptor(
                parameters: ["cyanuricAcid"],
                title: "Check CYA",
                timingText: "24-48 hours after adding stabilizer",
                body: "Test CYA after circulation before adding more stabilizer.",
                delayMinutes: TreatmentApplicationPolicy.granularCYACanonicalRetestHours * 60,
                optional: false
            )
        }

        if treatment.targetParameter == "calciumHardness", treatment.effectDelayHours > 0 {
            return FocusedCheckDescriptor(
                parameters: ["calciumHardness"],
                title: "Check CH",
                timingText: "About 24 hours after adding calcium",
                body: "Test calcium hardness before adding more calcium increaser.",
                delayMinutes: treatment.effectDelayHours * 60,
                optional: false
            )
        }

        return nextTestEngine.treatmentRetestRecommendation(for: treatment, completedAt: treatment.createdAt).map { recommendation in
            FocusedCheckDescriptor(
                parameters: parameters(for: treatment.targetParameter),
                title: recommendation.title.replacingOccurrences(of: "Retest", with: "Check"),
                timingText: recommendation.relativeLabel,
                body: recommendation.body,
                delayMinutes: Int(recommendation.interval / 60),
                optional: false
            )
        }
    }

    func makeCheckStep(after treatment: Treatment, sortOrder: Int) -> Treatment? {
        guard let descriptor = checkDescriptor(for: treatment) else { return nil }
        let check = Treatment(
            chemicalName: descriptor.title,
            actionDescription: descriptor.timingText,
            amount: 0,
            unit: "",
            instructions: descriptor.body,
            urgency: descriptor.optional ? .optional : .recommended,
            isAIGenerated: true,
            targetParameter: descriptor.parameters.first ?? treatment.targetParameter,
            minutesBeforeNext: 0,
            sortOrder: sortOrder,
            expectedEffectParameter: descriptor.parameters.joined(separator: ","),
            effectDelayHours: max(1, descriptor.delayMinutes / 60),
            poolTest: treatment.poolTest
        )
        check.workflowStepKind = .focusedCheck
        check.checkParameters = descriptor.parameters
        check.parentTreatmentID = treatment.id
        return check
    }

    func state(for step: Treatment, in steps: [Treatment], evaluationDate: Date = Date()) -> StepState {
        if step.isCompleted { return .completed }
        if step.isSkipped { return .skipped }
        if step.isFocusedCheckStep, let availableAt = availableDate(for: step, in: steps) {
            if evaluationDate < availableAt { return .waiting(availableAt: availableAt) }
        }

        for candidate in steps.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if candidate.id == step.id { return .current }
            if !candidate.isCompleted && !candidate.isSkipped {
                if candidate.isFocusedCheckStep, let availableAt = availableDate(for: candidate, in: steps), evaluationDate >= availableAt {
                    return .upcoming
                }
                if !candidate.isFocusedCheckStep {
                    return .upcoming
                }
            }
        }
        return .upcoming
    }

    func availableDate(for checkStep: Treatment, in steps: [Treatment]) -> Date? {
        guard checkStep.isFocusedCheckStep, let parentID = checkStep.parentTreatmentID else { return nil }
        guard let parent = steps.first(where: { $0.id == parentID }), let completedAt = parent.completedAt else { return nil }
        let minutes = checkDelayMinutes(for: checkStep, parent: parent)
        return completedAt.addingTimeInterval(TimeInterval(minutes * 60))
    }

    func checkDelayMinutes(for checkStep: Treatment, parent: Treatment) -> Int {
        if parent.targetParameter == "freeChlorine" { return chlorineDelayMinutes(for: parent) }
        if parent.targetParameter == "pH" { return 240 }
        if parent.targetParameter == "cyanuricAcid" { return TreatmentApplicationPolicy.granularCYACanonicalRetestHours * 60 }
        if parent.targetParameter == "totalAlkalinity" { return max(60, parent.effectDelayHours * 60) }
        if parent.targetParameter == "calciumHardness" { return max(60, parent.effectDelayHours * 60) }
        return max(0, parent.effectDelayHours * 60)
    }

    private func parameters(for targetParameter: String) -> [String] {
        switch targetParameter {
        case "freeChlorine": return ["freeChlorine", "combinedChlorine"]
        case "pH": return ["pH"]
        case "totalAlkalinity": return ["totalAlkalinity"]
        case "cyanuricAcid": return ["cyanuricAcid"]
        case "calciumHardness": return ["calciumHardness"]
        default: return [targetParameter]
        }
    }

    private func chlorineDelayMinutes(for treatment: Treatment) -> Int {
        if treatment.chemicalName.localizedCaseInsensitiveContains("tablet") { return 24 * 60 }
        if treatment.chemicalName.localizedCaseInsensitiveContains("granule")
            || treatment.chemicalName.localizedCaseInsensitiveContains("dichlor") { return 240 }
        return 60
    }

    private func waitText(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    private func shortChemicalName(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("muriatic") { return "acid" }
        if name.localizedCaseInsensitiveContains("dry acid") { return "dry acid" }
        return name
    }
}
