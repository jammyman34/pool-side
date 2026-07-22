import Foundation

struct PoolStateNormalizer {
    /// Normalization tolerance only. This distinguishes tiny rounding artifacts from objective TC/FC contradictions.
    private let chlorineComparisonTolerance = 0.05

    func normalize(request: AIRecommendationRequest, evaluationDate: Date = Date()) -> NormalizedPoolState {
        let test = request.currentTest
        let readings = normalizedReadings(for: test)
        let visualIndicators = Set(test.visualIndicators)
        let conditions = test.poolConditions
        let previousTests = request.recentHistory
            .filter { $0.id != test.id && $0.date < test.date }
            .sorted { $0.date > $1.date }
        let treatments = test.treatments
        let actionableTreatments = treatments.filter { !$0.isWatchlistItem }
        let completedTreatments = actionableTreatments.filter(\.isCompleted)

        return NormalizedPoolState(
            currentTestID: test.id,
            testDate: test.date,
            ageInMinutes: max(0, Int(evaluationDate.timeIntervalSince(test.date) / 60)),
            evaluationDate: evaluationDate,
            poolVolumeGallons: request.poolConfig.volumeGallons,
            surfaceType: request.poolConfig.surfaceType,
            saltSystemEnabled: request.poolConfig.isSaltwater,
            configuredTestMethod: request.poolConfig.testMethod,
            freeChlorine: readings.freeChlorine,
            totalChlorine: readings.totalChlorine,
            combinedChlorine: readings.combinedChlorine,
            pH: readings.pH,
            totalAlkalinity: readings.totalAlkalinity,
            calciumHardness: readings.calciumHardness,
            cyanuricAcid: readings.cyanuricAcid,
            saltLevel: readings.saltLevel,
            waterTemperature: readings.waterTemperature,
            unavailableReadingIdentifiers: readings.unavailableIdentifiers,
            internallyConflictingReadingIdentifiers: readings.conflictingIdentifiers,
            actualTestMethod: test.testMethod,
            testMethodConfidence: confidence(for: test.testMethod),
            normalizedWaterClarity: waterClarity(for: test, indicators: visualIndicators),
            normalizedVisibleAlgae: visibleAlgae(for: test, indicators: visualIndicators),
            odorReported: reportedIndicator(.strongChlorineSmell, in: visualIndicators),
            foamReported: reportedIndicator(.foam, in: visualIndicators),
            visualConditionsComplete: visualConditionsComplete(for: test, indicators: visualIndicators),
            recentRain: rainState(from: conditions),
            recentRefill: refillState(from: conditions),
            recentBackwash: backwashState(from: conditions),
            recentHeavyBatherLoad: heavyBatherState(from: conditions),
            recentContaminationConcern: .notRecorded,
            activeTreatmentCount: actionableTreatments.filter { !$0.isCompleted && !$0.isSkipped }.count,
            completedTreatmentCount: completedTreatments.count,
            skippedTreatmentCount: actionableTreatments.filter(\.isSkipped).count,
            mostRecentTreatmentCompletionDate: completedTreatments.compactMap(\.completedAt).max(),
            circulationStatus: .notRecorded,
            knownPumpRunningSince: nil,
            recentTestCount: previousTests.count,
            latestPreviousTestDate: previousTests.first?.date,
            hasConflictingRecentTest: false,
            hasRecentTreatmentHistory: request.recentHistory.contains { !$0.treatments.isEmpty }
        )
    }

    private func normalizedReadings(for test: PoolTest) -> (
        freeChlorine: Double?,
        totalChlorine: Double?,
        combinedChlorine: Double?,
        pH: Double?,
        totalAlkalinity: Double?,
        calciumHardness: Double?,
        cyanuricAcid: Double?,
        saltLevel: Double?,
        waterTemperature: Double?,
        unavailableIdentifiers: [String],
        conflictingIdentifiers: [String]
    ) {
        let freeChlorine = finite(test.freeChlorine, identifier: "freeChlorine")
        let totalChlorine = finite(test.totalChlorine, identifier: "totalChlorine")
        let pH = finite(test.pH, identifier: "pH")
        let totalAlkalinity = finite(test.totalAlkalinity, identifier: "totalAlkalinity")
        let calciumHardness = finite(test.calciumHardness, identifier: "calciumHardness")
        let cyanuricAcid = finite(test.cyanuricAcid, identifier: "cyanuricAcid")
        let saltLevel = finite(test.saltLevel, identifier: "saltLevel")
        let waterTemperature = finite(test.temperatureFahrenheit, identifier: "waterTemperature")

        var unavailable = [String]()
        unavailable += unavailableIdentifier(freeChlorine)
        unavailable += unavailableIdentifier(totalChlorine)
        unavailable += unavailableIdentifier(pH)
        unavailable += unavailableIdentifier(totalAlkalinity)
        unavailable += unavailableIdentifier(calciumHardness)
        unavailable += unavailableIdentifier(cyanuricAcid)
        unavailable += unavailableIdentifier(saltLevel)
        unavailable += unavailableIdentifier(waterTemperature)

        var conflicts = [String]()
        let combinedChlorine: Double?
        if let direct = directlyMeasuredCombinedChlorine(for: test) {
            combinedChlorine = direct
        } else if let fc = freeChlorine.value, let tc = totalChlorine.value {
            if tc + chlorineComparisonTolerance < fc {
                combinedChlorine = nil
                conflicts.append("combinedChlorine")
            } else {
                combinedChlorine = max(0, tc - fc)
            }
        } else {
            combinedChlorine = nil
            unavailable.append("combinedChlorine")
        }

        return (
            freeChlorine.value,
            totalChlorine.value,
            combinedChlorine,
            pH.value,
            totalAlkalinity.value,
            calciumHardness.value,
            cyanuricAcid.value,
            saltLevel.value,
            waterTemperature.value,
            unavailable,
            conflicts
        )
    }

