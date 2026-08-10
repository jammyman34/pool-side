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
        treatments.append(contentsOf: visualIndicatorTreatments(
            for: request.currentTest,
            config: request.poolConfig,
            existingTreatments: &treatments
        ))
        let assessment = buildAssessment(for: request, treatments: treatments)
        return AIRecommendationResponse(treatments: treatments, assessmentText: assessment)
    }

    // MARK: - Assessment Builder

    private func buildAssessment(for request: AIRecommendationRequest, treatments: [TreatmentTemplate]) -> String {
        let test = request.currentTest
        let readings = engine.allReadings(for: test, config: request.poolConfig)

        let criticals = readings.filter { $0.status == .critical }
        let actionTreatments = treatments.filter { $0.urgency.isActionable }
        let optionalTreatments = treatments.filter { $0.urgency == .optional }
        let advisoryTreatments = treatments.filter { $0.urgency == .advisory }

        if criticals.isEmpty && actionTreatments.isEmpty && optionalTreatments.isEmpty {
            var balanced = "Pool chemistry is well balanced. All parameters are within ideal ranges — no treatments needed."
            if !advisoryTreatments.isEmpty {
                balanced = "Pool chemistry is stable. No urgent treatments are needed; review the advisories for maintenance guidance."
            }
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
            parts.append("\(names) \(criticals.count == 1 ? "is" : "are") at critical levels requiring immediate attention.")
        }

        if !actionTreatments.isEmpty {
            let count = actionTreatments.count
            parts.append("\(count) treatment\(count == 1 ? "" : "s") should be handled based on current risk.")
        }

        if !optionalTreatments.isEmpty {
            parts.append("Optional maintenance can fine-tune the water, but it is not an emergency.")
        }

        if !advisoryTreatments.isEmpty {
            parts.append("Advisories are informational and do not necessarily require adding chemicals.")
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

        parts.append("\(treatments.count) card\(treatments.count == 1 ? "" : "s") generated.")

        return parts.joined(separator: " ")
    }

    private func visualIndicatorTreatments(
        for test: PoolTest,
        config: PoolConfiguration,
        existingTreatments: inout [TreatmentTemplate]
    ) -> [TreatmentTemplate] {
        var treatments: [TreatmentTemplate] = []
        let indicators = Set(test.visualIndicators)
        let hasCrystalClear = indicators.contains(VisualIndicator.crystalClear.rawValue)
        let hasAlgae = indicators.contains(VisualIndicator.greenWater.rawValue)
            || indicators.contains(VisualIndicator.algaeSpots.rawValue)
        let hasCloudyWater = indicators.contains(VisualIndicator.cloudyWater.rawValue) && !hasCrystalClear

        // Algae/green water still triggers a shock even if the user marked Crystal Clear too —
        // visible algae is hard to misobserve and the chemistry impact is severe.
        if hasAlgae, let chlorineIndex = existingTreatments.firstIndex(where: { $0.targetParameter == "freeChlorine" && $0.amount > 0 }) {
            existingTreatments[chlorineIndex].urgency = .immediate
            existingTreatments[chlorineIndex].actionDescription = recoveryChlorineReason(
                lowSanitizer: test.freeChlorine < 2,
                elevatedCombinedChlorine: test.combinedChlorine > 0.5,
                cloudyWater: hasCloudyWater,
                algae: true
            )
            existingTreatments[chlorineIndex].instructions = "Brush affected surfaces, run the pump continuously, and add this chlorine dose for the combined low-sanitizer and algae recovery conditions. Avoid dichlor or trichlor during algae recovery when CYA is already elevated. Use the Next Pool Test card for verification timing."
        } else if hasAlgae {
            let slamTarget = min(max(test.cyanuricAcid * 0.40, 10), 30)
            let ppmIncrease = max(0, slamTarget - test.freeChlorine)
            let productID = algaeRecoveryChlorineProductID(for: config)
            let concentration = productID == .liquidChlorine12_5 ? 12.5 : 10
            let gallons = (ppmIncrease * config.volumeGallons / 10000 / concentration).roundedLiquidChlorineDose()
            treatments.append(TreatmentTemplate(
                chemicalName: productID.displayName,
                actionDescription: recoveryChlorineReason(
                    lowSanitizer: test.freeChlorine < 2,
                    elevatedCombinedChlorine: test.combinedChlorine > 0.5,
                    cloudyWater: hasCloudyWater,
                    algae: true
                ),
                amount: gallons,
                unit: "gal",
                instructions: "Brush affected surfaces, run the pump continuously, and raise FC toward about \(Int(slamTarget.rounded())) ppm for the current CYA. Avoid dichlor or trichlor during algae recovery when CYA is already elevated. Use the Next Pool Test card for verification timing.",
                targetParameter: "freeChlorine",
                urgency: .immediate,
                minutesBeforeNext: 480,
                sortOrder: 900,
                expectedEffectParameter: "freeChlorine",
                expectedDelta: ppmIncrease,
                effectDelayHours: 2,
                effectDurationHours: 24,
                doNotRepeatHours: 4,
                productID: productID,
                globalPreferenceProductID: config.chlorinePreference.productID,
                calculatedDoseBeforeCap: gallons,
                calculatedDoseBeforeCapUnit: "gal"
            ))
        }

        // Diagnose cloudy water with sanitation and filtration before adding clarifier.
        if hasCloudyWater {
            treatments.append(TreatmentTemplate(
                chemicalName: "Keep Filtering Cloudy Water",
                actionDescription: "Cloudiness usually needs circulation and filtration while sanitizer is verified by the Next Pool Test.",
                amount: 0,
                unit: "",
                instructions: "Clean or backwash the filter, run circulation continuously, and brush the pool. Use clarifier only after sanitizer is in range and filtration has had time to work.",
                targetParameter: "visualIndicators",
                urgency: .recommended,
                minutesBeforeNext: 0,
                sortOrder: 901
            ))
        }

        return treatments
    }

    private func recoveryChlorineReason(
        lowSanitizer: Bool,
        elevatedCombinedChlorine: Bool,
        cloudyWater: Bool,
        algae: Bool
    ) -> String {
        var reasons: [String] = []
        if lowSanitizer { reasons.append("low sanitizer") }
        if algae { reasons.append("algae recovery") }
        if elevatedCombinedChlorine { reasons.append("elevated combined chlorine") }
        if cloudyWater { reasons.append("cloudy/problem water") }
        return reasons.isEmpty
            ? "Raise chlorine for recovery conditions"
            : "Raise chlorine for " + reasons.joined(separator: ", ")
    }

    private func algaeRecoveryChlorineProductID(for config: PoolConfiguration) -> ChemicalProductID {
        switch config.chlorinePreference {
        case .liquidChlorine12_5:
            return .liquidChlorine12_5
        default:
            return .liquidChlorine10
        }
    }
}