    private func finite(_ value: Double, identifier: String) -> (identifier: String, value: Double?) {
        (identifier, value.isFinite ? value : nil)
    }

    private func finite(_ value: Double?, identifier: String) -> (identifier: String, value: Double?) {
        guard let value, value.isFinite else { return (identifier, nil) }
        return (identifier, value)
    }

    private func unavailableIdentifier(_ reading: (identifier: String, value: Double?)) -> [String] {
        reading.value == nil ? [reading.identifier] : []
    }

    private func directlyMeasuredCombinedChlorine(for test: PoolTest) -> Double? {
        guard let drops = test.taylorCCDrops, let sampleSize = test.taylorSampleSize else { return nil }
        return Double(drops) * sampleSize.ppmPerDrop
    }

    private func confidence(for method: TestMethod) -> NormalizedTestMethodConfidence {
        switch method {
        case .liquidDropKit:
            return .high
        case .digitalTester, .poolStore:
            return .medium
        case .testStrips:
            return .low
        }
    }

    private func waterClarity(for test: PoolTest, indicators: Set<String>) -> NormalizedWaterClarity {
        switch test.waterClarityAssessment {
        case .clear:
            return .clear
        case .cloudy:
            return .cloudy
        case .cannotTell:
            return .cannotTell
        case .notRecorded:
            if indicators.contains(VisualIndicator.cloudyWater.rawValue) || indicators.contains(VisualIndicator.greenWater.rawValue) {
                return .cloudy
            }
            if indicators.contains(VisualIndicator.crystalClear.rawValue) {
                return .clear
            }
            return .notRecorded
        }
    }

    private func visibleAlgae(for test: PoolTest, indicators: Set<String>) -> NormalizedVisibleAlgae {
        switch test.visibleAlgaeAssessment {
        case .absent:
            return .absent
        case .present:
            return .present
        case .cannotTell:
            return .cannotTell
        case .notRecorded:
            if indicators.contains(VisualIndicator.algaeSpots.rawValue) || indicators.contains(VisualIndicator.greenWater.rawValue) {
                return .present
            }
            return .notRecorded
        }
    }

    private func visualConditionsComplete(for test: PoolTest, indicators: Set<String>) -> Bool {
        let clarity = waterClarity(for: test, indicators: indicators)
        let algae = visibleAlgae(for: test, indicators: indicators)
        return clarity != .notRecorded && clarity != .cannotTell && clarity != .unknown
            && algae != .notRecorded && algae != .cannotTell && algae != .unknown
    }

    private func reportedIndicator(_ indicator: VisualIndicator, in indicators: Set<String>) -> NormalizedReportedState {
        indicators.contains(indicator.rawValue) ? .reportedPresent : .notRecorded
    }

    private func rainState(from conditions: PoolConditions?) -> NormalizedReportedState {
        guard let conditions else { return .notRecorded }
        switch conditions.rainLoad {
        case .light, .steady, .heavy:
            return .reportedPresent
        case .none:
            return .reportedAbsent
        case .unknown:
            return .unknown
        }
    }

    private func refillState(from conditions: PoolConditions?) -> NormalizedReportedState {
        guard let conditions else { return .notRecorded }
        switch conditions.waterAdded {
        case .lessThanOneInch, .oneToTwoInches, .moreThanTwoInches:
            return .reportedPresent
        case .none:
            return .reportedAbsent
        case .unknown:
            return .unknown
        }
    }

    private func backwashState(from conditions: PoolConditions?) -> NormalizedReportedState {
        guard let conditions else { return .notRecorded }
        switch conditions.backwashedFilter {
        case .yes:
            return .reportedPresent
        case .no:
            return .reportedAbsent
        }
    }

    private func heavyBatherState(from conditions: PoolConditions?) -> NormalizedReportedState {
        guard let conditions else { return .notRecorded }
        if conditions.swimmingLoad == .high || conditions.petSwimmingLoad == .high {
            return .reportedPresent
        }
        if conditions.swimmingLoad == .unknown || conditions.petSwimmingLoad == .unknown {
            return .unknown
        }
        return .reportedAbsent
    }
}
