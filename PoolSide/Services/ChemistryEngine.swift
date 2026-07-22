import Foundation
import SwiftUI

// MARK: - Chemical Status

enum ChemicalStatus: String, CaseIterable {
    case ideal         = "ideal"
    case slightlyLow   = "slightly_low"
    case slightlyHigh  = "slightly_high"
    case low           = "low"
    case high          = "high"
    case critical      = "critical"
    case testing       = "testing"

    var displayName: String {
        switch self {
        case .ideal:        return "Ideal"
        case .slightlyLow:  return "Slightly Low"
        case .slightlyHigh: return "Slightly High"
        case .low:          return "Low"
        case .high:         return "High"
        case .critical:     return "Critical"
        case .testing:      return "Testing"
        }
    }

    var color: Color {
        switch self {
        case .ideal:                      return PoolColor.statusIdeal
        case .slightlyLow, .slightlyHigh: return PoolColor.statusSlight
        case .low, .high:                 return PoolColor.statusOffRange
        case .critical:                   return PoolColor.statusCritical
        case .testing:                    return PoolColor.statusTesting
        }
    }

    var icon: String {
        switch self {
        case .ideal:        return "checkmark.circle.fill"
        case .slightlyLow:  return "arrow.down.circle"
        case .slightlyHigh: return "arrow.up.circle"
        case .low:          return "arrow.down.circle.fill"
        case .high:         return "arrow.up.circle.fill"
        case .critical:     return "exclamationmark.triangle.fill"
        case .testing:      return "clock.fill"
        }
    }

    /// Maps to TreatmentUrgency for treatment generation
    var treatmentUrgency: TreatmentUrgency? {
        switch self {
        case .ideal, .testing: return nil
        case .slightlyLow, .slightlyHigh: return .optional
        case .low, .high:      return .recommended
        case .critical:        return .immediate
        }
    }
}

// MARK: - Chemical Reading

struct ChemicalReading: Identifiable {
    let id = UUID()
    let parameter: String
    let key: String
    let value: Double
    let unit: String
    let status: ChemicalStatus
    let idealRange: String
    let trend: Trend?

    enum Trend {
        case rising, falling, stable
        var icon: String {
            switch self {
            case .rising:  return "arrow.up.right"
            case .falling: return "arrow.down.right"
            case .stable:  return "arrow.right"
            }
        }
    }
}

// MARK: - Chemistry Engine

struct ChemistryEngine {

    // MARK: - Reference Ranges

    struct Ranges {
        static let pH           = 7.2...7.6
        static let pHLow        = 6.8...7.2
        static let pHHigh       = 7.6...8.0
        static let pHCritical   = 0.0...6.8

        static let totalAlkalinity       = 80.0...120.0
        static let totalAlkalinityLow    = 60.0...80.0
        static let totalAlkalinityHigh   = 120.0...150.0

        static let calciumHardness       = 200.0...400.0
        static let calciumHardnessLow    = 150.0...200.0
        static let calciumHardnessHigh   = 400.0...500.0

        static let cyanuricAcid          = 30.0...50.0
        static let cyanuricAcidLow       = 10.0...30.0
        static let cyanuricAcidHigh      = 50.0...100.0

        static let salt                  = 2700.0...3400.0
        static let saltLow               = 2000.0...2700.0
        static let saltHigh              = 3400.0...4000.0
    }

    // MARK: - Status Calculation

    func pHStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case 7.2...7.6:         return .ideal
        case 7.0..<7.2:         return .slightlyLow
        case 7.6...8.0:         return .slightlyHigh
        case 6.8..<7.0:         return .low
        case 8.0...8.2:         return .high
        default:                 return .critical
        }
    }

    func freeChlorineStatus(_ value: Double) -> ChemicalStatus {
        freeChlorineStatus(value, cyanuricAcid: nil)
    }

    func freeChlorineStatus(_ value: Double, cyanuricAcid: Double?) -> ChemicalStatus {
        let range = freeChlorineTargetRange(cyanuricAcid: cyanuricAcid)
        let minimum = freeChlorineMinimum(cyanuricAcid: cyanuricAcid)
        let maintenanceFloor = max(0, minimum - 0.5)
        let veryLow = max(0, minimum * 0.5)
        let shockLevel = freeChlorineShockLevel(cyanuricAcid: cyanuricAcid)

        switch value {
        case range:
            return .ideal
        case maintenanceFloor..<range.lowerBound:
            return .slightlyLow
        case range.upperBound..<shockLevel:
            return .high
        case veryLow..<maintenanceFloor:
            return .low
        case 0..<veryLow:
            return .critical
        default:
            return .critical
        }
    }

    func freeChlorineTargetRange(cyanuricAcid: Double?) -> ClosedRange<Double> {
        guard let cya = cyanuricAcid, cya >= 20 else {
            return 1.0...3.0
        }

        let minimum = freeChlorineMinimum(cyanuricAcid: cya)
        let target = max(minimum + 1.5, cya * 0.10)
        let upper = max(target + 2.0, cya * 0.12)
        return target...upper
    }

    func freeChlorineSwimReadinessMinimum(cyanuricAcid: Double?) -> Double {
        freeChlorineMinimum(cyanuricAcid: cyanuricAcid)
    }

    func freeChlorineIdealRangeLabel(cyanuricAcid: Double?) -> String {
        let range = freeChlorineTargetRange(cyanuricAcid: cyanuricAcid)
        return "\(formatRangeBound(range.lowerBound)) – \(formatRangeBound(range.upperBound)) ppm"
    }

    private func calciumHardnessIdealRangeLabel(surface: SurfaceType) -> String {
        switch surface {
        case .plaster, .pebble:
            return "250 – 400 ppm"
        case .vinyl, .fiberglass:
            return "150 – 300 ppm"
        }
    }

    private func formatRangeBound(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func freeChlorineMinimum(cyanuricAcid: Double?) -> Double {
        guard let cya = cyanuricAcid, cya >= 20 else {
            return 1.0
        }

        return max(1.0, (cya * 0.075).rounded(toPlaces: 1))
    }

    private func freeChlorineTargetMidpoint(cyanuricAcid: Double?) -> Double {
        let range = freeChlorineTargetRange(cyanuricAcid: cyanuricAcid)
        return (range.lowerBound + range.upperBound) / 2
    }

    private func freeChlorineShockLevel(cyanuricAcid: Double?) -> Double {
        guard let cya = cyanuricAcid, cya >= 20 else {
            return 10
        }

        return max(cya * 0.40, 10)
    }

    func totalAlkalinityStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case Ranges.totalAlkalinity: return .ideal
        case 70.0..<80.0:           return .slightlyLow
        case 120.0...140.0:         return .slightlyHigh
        case 50.0..<70.0:           return .low
        case 140.0..<200.0:         return .slightlyHigh
        default:                     return .critical
        }
    }

    func calciumHardnessStatus(_ value: Double, surface: SurfaceType = .plaster) -> ChemicalStatus {
        let ideal: ClosedRange<Double>
        let acceptable: ClosedRange<Double>
        switch surface {
        case .plaster, .pebble:
            ideal = 250...400
            acceptable = 200...450
        case .vinyl, .fiberglass:
            ideal = 150...300
            acceptable = 125...350
        }
        switch value {
        case ideal:               return .ideal
        case acceptable:          return value < ideal.lowerBound ? .slightlyLow : .slightlyHigh
        case 0..<acceptable.lowerBound: return .low
        default:                  return .high
        }
    }

    func cyanuricAcidStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case 30.0...50.0:          return .ideal
        case 15.0..<30.0:          return .slightlyLow
        case 50.0...90.0:          return .slightlyHigh
        case 0.0..<15.0:           return .low
        case 90.0...110.0:         return .high
        default:                    return .critical
        }
    }

    func saltStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case Ranges.salt:     return .ideal
        case 2400..<2700:    return .slightlyLow
        case 3400..<3600:    return .slightlyHigh
        case 0..<2400:       return .low
        default:              return .high
        }
    }

    // MARK: - All Readings

    func allReadings(for test: PoolTest, previousTest: PoolTest? = nil, config: PoolConfiguration = .current) -> [ChemicalReading] {
        var readings: [ChemicalReading] = []

        let phTrend = previousTest.map { trend(current: test.pH, previous: $0.pH) }
        readings.append(ChemicalReading(
            parameter: "pH",
            key: "pH",
            value: test.pH,
            unit: "",
            status: pHStatus(test.pH),
            idealRange: "7.2 – 7.8",
            trend: phTrend
        ))

        let clTrend = previousTest.map { trend(current: test.freeChlorine, previous: $0.freeChlorine) }
        readings.append(ChemicalReading(
            parameter: "Free Chlorine",
            key: "freeChlorine",
            value: test.freeChlorine,
            unit: "ppm",
            status: freeChlorineStatus(test.freeChlorine, cyanuricAcid: test.cyanuricAcid),
            idealRange: freeChlorineIdealRangeLabel(cyanuricAcid: test.cyanuricAcid),
            trend: clTrend
        ))

        let alkTrend = previousTest.map { trend(current: test.totalAlkalinity, previous: $0.totalAlkalinity) }
        readings.append(ChemicalReading(
            parameter: "Total Alkalinity",
            key: "totalAlkalinity",
            value: test.totalAlkalinity,
            unit: "ppm",
            status: totalAlkalinityStatus(test.totalAlkalinity),
            idealRange: "80 – 120 ppm",
            trend: alkTrend
        ))

        let chTrend = previousTest.map { trend(current: test.calciumHardness, previous: $0.calciumHardness) }
        readings.append(ChemicalReading(
            parameter: "Calcium Hardness",
            key: "calciumHardness",
            value: test.calciumHardness,
            unit: "ppm",
            status: calciumHardnessStatus(test.calciumHardness, surface: config.surfaceType),
            idealRange: calciumHardnessIdealRangeLabel(surface: config.surfaceType),
            trend: chTrend
        ))

        let caTrend = previousTest.map { trend(current: test.cyanuricAcid, previous: $0.cyanuricAcid) }
        readings.append(ChemicalReading(
            parameter: "Cyanuric Acid",
            key: "cyanuricAcid",
            value: test.cyanuricAcid,
            unit: "ppm",
            status: cyanuricAcidStatus(test.cyanuricAcid),
            idealRange: "30 – 50 ppm ideal; 50 – 80 manageable",
            trend: caTrend
        ))

        if config.isSaltwater, let salt = test.saltLevel {
            let saltTrend = previousTest.flatMap { $0.saltLevel }.map { trend(current: salt, previous: $0) }
            readings.append(ChemicalReading(
                parameter: "Salt Level",
                key: "saltLevel",
                value: salt,
                unit: "ppm",
                status: saltStatus(salt),
                idealRange: "2700 – 3400 ppm",
                trend: saltTrend
            ))
        }

        return readings
    }

    // MARK: - Current Status Summary

    func currentStatusSummary(for test: PoolTest, treatments: [Treatment] = [], config: PoolConfiguration = .current) -> String {
        let indicators = Set(test.visualIndicators)

        if indicators.contains(VisualIndicator.greenWater.rawValue) || indicators.contains(VisualIndicator.algaeSpots.rawValue) {
            return "Recovery"
        }

        if indicators.contains(VisualIndicator.cloudyWater.rawValue) && !indicators.contains(VisualIndicator.crystalClear.rawValue) {
            return "Recovery"
        }

        if test.pH < 7.0 || test.pH > 8.0 {
            return "Recovery"
        }

        let minimumFC = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        let targetLower = freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound
        let lowChlorine = test.freeChlorine < targetLower || test.freeChlorine < minimumFC
        let contaminationIndicators = indicators.contains(VisualIndicator.strongChlorineSmell.rawValue)
            || indicators.contains(VisualIndicator.foam.rawValue)
            || test.resolvedPoolConditions.chlorineDemandContribution >= 3

        if test.combinedChlorine >= 1.0 && (lowChlorine || contaminationIndicators) {
            return "Recovery"
        }

        let elevatedAlkalinity = test.totalAlkalinity > 140
        let elevatedStabilizer = test.cyanuricAcid > 50
        let elevatedCombinedChlorine = test.combinedChlorine >= 0.5
        let hardnessIssue = calciumHardnessStatus(test.calciumHardness, surface: config.surfaceType) != .ideal
        let saltIssue = config.isSaltwater && test.saltLevel.map { saltStatus($0) != .ideal } == true
        let possibleDilution = test.resolvedPoolConditions.waterChangeContribution >= 3
            || treatments.contains { $0.chemicalName.localizedCaseInsensitiveContains("Dilution") }

        let issueCount = [
            lowChlorine,
            elevatedAlkalinity,
            elevatedStabilizer,
            elevatedCombinedChlorine,
            hardnessIssue,
            saltIssue
        ].filter { $0 }.count

        if issueCount >= 3 {
            return "Needs Attention"
        }

        if possibleDilution && issueCount <= 1 {
            return "Monitor Trends"
        }

        if lowChlorine && elevatedAlkalinity {
            return "Needs Chlorine"
        }

        if lowChlorine {
            return "Needs Chlorine"
        }

        if elevatedAlkalinity {
            return test.pH >= 7.8 ? "Needs pH Adjustment" : "Monitor Trends"
        }

        if elevatedStabilizer {
            return "Monitor Trends"
        }

        if elevatedCombinedChlorine {
            return "Needs Attention"
        }

        if hardnessIssue {
            return "Needs Attention"
        }

        if saltIssue {
            return "Needs Attention"
        }

        return "Balanced"
    }

    // MARK: - Overall Score

    static func scoreStatusLabel(score: Int, status: String) -> String {
        if status == "Recovery" {
            return "Problem Recovery"
        }

        switch score {
        case 85...100:
            return "Stable"
        case 70..<85:
            return "Good / watch"
        case 60..<70:
            return "Needs Attention"
        default:
            switch status {
            case "Needs Chlorine", "Needs pH Adjustment", "Monitor Trends":
                return status
            default:
                return "Needs Attention"
            }
        }
    }

    func overallScore(
        for test: PoolTest,
        previousTest: PoolTest? = nil,
        recentHistory: [PoolTest] = [],
        config: PoolConfiguration = .current
    ) -> Int {
        let readings = allReadings(for: test, previousTest: previousTest, config: config)
        guard !readings.isEmpty else { return 0 }

        var penalty = readings.reduce(0.0) { total, reading in
            total + scorePenalty(
                for: reading,
                test: test,
                previousTest: previousTest,
                recentHistory: recentHistory,
                config: config
            )
        }

        penalty += combinedChlorinePenalty(for: test)
        penalty += visualIndicatorPenalty(for: test)
        penalty += poolConditionsPenalty(for: test)

        var score = max(0, min(100, 100 - penalty))
        if let floor = scoreFloor(for: test, previousTest: previousTest, recentHistory: recentHistory, config: config) {
            score = max(score, floor)
        }

        return Int(score.rounded())
    }

    private func scorePenalty(
        for reading: ChemicalReading,
        test: PoolTest,
        previousTest: PoolTest?,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Double {
        var penalty = contextualBasePenalty(
            for: reading,
            test: test,
            previousTest: previousTest,
            recentHistory: recentHistory,
            config: config
        )

        guard penalty > 0 else { return 0 }

        if let trend = reading.trend {
            switch trend {
            case .rising where reading.status == .slightlyLow || reading.status == .low:
                penalty *= 0.85
            case .falling where reading.status == .slightlyHigh || reading.status == .high:
                penalty *= 0.85
            case .falling where reading.status == .slightlyLow || reading.status == .low:
                penalty *= 1.15
            case .rising where reading.status == .slightlyHigh || reading.status == .high:
                penalty *= 1.15
            case .stable:
                break
            default:
                break
            }
        }

        if shouldTreatAsLikelyTestingVariance(reading: reading, test: test, previousTest: previousTest, config: config) {
            penalty *= 0.3
        }

        if reading.key == "freeChlorine",
           (config.testMethod == .testStrips || test.testMethod == .testStrips),
           test.totalChlorine + 0.3 < test.freeChlorine {
            penalty *= 0.6
        }

        if shouldStronglyReduceSecondaryAdvisoryPenalty(reading: reading, test: test, recentHistory: recentHistory, config: config) {
            penalty *= 0.3
        } else if shouldReduceSecondaryAdvisoryPenalty(reading: reading, test: test, recentHistory: recentHistory, config: config) {
            penalty *= 0.5
        }

        return penalty
    }

    private func contextualBasePenalty(
        for reading: ChemicalReading,
        test: PoolTest,
        previousTest: PoolTest?,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Double {
        guard reading.status != .ideal && reading.status != .testing else { return 0 }

        switch reading.key {
        case "pH":
            if test.pH < 7.0 || test.pH > 8.0 { return reading.status == .critical ? 34 : 26 }
            return 8

        case "freeChlorine":
            let minimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
            let maintenanceFloor = max(0, minimum - 0.5)
            let isProblemWater = hasVisibleAlgae(test) || hasCloudyWater(test)
            if test.freeChlorine < minimum * 0.5 { return isProblemWater ? 42 : 30 }
            if test.freeChlorine < maintenanceFloor { return isProblemWater ? 32 : 22 }
            if test.freeChlorine < minimum {
                return isStablePoolContext(test, previousTest: previousTest, recentHistory: recentHistory, config: config) ? 14 : 18
            }
            if test.freeChlorine < freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound {
                return isStablePoolContext(test, previousTest: previousTest, recentHistory: recentHistory, config: config) ? 10 : 14
            }
            return 3

        case "totalAlkalinity":
            if test.totalAlkalinity > 140 {
                if test.totalAlkalinity >= 200 { return 12 }
                if test.pH >= 7.6 || isPHRising(current: test, previousTest: previousTest) || hasScaling(test) { return 10 }
                if test.pH <= 7.4 && !hasVisibleAlgae(test) && !hasCloudyWater(test) { return 3 }
                return isStablePoolContext(test, previousTest: previousTest, recentHistory: recentHistory, config: config) ? 6 : 8
            }
            return 4

        case "cyanuricAcid":
            if test.cyanuricAcid > 90 { return 16 }
            if test.cyanuricAcid >= 80 { return isStablePoolContext(test, previousTest: previousTest, recentHistory: recentHistory, config: config) ? 8 : 12 }
            if test.cyanuricAcid > 50 { return isStablePoolContext(test, previousTest: previousTest, recentHistory: recentHistory, config: config) ? 6 : 8 }
            if test.cyanuricAcid < 15 { return 12 }
            return 4

        case "calciumHardness":
            if test.calciumHardness > 450 && (test.pH >= 7.8 || hasScaling(test)) { return 12 }
            if test.calciumHardness < calciumAcceptableRange(surface: config.surfaceType).lowerBound { return 8 }
            return isClearAndSafe(test, config: config) ? 2 : 5

        case "saltLevel":
            switch reading.status {
            case .low, .high, .critical: return 12
            default: return 5
            }

        default:
            return 5
        }
    }

    private func shouldTreatAsLikelyTestingVariance(
        reading: ChemicalReading,
        test: PoolTest,
        previousTest: PoolTest?,
        config: PoolConfiguration
    ) -> Bool {
        guard config.testMethod == .testStrips || test.testMethod == .testStrips else { return false }
        guard let previousTest else { return false }

        switch reading.key {
        case "cyanuricAcid":
            return abs(test.cyanuricAcid - previousTest.cyanuricAcid) >= 10
                && reading.status == .slightlyLow
        case "totalAlkalinity":
            return abs(test.totalAlkalinity - previousTest.totalAlkalinity) <= 10
                && (reading.status == .slightlyLow || reading.status == .slightlyHigh)
        default:
            return false
        }
    }

    private func isPHRising(current test: PoolTest, previousTest: PoolTest?) -> Bool {
        guard let previousTest else { return false }
        return test.pH - previousTest.pH >= 0.2
    }

    private func shouldTreatHighAlkalinityWithAcid(_ alkalinity: Double, test: PoolTest, previousTest: PoolTest?) -> Bool {
        guard alkalinity > 140 else { return false }
        if hasScaling(test) { return true }
        if test.pH <= 7.6 { return false }
        if test.pH >= 7.8 { return false }
        if isPHRising(current: test, previousTest: previousTest) { return true }
        return alkalinity >= 200 && test.pH > 7.6
    }

    private func shouldTreatHighPHWithAcid(_ pH: Double, test: PoolTest, previousTest: PoolTest?, recentHistory: [PoolTest]) -> Bool {
        if hasActiveRecentAcidTreatment(recentHistory: recentHistory) { return false }
        if pH > 8.0 { return true }
        if pH >= 7.8 {
            return hasScaling(test)
                || isPHRising(current: test, previousTest: previousTest)
                || pHHistorySupportsConservativeAcid(current: test, recentHistory: recentHistory)
        }
        if pH > 7.6 {
            return isPHRising(current: test, previousTest: previousTest) || hasScaling(test)
        }
        return false
    }

    private func pHDecreaserUrgency(for pH: Double, test: PoolTest, previousTest: PoolTest?, recentHistory: [PoolTest]) -> TreatmentUrgency {
        if pH > 8.0 { return .immediate }
        if hasScaling(test) || isPHRising(current: test, previousTest: previousTest) || pHHistorySupportsConservativeAcid(current: test, recentHistory: recentHistory) {
            return .recommended
        }
        return .optional
    }

    private func pHHistorySupportsConservativeAcid(current test: PoolTest, recentHistory: [PoolTest]) -> Bool {
        let historical = Array(recentHistory.prefix(5).reversed())
        guard historical.count >= 3 else { return false }
        let pHValues = historical.map(\.pH) + [test.pH]
        guard let first = pHValues.first, let last = pHValues.last else { return false }
        let upwardSteps = zip(pHValues.dropLast(), pHValues.dropFirst()).filter { $1 >= $0 - 0.05 }.count
        let elevatedTAReadings = (historical + [test]).filter { $0.totalAlkalinity >= 140 }.count
        return last >= 7.8
            && last - first >= 0.25
            && upwardSteps >= pHValues.count - 2
            && elevatedTAReadings >= 3
            && !hasCompletedAcidTreatment(recentHistory: recentHistory)
    }

    private func hasCompletedAcidTreatment(recentHistory: [PoolTest]) -> Bool {
        recentHistory
            .flatMap(\.treatments)
            .contains { $0.isCompleted && $0.isAcidTreatment }
    }

    private func hasActiveRecentAcidTreatment(recentHistory: [PoolTest]) -> Bool {
        activeRecentAcidTreatment(recentHistory: recentHistory) != nil
    }

    private func activeRecentAcidTreatment(recentHistory: [PoolTest]) -> Treatment? {
        let now = Date()
        return recentHistory
            .flatMap(\.treatments)
            .first { treatment in
                treatment.isCompleted
                    && treatment.isAcidTreatment
                    && (treatment.doNotRepeatBefore.map { $0 > now } ?? false)
            }
    }

    private func pHAcidActionDescription(for test: PoolTest, recentHistory: [PoolTest]) -> String {
        if pHHistorySupportsConservativeAcid(current: test, recentHistory: recentHistory) {
            return "pH has gradually risen while TA stayed elevated, and no acid treatment has been completed during that period, so a conservative correction is reasonable now"
        }
        if hasScaling(test) {
            return "Lower pH conservatively to reduce scaling risk"
        }
        if test.pH > 7.8 {
            return "Lower pH with a measured conservative dose"
        }
        return "Monitor pH closely and make a conservative correction"
    }

    private func hasIndicator(_ indicator: VisualIndicator, in test: PoolTest) -> Bool {
        test.visualIndicators.contains(indicator.rawValue)
    }

    private func hasVisibleAlgae(_ test: PoolTest) -> Bool {
        hasIndicator(.greenWater, in: test) || hasIndicator(.algaeSpots, in: test)
    }

    private func hasCloudyWater(_ test: PoolTest) -> Bool {
        hasIndicator(.cloudyWater, in: test)
    }

    private func hasScaling(_ test: PoolTest) -> Bool {
        hasIndicator(.scaling, in: test)
    }

    private func hasFoam(_ test: PoolTest) -> Bool {
        hasIndicator(.foam, in: test)
    }

    private func hasStrongChlorineSmell(_ test: PoolTest) -> Bool {
        hasIndicator(.strongChlorineSmell, in: test)
    }

    private func hasPositiveClearWaterSignals(_ test: PoolTest) -> Bool {
        hasIndicator(.crystalClear, in: test)
            || hasIndicator(.smoothWalls, in: test)
            || hasIndicator(.pleasantSmell, in: test)
    }

    private func isClearAndSafe(_ test: PoolTest, config: PoolConfiguration) -> Bool {
        let fcMinimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        return hasPositiveClearWaterSignals(test)
            && !hasVisibleAlgae(test)
            && !hasCloudyWater(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.5
            && test.freeChlorine >= fcMinimum - 0.5
    }

    private func isLowChlorineOnlyActiveIssue(_ test: PoolTest, recentHistory: [PoolTest], config: PoolConfiguration) -> Bool {
        let fcMinimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        return hasPositiveClearWaterSignals(test)
            && !hasVisibleAlgae(test)
            && !hasCloudyWater(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.5
            && calciumAcceptableRange(surface: config.surfaceType).contains(test.calciumHardness)
            && test.freeChlorine < fcMinimum
            && test.freeChlorine >= fcMinimum * 0.35
            && !hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)
    }

    private func isStableLowChlorineOnlyActiveIssue(_ test: PoolTest, recentHistory: [PoolTest], config: PoolConfiguration) -> Bool {
        let fcMinimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        return hasPositiveClearWaterSignals(test)
            && !hasVisibleAlgae(test)
            && !hasCloudyWater(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.05
            && calciumAcceptableRange(surface: config.surfaceType).contains(test.calciumHardness)
            && test.freeChlorine < fcMinimum
            && test.freeChlorine >= fcMinimum * 0.35
            && !hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)
    }

    private func shouldReduceSecondaryAdvisoryPenalty(
        reading: ChemicalReading,
        test: PoolTest,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Bool {
        guard isLowChlorineOnlyActiveIssue(test, recentHistory: recentHistory, config: config) else { return false }

        switch reading.key {
        case "totalAlkalinity":
            return test.totalAlkalinity > 140
                && test.pH <= 7.8
                && !hasScaling(test)
        case "cyanuricAcid":
            return test.cyanuricAcid > 50
                && test.cyanuricAcid <= 90
        default:
            return false
        }
    }

    private func shouldStronglyReduceSecondaryAdvisoryPenalty(
        reading: ChemicalReading,
        test: PoolTest,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Bool {
        guard isStableLowChlorineOnlyActiveIssue(test, recentHistory: recentHistory, config: config) else { return false }

        switch reading.key {
        case "totalAlkalinity":
            return test.totalAlkalinity > 140
                && test.pH <= 7.8
                && !hasScaling(test)
        case "cyanuricAcid":
            return test.cyanuricAcid > 50
                && test.cyanuricAcid <= 90
        default:
            return false
        }
    }

    private func isStablePoolContext(
        _ test: PoolTest,
        previousTest: PoolTest?,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Bool {
        let fcMinimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        return !hasVisibleAlgae(test)
            && !hasCloudyWater(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.5
            && test.freeChlorine >= fcMinimum - 0.5
            && calciumAcceptableRange(surface: config.surfaceType).contains(test.calciumHardness)
            && !hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)
    }

    private func scoreFloor(
        for test: PoolTest,
        previousTest: PoolTest?,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Double? {
        let fcMinimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        let calciumAcceptable = calciumAcceptableRange(surface: config.surfaceType).contains(test.calciumHardness)
        let repeatedFailedChlorine = hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)

        if hasVisibleAlgae(test)
            || hasCloudyWater(test)
            || test.pH < 7.0
            || test.pH > 8.0
            || test.combinedChlorine >= 1.0
            || test.freeChlorine < fcMinimum * 0.5
            || repeatedFailedChlorine
            || hasMajorScalingOrCorrosionRisk(test, config: config) {
            return nil
        }

        if hasPositiveClearWaterSignals(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.5
            && test.freeChlorine >= fcMinimum - 0.5
            && calciumAcceptable
            && !repeatedFailedChlorine {
            return 70
        }

        if hasPositiveClearWaterSignals(test)
            && test.pH >= 7.2
            && test.pH <= 7.8
            && test.combinedChlorine <= 0.5
            && calciumAcceptable
            && test.freeChlorine < fcMinimum - 0.5
            && test.freeChlorine >= fcMinimum * 0.5 {
            return 60
        }

        return nil
    }

    private func hasMajorScalingOrCorrosionRisk(_ test: PoolTest, config: PoolConfiguration) -> Bool {
        hasScaling(test)
            || test.calciumHardness < calciumAcceptableRange(surface: config.surfaceType).lowerBound - 50
            || (test.calciumHardness > calciumAcceptableRange(surface: config.surfaceType).upperBound && test.pH >= 7.8)
    }

    private func calciumAcceptableRange(surface: SurfaceType) -> ClosedRange<Double> {
        switch surface {
        case .plaster, .pebble:
            return 200...450
        case .vinyl, .fiberglass:
            return 125...350
        }
    }

    private func combinedChlorinePenalty(for test: PoolTest) -> Double {
        if test.totalChlorine + 0.3 < test.freeChlorine {
            return 0
        }

        switch test.combinedChlorine {
        case 1.0...:
            return 25
        case 0.5...1.0 where test.combinedChlorine > 0.5:
            return 10
        default:
            return 0
        }
    }

    private func visualIndicatorPenalty(for test: PoolTest) -> Double {
        test.visualIndicators.reduce(0.0) { total, rawValue in
            guard let indicator = VisualIndicator(rawValue: rawValue) else { return total }

            switch indicator {
            case .greenWater, .algaeSpots:
                return total + 25
            case .cloudyWater:
                return total + 14
            case .strongChlorineSmell:
                return total + 10
            case .foam, .poorCirculation:
                return total + (indicator == .foam && test.freeChlorine < freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid) ? 12 : 6)
            case .scaling, .staining:
                return total + 6
            case .crystalClear, .pleasantSmell, .smoothWalls:
                return total
            }
        }
    }

    private func poolConditionsPenalty(for test: PoolTest) -> Double {
        let chlorineDemand = chlorineDemandScore(for: test)
        let waterChange = waterChangeScore(for: test)
        var penalty = 0.0

        if chlorineDemand >= 6 {
            penalty += test.freeChlorine < freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound ? 5 : 3
        } else if chlorineDemand >= 3 {
            penalty += test.freeChlorine < freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound ? 3 : 2
        }

        if waterChange >= 3 {
            penalty += 2
        }

        return penalty
    }

    func recommendationConfidenceInput(
        for test: PoolTest,
        recentHistory: [PoolTest] = []
    ) -> RecommendationConfidenceInput {
        RecommendationConfidenceInput(
            hasChemistryData: true,
            hasPoolConditions: test.poolConditions != nil,
            hasVisualIndicators: !test.visualIndicators.isEmpty,
            hasRecentHistory: !recentHistory.isEmpty,
            hasCompletedTreatmentHistory: recentHistory.flatMap(\.treatments).contains { $0.isCompleted },
            chlorineDemandScore: chlorineDemandScore(for: test),
            waterChangeScore: waterChangeScore(for: test)
        )
    }

    // MARK: - Rule-Based Treatments

    func ruleTreatments(
        for test: PoolTest,
        config: PoolConfiguration = .current,
        recentHistory: [PoolTest] = []
    ) -> [TreatmentTemplate] {
        let readings = allReadings(for: test, config: config)
        var templates: [TreatmentTemplate] = []
        let previousTest = recentHistory.first

        for reading in readings where reading.status != .ideal && reading.status != .testing {
            if let template = treatmentTemplate(
                for: reading,
                test: test,
                previousTest: previousTest,
                recentHistory: recentHistory,
                config: config
            ) {
                templates.append(template)
            }
        }

        templates.append(contentsOf: advisoryTemplates(for: test, previousTest: previousTest, config: config))

        // Sort by practical risk instead of by textbook chemical dependency.
        var sorted = suppressAcidTreatmentsWhenPHIsLowNormal(templates, for: test).sorted {
            if $0.sequencePriority == $1.sequencePriority {
                return $0.urgency.sortOrder < $1.urgency.sortOrder
            }
            return $0.sequencePriority < $1.sequencePriority
        }
        for i in 0..<sorted.count {
            sorted[i].sortOrder = i
            // Set wait after this step before the next (only if there IS a next step)
            if i < sorted.count - 1 {
                sorted[i].minutesBeforeNext = waitMinutes(for: sorted[i].targetParameter)
            }
        }
        return sorted
    }

    func validatedTreatments(
        for test: PoolTest,
        config: PoolConfiguration = .current,
        recentHistory: [PoolTest] = []
    ) -> [TreatmentTemplate] {
        var templates = ruleTreatments(for: test, config: config, recentHistory: recentHistory)
        templates = suppressRecentlyCompletedEffects(templates, recentHistory: recentHistory)
        templates = suppressChlorineDuringMixingWindow(templates, for: test, recentHistory: recentHistory)
        templates = suppressLowConfidenceOptionalTreatments(templates, config: config)
        templates = suppressAcidTreatmentsWhenPHIsLowNormal(templates, for: test)
        templates = appendActiveAcidWaitAdvisoryIfNeeded(templates, recentHistory: recentHistory)

        for i in 0..<templates.count {
            templates[i].sortOrder = i
            templates[i].minutesBeforeNext = i < templates.count - 1
                ? waitMinutes(for: templates[i].targetParameter)
                : 0
        }

        return templates
    }

    /// Standard wait time (in minutes) to observe after adding a chemical before the next treatment
    private func waitMinutes(for parameter: String) -> Int {
        switch parameter {
        case "pH":              return 240  // 4 hours
        case "totalAlkalinity": return 240  // 4 hours
        case "freeChlorine":    return 60   // 1 hour
        case "calciumHardness": return 240  // 4 hours
        case "cyanuricAcid":    return 2880 // 48 hours
        default:                return 30
        }
    }

    private func suppressRecentlyCompletedEffects(
        _ templates: [TreatmentTemplate],
        recentHistory: [PoolTest]
    ) -> [TreatmentTemplate] {
        let completedTreatments = recentHistory
            .flatMap { $0.treatments }
            .filter { $0.isCompleted }

        return templates.filter { template in
            !completedTreatments.contains { completed in
                guard
                    completed.expectedEffectParameter == template.targetParameter,
                    let doNotRepeatBefore = completed.doNotRepeatBefore
                else { return false }

                return doNotRepeatBefore > Date() && !template.isSafeToRepeat(despite: completed)
            }
        }
    }

    private func appendActiveAcidWaitAdvisoryIfNeeded(
        _ templates: [TreatmentTemplate],
        recentHistory: [PoolTest]
    ) -> [TreatmentTemplate] {
        guard !templates.contains(where: { $0.isAcidTreatment }) else { return templates }
        guard activeRecentAcidTreatment(recentHistory: recentHistory) != nil else { return templates }
        guard !templates.contains(where: { $0.chemicalName == "Wait for Acid Treatment" }) else { return templates }

        return templates + [
            TreatmentTemplate(
                chemicalName: "Wait for Acid Treatment",
                actionDescription: "A recent acid treatment is still in its wait/retest window, so another acid dose is being withheld.",
                amount: 0,
                unit: "",
                instructions: "Let the previous acid dose circulate and verify pH before adding more. Pool Side suppresses duplicate acid recommendations until the active wait window has passed or a retest confirms another correction is needed.",
                targetParameter: "pH",
                urgency: .advisory,
                expectedEffectParameter: "pH",
                expectedDelta: 0,
                effectDelayHours: 0,
                effectDurationHours: 12,
                doNotRepeatHours: 12
            )
        ]
    }

    private func suppressChlorineDuringMixingWindow(
        _ templates: [TreatmentTemplate],
        for test: PoolTest,
        recentHistory: [PoolTest]
    ) -> [TreatmentTemplate] {
        guard templates.contains(where: { $0.targetParameter == "freeChlorine" }) else {
            return templates
        }

        guard let advisory = recentCompletedChlorineWaitAdvisory(for: test, recentHistory: recentHistory) else {
            return templates
        }

        return templates.filter { $0.targetParameter != "freeChlorine" } + [advisory]
    }

    private func recentCompletedChlorineWaitAdvisory(for test: PoolTest, recentHistory: [PoolTest]) -> TreatmentTemplate? {
        let now = Date()
        let completedChlorine = recentHistory
            .flatMap { $0.treatments }
            .filter { $0.isCompleted && $0.targetParameter == "freeChlorine" }
            .compactMap { treatment -> (Treatment, TimeInterval)? in
                guard let completedAt = treatment.completedAt else { return nil }
                guard test.date <= completedAt else { return nil }
                return (treatment, now.timeIntervalSince(completedAt))
            }
            .sorted { $0.1 < $1.1 }
            .first

        guard let (treatment, elapsed) = completedChlorine else { return nil }

        let waitSeconds = TimeInterval(chlorineRetestWaitMinutes(for: treatment.chemicalName) * 60)
        guard elapsed < waitSeconds else { return nil }

        let remainingMinutes = max(1, Int(ceil((waitSeconds - elapsed) / 60)))
        let expectedRise = treatment.expectedDelta > 0
            ? " It was expected to raise FC by about \(String(format: "%.1f", treatment.expectedDelta)) ppm."
            : ""

        return TreatmentTemplate(
            chemicalName: "Chlorine Still Circulating",
            actionDescription: "A recent chlorine dose is still mixing.",
            amount: 0,
            unit: "",
            instructions: "Wait about \(remainingMinutes) more minutes before adding more chlorine. Use the Next Pool Test card for testing timing.\(expectedRise) Unchecked or skipped chlorine cards are not counted as completed.",
            targetParameter: "freeChlorine",
            urgency: .advisory,
            expectedEffectParameter: "freeChlorine",
            expectedDelta: 0,
            effectDelayHours: 0,
            effectDurationHours: 4,
            doNotRepeatHours: 1
        )
    }

    private func suppressLowConfidenceOptionalTreatments(
        _ templates: [TreatmentTemplate],
        config: PoolConfiguration
    ) -> [TreatmentTemplate] {
        guard config.testMethod.shouldSuppressOptionalTreatments else {
            return templates
        }

        return templates.filter { $0.urgency != .optional }
    }

    private func suppressAcidTreatmentsWhenPHIsLowNormal(
        _ templates: [TreatmentTemplate],
        for test: PoolTest
    ) -> [TreatmentTemplate] {
        guard test.pH <= 7.4, !hasScaling(test) else {
            return templates
        }

        return templates.filter { !$0.isAcidTreatment }
    }

    // MARK: - Treatment Templates

    /// Recomputes a single treatment template for the given target parameter under the
    /// provided config. Used when the user swaps to a different chemical product so the
    /// dosing math reflects the new product's concentration.
    func proposedTreatmentTemplate(
        forTargetParameter targetParameter: String,
        test: PoolTest,
        config: PoolConfiguration
    ) -> TreatmentTemplate? {
        let readings = allReadings(for: test, config: config)
        guard let reading = readings.first(where: { $0.key == targetParameter }) else { return nil }
        guard let template = treatmentTemplate(for: reading, test: test, previousTest: nil, recentHistory: [], config: config) else {
            return nil
        }
        return suppressAcidTreatmentsWhenPHIsLowNormal([template], for: test).first
    }

    func repricedTreatmentTemplate(
        from treatment: Treatment,
        test: PoolTest,
        productID: ChemicalProductID,
        config: PoolConfiguration
    ) -> TreatmentTemplate? {
        let volume = config.volumeGallons
        let kGal = volume / 1000
        let globalPreference = treatment.globalPreferenceIdentifier.flatMap(ChemicalProductID.init(rawValue:))

        switch productID {
        case .liquidChlorine10, .liquidChlorine12_5, .trichlorTablets, .calHypoGranules, .dichlorGranules, .saltGenerator:
            guard treatment.targetParameter == "freeChlorine" else { return nil }
            let preference = ChlorinePreference(rawValue: productID.rawValue) ?? .liquidChlorine10
            let ppmIncrease = max(0, treatment.expectedDelta)
            let product = chlorineProduct(preference, volume: volume, ppmIncrease: ppmIncrease)
            let actionDescription = productID == .saltGenerator
                ? "Modest FC deficit with clear water can usually be corrected by generator output or run time"
                : treatment.actionDescription.replacingOccurrences(of: "Salt Chlorine Generator", with: product.name)
            return TreatmentTemplate(
                chemicalName: product.name,
                actionDescription: actionDescription,
                amount: product.amount,
                unit: product.unit,
                instructions: chlorineInstructions(for: product, test: test),
                targetParameter: treatment.targetParameter,
                urgency: treatment.urgency,
                expectedEffectParameter: treatment.expectedEffectParameter,
                expectedDelta: productID == .saltGenerator ? 0 : ppmIncrease,
                effectDelayHours: productID == .saltGenerator ? 4 : 1,
                effectDurationHours: treatment.effectDurationHours,
                doNotRepeatHours: productID == .saltGenerator ? 4 : chlorineDoNotRepeatHours(for: product.name),
                productID: product.id,
                globalPreferenceProductID: globalPreference,
                calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                wasDoseCapped: product.wasCapped
            )

        case .muriaticAcid31, .muriaticAcid20, .dryAcid:
            guard treatment.targetParameter == "pH" || treatment.targetParameter == "totalAlkalinity" else { return nil }
            let preference = PHDecreaserPreference(rawValue: productID.rawValue) ?? .muriaticAcid
            let pHDelta = max(0.2, abs(treatment.expectedDelta))
            let ounces = kGal * 6 * (pHDelta / 0.2)
            let product = pHDecreaserProduct(preference, ounces: ounces)
            return TreatmentTemplate(
                chemicalName: product.name,
                actionDescription: treatment.actionDescription,
                amount: product.amount,
                unit: product.unit,
                instructions: "\(product.instructions) Treatment goal is unchanged from the original plan.",
                targetParameter: treatment.targetParameter,
                urgency: treatment.urgency,
                expectedEffectParameter: treatment.expectedEffectParameter,
                expectedDelta: treatment.expectedDelta,
                effectDelayHours: treatment.effectDelayHours,
                effectDurationHours: treatment.effectDurationHours,
                doNotRepeatHours: 12,
                productID: product.id,
                globalPreferenceProductID: globalPreference,
                calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                wasDoseCapped: product.wasCapped
            )

        case .sodaAsh, .borax:
            guard treatment.targetParameter == "pH" else { return nil }
            let preference = PHIncreaserPreference(rawValue: productID.rawValue) ?? .sodaAsh
            let pHDelta = max(0.2, abs(treatment.expectedDelta))
            let product = pHIncreaserProduct(preference, ounces: kGal * 6 * (pHDelta / 0.2))
            return TreatmentTemplate(
                chemicalName: product.name,
                actionDescription: treatment.actionDescription,
                amount: product.amount,
                unit: product.unit,
                instructions: "\(product.instructions) Treatment goal is unchanged from the original plan.",
                targetParameter: treatment.targetParameter,
                urgency: treatment.urgency,
                expectedEffectParameter: treatment.expectedEffectParameter,
                expectedDelta: treatment.expectedDelta,
                effectDelayHours: treatment.effectDelayHours,
                effectDurationHours: treatment.effectDurationHours,
                doNotRepeatHours: 12,
                productID: product.id,
                globalPreferenceProductID: globalPreference,
                calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                wasDoseCapped: product.wasCapped
            )

        case .granularCYA, .liquidStabilizer:
            guard treatment.targetParameter == "cyanuricAcid" else { return nil }
            let preference = StabilizerPreference(rawValue: productID.rawValue) ?? .granularCYA
            let pounds = kGal * 0.5 * (max(0, treatment.expectedDelta) / 10)
            let product = stabilizerProduct(preference, pounds: pounds)
            return TreatmentTemplate(
                chemicalName: product.name,
                actionDescription: treatment.actionDescription,
                amount: product.amount,
                unit: product.unit,
                instructions: "\(product.instructions) Treatment goal is unchanged from the original plan.",
                targetParameter: treatment.targetParameter,
                urgency: treatment.urgency,
                expectedEffectParameter: treatment.expectedEffectParameter,
                expectedDelta: treatment.expectedDelta,
                effectDelayHours: product.id == .granularCYA ? 72 : 24,
                effectDurationHours: treatment.effectDurationHours,
                doNotRepeatHours: product.id == .granularCYA ? 168 : 72,
                productID: product.id,
                globalPreferenceProductID: globalPreference,
                calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                wasDoseCapped: product.wasCapped
            )

        case .bakingSoda, .calciumChloride:
            return nil
        }
    }

    private func treatmentTemplate(
        for reading: ChemicalReading,
        test: PoolTest,
        previousTest: PoolTest?,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> TreatmentTemplate? {
        let volume = config.volumeGallons
        let kGal = volume / 1000

        switch reading.key {
        case "pH":
            if reading.value < 7.0 {
                let targetPH = 7.2
                let oz = kGal * 6 * ((targetPH - reading.value) / 0.2)
                let product = pHIncreaserProduct(config.pHIncreaserPreference, ounces: oz)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Raise unsafe low pH into the safe range",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: "\(product.instructions) Retest before making any sanitizer or alkalinity adjustments.",
                    targetParameter: "pH",
                    urgency: .immediate,
                    expectedEffectParameter: "pH",
                    expectedDelta: targetPH - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 24,
                    doNotRepeatHours: 12,
                    productID: product.id,
                    globalPreferenceProductID: config.pHIncreaserPreference.productID,
                    calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                    calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                    wasDoseCapped: product.wasCapped
                )
            } else if reading.value < 7.2 {
                return TreatmentTemplate(
                    chemicalName: "Monitor pH",
                    actionDescription: "pH is low-normal; avoid adding acid and retest before adjusting.",
                    amount: 0,
                    unit: "",
                    instructions: "Do not lower pH. Keep circulation running and retest pH with a reliable kit before adding pH increaser unless it drops below 7.0.",
                    targetParameter: "pH",
                    urgency: .advisory,
                    expectedEffectParameter: "pH",
                    expectedDelta: 0,
                    effectDelayHours: 0,
                    effectDurationHours: 12,
                    doNotRepeatHours: 12
                )
            } else if shouldTreatHighPHWithAcid(reading.value, test: test, previousTest: previousTest, recentHistory: recentHistory) {
                let targetPH = reading.value <= 7.8 ? 7.6 : 7.5
                let oz = kGal * 6 * ((reading.value - targetPH) / 0.2)
                let product = pHDecreaserProduct(config.pHDecreaserPreference, ounces: oz)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: pHAcidActionDescription(for: test, recentHistory: recentHistory),
                    amount: product.amount,
                    unit: product.unit,
                    instructions: "\(product.instructions) Add this conservative dose, circulate, then retest pH before adding more. Avoid chasing alkalinity at the same time.",
                    targetParameter: "pH",
                    urgency: pHDecreaserUrgency(for: reading.value, test: test, previousTest: previousTest, recentHistory: recentHistory),
                    expectedEffectParameter: "pH",
                    expectedDelta: targetPH - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 24,
                    doNotRepeatHours: 12,
                    productID: product.id,
                    globalPreferenceProductID: config.pHDecreaserPreference.productID,
                    calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                    calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                    wasDoseCapped: product.wasCapped
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Monitor pH Trend",
                    actionDescription: "pH is currently acceptable, but elevated alkalinity may cause it to rise.",
                    amount: 0,
                    unit: "",
                    instructions: "Keep circulation running and watch the next pH result. Do not add acid unless pH reaches 7.8 or higher, pH keeps rising, or scaling appears.",
                    targetParameter: "pH",
                    urgency: .advisory,
                    expectedEffectParameter: "pH",
                    expectedDelta: 0,
                    effectDelayHours: 0,
                    effectDurationHours: 12,
                    doNotRepeatHours: 12
                )
            }

        case "freeChlorine":
            let targetRange = freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)
            if reading.value < targetRange.lowerBound {
                let target = chlorineCorrectionTarget(
                    for: test,
                    targetRange: targetRange,
                    recentHistory: recentHistory,
                    config: config
                )
                let ppmIncrease = max(0, target - reading.value)
                guard ppmIncrease > 0 else { return nil }
                if config.isSaltwater && config.chlorinePreference == .saltGenerator && !requiresSupplementalChlorine(test: test, target: target, recentHistory: recentHistory) {
                    let product = chlorineProduct(.saltGenerator, volume: volume, ppmIncrease: ppmIncrease)
                    return TreatmentTemplate(
                        chemicalName: product.name,
                        actionDescription: "Modest FC deficit with clear water can usually be corrected by generator output or run time",
                        amount: product.amount,
                        unit: product.unit,
                        instructions: product.instructions,
                        targetParameter: "freeChlorine",
                        urgency: .optional,
                        expectedEffectParameter: "freeChlorine",
                        expectedDelta: 0,
                        effectDelayHours: 4,
                        effectDurationHours: 24,
                        doNotRepeatHours: 4,
                        productID: product.id,
                        globalPreferenceProductID: config.chlorinePreference.productID
                    )
                }
                let chlorinePreference = supplementalChlorinePreference(for: test, config: config, recentHistory: recentHistory)
                let product = chlorineProduct(
                    chlorinePreference,
                    volume: volume,
                    ppmIncrease: ppmIncrease
                )
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: chlorineActionDescription(for: test, target: target, recentHistory: recentHistory, config: config),
                    amount: product.amount,
                    unit: product.unit,
                    instructions: chlorineInstructions(for: product, test: test),
                    targetParameter: "freeChlorine",
                    urgency: chlorineTreatmentUrgency(for: test, target: target, recentHistory: recentHistory, config: config),
                    expectedEffectParameter: "freeChlorine",
                    expectedDelta: target - reading.value,
                    effectDelayHours: 1,
                    effectDurationHours: 24,
                    doNotRepeatHours: chlorineDoNotRepeatHours(for: product.name),
                    productID: product.id,
                    globalPreferenceProductID: config.chlorinePreference.productID,
                    calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                    calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                    wasDoseCapped: product.wasCapped
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Remove Chlorine Source",
                    actionDescription: "Reduce free chlorine — it's elevated",
                    amount: 0,
                    unit: "",
                    instructions: "Allow levels to drop naturally by running pool in sunlight without adding chlorine. Retest in 24 hours. If urgent, use a chlorine neutralizer (sodium thiosulfate).",
                    targetParameter: "freeChlorine",
                    urgency: reading.status.treatmentUrgency ?? .optional,
                    expectedEffectParameter: "freeChlorine",
                    expectedDelta: 0,
                    effectDelayHours: 24,
                    effectDurationHours: 24,
                    doNotRepeatHours: 24
                )
            }

        case "totalAlkalinity":
            if reading.value < 70 {
                if shouldConfirmPossibleDilutionBeforeCorrection(reading: reading, test: test, config: config) {
                    return possibleDilutionRetestTemplate(for: "Total Alkalinity")
                }
                let alkalinityIncrease = 80 - reading.value
                // Sodium bicarbonate raises TA by about 10 ppm with 1.4 lb per 10,000 gallons.
                let lbs = (volume / 10_000) * 1.4 * (alkalinityIncrease / 10)
                return TreatmentTemplate(
                    chemicalName: config.alkalinityIncreaserPreference.displayName,
                    actionDescription: "Raise low alkalinity so pH is less likely to swing",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Add directly to pool with pump running. For large doses, split into two additions 4-6 hours apart. Retest pH and alkalinity next day.",
                    targetParameter: "totalAlkalinity",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "totalAlkalinity",
                    expectedDelta: alkalinityIncrease,
                    effectDelayHours: 12,
                    effectDurationHours: 48,
                    doNotRepeatHours: 24,
                    productID: config.alkalinityIncreaserPreference.productID,
                    globalPreferenceProductID: config.alkalinityIncreaserPreference.productID,
                    calculatedDoseBeforeCap: lbs.rounded(toPlaces: 1),
                    calculatedDoseBeforeCapUnit: "lbs"
                )
            } else if shouldTreatHighAlkalinityWithAcid(reading.value, test: test, previousTest: previousTest) {
                let flOz = kGal * 0.8 * ((reading.value - 120) / 10)
                let product = pHDecreaserProduct(config.pHDecreaserPreference, ounces: flOz)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Lower TA only because pH is high or drifting upward",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: "Use the acid/aeration process: add this conservative dose carefully, circulate, then aerate to raise pH without restoring TA. Retest pH in 4 hours and TA after circulation before adding more.",
                    targetParameter: "totalAlkalinity",
                    urgency: .optional,
                    expectedEffectParameter: "totalAlkalinity",
                    expectedDelta: 120 - reading.value,
                    effectDelayHours: 6,
                    effectDurationHours: 48,
                    doNotRepeatHours: 24,
                    productID: product.id,
                    globalPreferenceProductID: config.pHDecreaserPreference.productID,
                    calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                    calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                    wasDoseCapped: product.wasCapped
                )
            } else {
                let action = test.pH >= 7.8
                    ? "TA is elevated; handle pH with the active pH recommendation rather than adding a separate TA acid dose."
                    : "pH is currently acceptable, but elevated alkalinity may cause it to rise."
                return TreatmentTemplate(
                    chemicalName: test.pH >= 7.8 ? "Monitor Elevated Alkalinity" : "Monitor pH Trend",
                    actionDescription: action,
                    amount: 0,
                    unit: "",
                    instructions: "Do not add acid solely for TA while pH is in or near the safe range. Watch for repeated pH rise or scaling; correct TA only if pH keeps drifting upward or scaling appears.",
                    targetParameter: "totalAlkalinity",
                    urgency: .advisory,
                    expectedEffectParameter: "totalAlkalinity",
                    expectedDelta: 0,
                    effectDelayHours: 0,
                    effectDurationHours: 48,
                    doNotRepeatHours: 24
                )
            }

        case "calciumHardness":
            let acceptable = calciumAcceptableRange(surface: config.surfaceType)
            if reading.value < acceptable.lowerBound {
                if shouldConfirmPossibleDilutionBeforeCorrection(reading: reading, test: test, config: config) {
                    return possibleDilutionRetestTemplate(for: "Calcium Hardness")
                }
                let lbs = kGal * 1.25 * ((acceptable.lowerBound - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: "Calcium Hardness Increaser (\(config.calciumIncreaserPreference.displayName))",
                    actionDescription: "Raise clearly low calcium hardness to reduce corrosion risk",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Pre-dissolve in water; this releases heat, so use caution. Add slowly around pool perimeter. Retest after full circulation.",
                    targetParameter: "calciumHardness",
                    urgency: .optional,
                    expectedEffectParameter: "calciumHardness",
                    expectedDelta: acceptable.lowerBound - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 72,
                    doNotRepeatHours: 24,
                    productID: config.calciumIncreaserPreference.productID,
                    globalPreferenceProductID: config.calciumIncreaserPreference.productID,
                    calculatedDoseBeforeCap: lbs.rounded(toPlaces: 1),
                    calculatedDoseBeforeCapUnit: "lbs"
                )
            } else if reading.value > acceptable.upperBound && (test.pH >= 7.8 || hasScaling(test)) {
                return TreatmentTemplate(
                    chemicalName: "Manage Scaling Risk",
                    actionDescription: "High calcium with high pH or scaling can deposit scale.",
                    amount: 0,
                    unit: "",
                    instructions: "Keep pH in the lower safe range, brush scaling areas, and avoid cal-hypo until calcium has room. Consider partial water replacement only if hardness remains high after retesting.",
                    targetParameter: "calciumHardness",
                    urgency: .optional,
                    expectedEffectParameter: "calciumHardness",
                    expectedDelta: 0,
                    effectDelayHours: 0,
                    effectDurationHours: 72,
                    doNotRepeatHours: 24
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Monitor Calcium Hardness",
                    actionDescription: "Calcium hardness is imperfect but not driving an immediate problem.",
                    amount: 0,
                    unit: "",
                    instructions: "Do not add calcium or drain water unless a reliable retest confirms a clear problem or scaling/corrosion symptoms appear.",
                    targetParameter: "calciumHardness",
                    urgency: .advisory,
                    expectedEffectParameter: "calciumHardness",
                    expectedDelta: 0,
                    effectDelayHours: 0,
                    effectDurationHours: 72,
                    doNotRepeatHours: 24
                )
            }

        case "cyanuricAcid":
            if reading.value < 30 {
                if shouldConfirmPossibleDilutionBeforeCorrection(reading: reading, test: test, config: config) {
                    return possibleDilutionRetestTemplate(for: "CYA")
                }
                if config.testMethod == .testStrips || test.testMethod == .testStrips {
                    return TreatmentTemplate(
                        chemicalName: "Confirm CYA",
                        actionDescription: "Low CYA from strips should be confirmed before adding stabilizer.",
                        amount: 0,
                        unit: "",
                        instructions: "Retest CYA with a reliable drop test or pool-store test before adding stabilizer. If confirmed below 30 ppm, raise toward about 40 ppm.",
                        targetParameter: "cyanuricAcid",
                        urgency: .advisory,
                        expectedEffectParameter: "cyanuricAcid",
                        expectedDelta: 0,
                        effectDelayHours: 0,
                        effectDurationHours: 168,
                        doNotRepeatHours: 72
                    )
                }

                let lbs = kGal * 0.5 * ((40 - reading.value) / 10)
                let product = stabilizerProduct(config.stabilizerPreference, pounds: lbs)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Raise cyanuric acid to protect chlorine from UV",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: "\(product.instructions) Confirm low CYA with the most reliable test available before repeating; stabilizer is slow to leave the pool.",
                    targetParameter: "cyanuricAcid",
                    urgency: config.testMethod == .testStrips ? .advisory : .optional,
                    expectedEffectParameter: "cyanuricAcid",
                    expectedDelta: 40 - reading.value,
                    effectDelayHours: 72,
                    effectDurationHours: 168,
                    doNotRepeatHours: product.id == .granularCYA ? 168 : 72,
                    productID: product.id,
                    globalPreferenceProductID: config.stabilizerPreference.productID,
                    calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                    calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                    wasDoseCapped: product.wasCapped
                )
            } else if reading.value >= 90 {
                return TreatmentTemplate(
                    chemicalName: "Partial Water Replacement",
                    actionDescription: "Dilute very high CYA so chlorine can be maintained",
                    amount: Double(Int(volume * 0.30)),
                    unit: "gallons to drain/refill",
                    instructions: "Drain 30% of pool water, refill with fresh water, and retest CYA after circulation. Avoid dichlor and trichlor; CYA cannot be chemically removed.",
                    targetParameter: "cyanuricAcid",
                    urgency: .recommended,
                    expectedEffectParameter: "cyanuricAcid",
                    expectedDelta: 0,
                    effectDelayHours: 24,
                    effectDurationHours: 168,
                    doNotRepeatHours: 72
                )
            }
            return nil

        case "saltLevel":
            if reading.value < 2700 {
                if shouldConfirmPossibleDilutionBeforeCorrection(reading: reading, test: test, config: config) {
                    return possibleDilutionRetestTemplate(for: "Salt")
                }
                let pounds = volume * (3200 - reading.value) / 12000
                return TreatmentTemplate(
                    chemicalName: "Pool Salt",
                    actionDescription: "Raise salt into the chlorinator operating range",
                    amount: pounds.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Broadcast salt across the shallow end with the pump running and brush until dissolved. Do not add through the skimmer. Retest after 24 hours of circulation.",
                    targetParameter: "saltLevel",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "saltLevel",
                    expectedDelta: 3200 - reading.value,
                    effectDelayHours: 24,
                    effectDurationHours: 168,
                    doNotRepeatHours: 24
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Dilute Salt",
                    actionDescription: "Salt is above the chlorinator operating range",
                    amount: Double(Int(volume * 0.10)),
                    unit: "gallons to drain/refill",
                    instructions: "Replace about 10% of the water, circulate, and retest salt before repeating. Check the salt cell manual for its exact high-salt limit.",
                    targetParameter: "saltLevel",
                    urgency: .optional,
                    expectedEffectParameter: "saltLevel",
                    expectedDelta: 0,
                    effectDelayHours: 24,
                    effectDurationHours: 168,
                    doNotRepeatHours: 24
                )
            }

        default:
            return nil
        }
    }

    private func chlorineCorrectionTarget(
        for test: PoolTest,
        targetRange: ClosedRange<Double>,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> Double {
        if hasVisibleAlgae(test) {
            return min(max(targetRange.upperBound, freeChlorineShockLevel(cyanuricAcid: test.cyanuricAcid)), 30)
        }
        if shouldUseUpperChlorineTarget(for: test, recentHistory: recentHistory) {
            return targetRange.upperBound
        }
        let midpoint = freeChlorineTargetMidpoint(cyanuricAcid: test.cyanuricAcid)
        let demandScore = chlorineDemandScore(for: test)
        if demandScore >= 6 {
            return targetRange.upperBound
        }
        if demandScore >= 3 {
            return midpoint + ((targetRange.upperBound - midpoint) * 0.25)
        }
        return midpoint
    }

    private func shouldUseUpperChlorineTarget(for test: PoolTest, recentHistory: [PoolTest]) -> Bool {
        hasCloudyWater(test)
            || hasStrongChlorineSmell(test)
            || test.combinedChlorine > 0.5
            || (hasFoam(test) && test.freeChlorine < freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid))
            || hasRapidChlorineLoss(current: test, recentHistory: recentHistory)
            || hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)
    }

    private func hasRapidChlorineLoss(current test: PoolTest, recentHistory: [PoolTest]) -> Bool {
        guard let previous = recentHistory.first else { return false }
        let drop = previous.freeChlorine - test.freeChlorine
        let completedRecentChlorine = recentHistory
            .prefix(3)
            .flatMap { $0.treatments }
            .contains { $0.isCompleted && $0.targetParameter == "freeChlorine" }

        return completedRecentChlorine && drop >= 2.0 && test.freeChlorine < freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound
    }

    private func hasRepeatedFailedChlorineCorrections(current test: PoolTest, recentHistory: [PoolTest]) -> Bool {
        let completedChlorineDoses = recentHistory
            .prefix(5)
            .flatMap { $0.treatments }
            .filter { $0.isCompleted && !$0.isSkipped && $0.targetParameter == "freeChlorine" }
            .count
        let repeatedLowFCReadings = recentHistory
            .prefix(5)
            .filter { historicalTest in
                historicalTest.freeChlorine < freeChlorineMinimum(cyanuricAcid: historicalTest.cyanuricAcid)
                    && !hasVisibleAlgae(historicalTest)
                    && !hasCloudyWater(historicalTest)
            }
            .count

        return completedChlorineDoses >= 2
            && repeatedLowFCReadings >= 2
            && test.freeChlorine < freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
    }

    private func preferredChlorinePreference(for test: PoolTest, config: PoolConfiguration) -> ChlorinePreference {
        if config.chlorinePreference == .saltGenerator {
            return .saltGenerator
        }
        if test.cyanuricAcid >= 40 {
            if config.chlorinePreference == .liquidChlorine10 || config.chlorinePreference == .liquidChlorine12_5 {
                return config.chlorinePreference
            }
        }

        if test.cyanuricAcid >= 60 {
            if config.chlorinePreference == .liquidChlorine10 || config.chlorinePreference == .liquidChlorine12_5 {
                return config.chlorinePreference
            }

            let calciumRoom = test.calciumHardness < 300
            return calciumRoom ? .calHypo : .liquidChlorine10
        }

        if test.cyanuricAcid > 50 && (config.chlorinePreference == .dichlor || config.chlorinePreference == .tablets) {
            return .liquidChlorine10
        }

        if config.chlorinePreference == .tablets
            && test.freeChlorine < freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound {
            return .liquidChlorine10
        }

        return config.chlorinePreference
    }

    private func supplementalChlorinePreference(for test: PoolTest, config: PoolConfiguration, recentHistory: [PoolTest]) -> ChlorinePreference {
        if config.chlorinePreference == .saltGenerator {
            if config.lastNonSaltChlorinePreference.isSaltCompatibleManualProduct {
                return config.lastNonSaltChlorinePreference
            }
            return .liquidChlorine10
        }
        return preferredChlorinePreference(for: test, config: config)
    }

    private func requiresSupplementalChlorine(test: PoolTest, target: Double, recentHistory: [PoolTest]) -> Bool {
        let minimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        return hasVisibleAlgae(test)
            || hasCloudyWater(test)
            || hasStrongChlorineSmell(test)
            || test.combinedChlorine > 0.5
            || test.freeChlorine < minimum * 0.5
            || target >= freeChlorineShockLevel(cyanuricAcid: test.cyanuricAcid)
            || chlorineDemandScore(for: test) >= 3
            || hasRapidChlorineLoss(current: test, recentHistory: recentHistory)
            || hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory)
    }

    private func chlorineActionDescription(
        for test: PoolTest,
        target: Double,
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> String {
        let urgency = chlorineTreatmentUrgency(for: test, target: target, recentHistory: recentHistory, config: config)
        if urgency == .optional {
            return "Maintenance top-off toward \(formatRangeBound(target)) ppm"
        }
        if target >= freeChlorineShockLevel(cyanuricAcid: test.cyanuricAcid) {
            return "Raise free chlorine to recovery level based on CYA"
        }
        if config.isSaltwater && config.chlorinePreference == .saltGenerator {
            return "Supplemental chlorine is needed because the FC deficit or water condition needs faster recovery than the salt generator can provide"
        }
        return "Raise free chlorine toward \(formatRangeBound(target)) ppm"
    }

    private func chlorineTreatmentUrgency(for test: PoolTest, target: Double, recentHistory: [PoolTest], config: PoolConfiguration) -> TreatmentUrgency {
        let minimum = freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
        let maintenanceFloor = max(0, minimum - 0.5)
        let targetLower = freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid).lowerBound
        if hasVisibleAlgae(test) || hasCloudyWater(test) || target >= freeChlorineShockLevel(cyanuricAcid: test.cyanuricAcid) {
            return .immediate
        }
        if hasRapidChlorineLoss(current: test, recentHistory: recentHistory) || hasRepeatedFailedChlorineCorrections(current: test, recentHistory: recentHistory) {
            return .recommended
        }
        if test.freeChlorine < minimum * 0.5 {
            return .immediate
        }
        if test.freeChlorine < maintenanceFloor {
            return .recommended
        }
        if test.freeChlorine < targetLower && chlorineDemandScore(for: test) >= 3 {
            return .recommended
        }
        if isStablePoolContext(test, previousTest: recentHistory.first, recentHistory: recentHistory, config: config) {
            return .optional
        }
        return .optional
    }

    private func chlorineDemandScore(for test: PoolTest) -> Int {
        test.resolvedPoolConditions.chlorineDemandContribution
    }

    private func waterChangeScore(for test: PoolTest) -> Int {
        test.resolvedPoolConditions.waterChangeContribution
    }

    private func chlorineInstructions(for product: ChemicalProduct, test: PoolTest) -> String {
        var parts = [product.instructions]

        if product.name.contains("Dichlor") || product.name.contains("Tablets") {
            parts.append("This also raises CYA; avoid repeated use if CYA is already above 50.")
        }

        if test.cyanuricAcid >= 60 {
            parts.append("Because CYA is elevated, liquid chlorine is preferred; use stabilized chlorine only as a backup.")
        }

        if product.name.contains("Calcium") || product.name.contains("Granules") {
            parts.append("Cal-hypo adds calcium, so avoid repeated use when calcium hardness is high or scaling is present.")
        }

        let waitMinutes = chlorineRetestWaitMinutes(for: product.name)
        let needsVerification = hasVisibleAlgae(test)
            || hasCloudyWater(test)
            || hasStrongChlorineSmell(test)
            || test.combinedChlorine > 0.5
            || test.freeChlorine < freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid) * 0.5
        if needsVerification {
            parts.append("Retest FC and CC in \(waitMinutes) minutes.")
        } else {
            parts.append("Circulate for \(waitMinutes) minutes before swimming.")
        }

        return parts.joined(separator: " ")
    }

    private func chlorineDoNotRepeatHours(for chemicalName: String) -> Int {
        chlorineRetestWaitMinutes(for: chemicalName) <= 60 ? 1 : 4
    }

    private func chlorineRetestWaitMinutes(for chemicalName: String) -> Int {
        if chemicalName.contains("Liquid Chlorine") {
            return 60
        }
        if chemicalName.contains("Granules") || chemicalName.contains("Dichlor") {
            return 240
        }
        if chemicalName.contains("Tablets") {
            return 1440
        }
        return 60
    }

    private func shouldConfirmPossibleDilutionBeforeCorrection(
        reading: ChemicalReading,
        test: PoolTest,
        config: PoolConfiguration
    ) -> Bool {
        guard waterChangeScore(for: test) >= 2 else { return false }

        switch reading.key {
        case "totalAlkalinity":
            return test.totalAlkalinity >= 50
        case "calciumHardness":
            return test.calciumHardness >= calciumAcceptableRange(surface: config.surfaceType).lowerBound - 50
        case "cyanuricAcid":
            return test.cyanuricAcid >= 15
        case "saltLevel":
            return test.saltLevel.map { $0 >= 2400 } ?? false
        default:
            return false
        }
    }

    private func possibleDilutionRetestTemplate(for parameter: String) -> TreatmentTemplate {
        TreatmentTemplate(
            chemicalName: "Confirm \(parameter)",
            actionDescription: "\(parameter) may be lower from recent water addition or rain.",
            amount: 0,
            unit: "",
            instructions: "Recent water addition or rain may explain this lower value. Retest before making a large correction unless the value is unsafe or symptoms appear.",
            targetParameter: "poolConditions",
            urgency: .advisory,
            expectedEffectParameter: parameter,
            expectedDelta: 0,
            effectDelayHours: 0,
            effectDurationHours: 24,
            doNotRepeatHours: 24
        )
    }

    private func advisoryTemplates(
        for test: PoolTest,
        previousTest: PoolTest?,
        config: PoolConfiguration
    ) -> [TreatmentTemplate] {
        var templates: [TreatmentTemplate] = []
        let chlorineDemand = chlorineDemandScore(for: test)
        let waterChange = waterChangeScore(for: test)

        let targetRange = freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)
        if test.totalChlorine + 0.3 >= test.freeChlorine
            && test.combinedChlorine > 0.5
            && test.freeChlorine >= targetRange.lowerBound {
            let target = test.combinedChlorine >= 1.0 ? targetRange.upperBound : max(targetRange.lowerBound, test.freeChlorine + 1.5)
            let product = chlorineProduct(
                supplementalChlorinePreference(for: test, config: config, recentHistory: []),
                volume: config.volumeGallons,
                ppmIncrease: max(0, target - test.freeChlorine)
            )
            templates.append(TreatmentTemplate(
                chemicalName: product.name,
                actionDescription: "Oxidize combined chlorine above 0.5 ppm",
                amount: product.amount,
                unit: product.unit,
                instructions: "\(product.instructions) Open the cover if present, circulate well, and retest FC and CC. CC at or below 0.5 is acceptable; above 1.0 needs stronger attention.",
                targetParameter: "freeChlorine",
                urgency: test.combinedChlorine >= 1.0 ? .recommended : .optional,
                expectedEffectParameter: "combinedChlorine",
                expectedDelta: -test.combinedChlorine,
                effectDelayHours: 2,
                effectDurationHours: 24,
                doNotRepeatHours: 4,
                productID: product.id,
                globalPreferenceProductID: config.chlorinePreference.productID,
                calculatedDoseBeforeCap: product.calculatedAmountBeforeCap,
                calculatedDoseBeforeCapUnit: product.calculatedUnitBeforeCap,
                wasDoseCapped: product.wasCapped
            ))
        }

        if config.hasCover
            || test.freeChlorine < freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid)
            || hasFoam(test)
            || hasStrongChlorineSmell(test) {
            templates.append(TreatmentTemplate(
                chemicalName: "Open Cover for Gas Exchange",
                actionDescription: "Covered pools can accumulate chloramines and organics when FC runs low.",
                amount: 0,
                unit: "",
                instructions: "Open the cover periodically, circulate the pool, and avoid letting FC sit near the minimum. Aim for the upper half of the CYA-adjusted FC range.",
                targetParameter: "cover",
                urgency: .advisory
            ))
        }

        if test.cyanuricAcid >= 50 && test.cyanuricAcid < 90 {
            templates.append(TreatmentTemplate(
                chemicalName: "Maintain Higher FC for Current CYA",
                actionDescription: "Current CYA is manageable, but it requires a higher ongoing FC target.",
                amount: 0,
                unit: "",
                instructions: "Maintain FC around \(freeChlorineIdealRangeLabel(cyanuricAcid: test.cyanuricAcid)). Avoid dichlor and trichlor, which add more CYA. Dilution is only needed if CYA keeps rising or the higher FC target is impractical.",
                targetParameter: "cyanuricAcid",
                urgency: .advisory,
                doNotRepeatHours: 72
            ))
        } else if test.cyanuricAcid > 50 && (config.chlorinePreference == .dichlor || config.chlorinePreference == .tablets) {
            templates.append(TreatmentTemplate(
                chemicalName: "Avoid Stabilized Chlorine",
                actionDescription: "Dichlor and trichlor add CYA, which is already elevated.",
                amount: 0,
                unit: "",
                instructions: "Use liquid chlorine when CYA is adequate or high. Use cal-hypo only if calcium hardness has room.",
                targetParameter: "cyanuricAcid",
                urgency: .advisory,
                doNotRepeatHours: 72
            ))
        }

        if hasFoam(test) && test.freeChlorine >= freeChlorineMinimum(cyanuricAcid: test.cyanuricAcid) && test.combinedChlorine <= 0.5 {
            templates.append(TreatmentTemplate(
                chemicalName: "Monitor Foam",
                actionDescription: "Foam without low sanitizer or high CC is not automatically a chemical emergency.",
                amount: 0,
                unit: "",
                instructions: "Keep circulation and filtration running. If foam persists or CC rises above 0.5, oxidize and retest.",
                targetParameter: "visualIndicators",
                urgency: .advisory
            ))
        }

        if chlorineDemand >= 3 && !templates.contains(where: { $0.chemicalName == "Increased Chlorine Demand" }) {
            templates.append(TreatmentTemplate(
                chemicalName: "Increased Chlorine Demand",
                actionDescription: "Recent pool conditions may increase chlorine demand.",
                amount: 0,
                unit: "",
                instructions: "Recent pool conditions may increase chlorine demand. The chlorine recommendation accounts for swimming, rain, debris, cover time, and cleaning activity where provided.",
                targetParameter: "poolConditions",
                urgency: .advisory,
                doNotRepeatHours: 24
            ))
        }

        if waterChange >= 3 && !templates.contains(where: { $0.chemicalName == "Possible Dilution" }) {
            let backwashed = test.resolvedPoolConditions.backwashedFilter == .yes
            let actionDescription = backwashed
                ? "Recent backwashing or water replacement may dilute chemistry."
                : "Recent water addition or rain may have changed chemistry."
            let dilutedValues = config.isSaltwater ? "stabilizer, hardness, alkalinity, salt, and chlorine" : "stabilizer, hardness, alkalinity, and chlorine"
            let instructions = backwashed
                ? "Backwashing removes pool water and replacement water may affect \(dilutedValues). Retest before making large corrections unless values are unsafe."
                : "Recent water addition or rain may affect \(dilutedValues). Retest before making large corrections unless values are unsafe."
            templates.append(TreatmentTemplate(
                chemicalName: "Possible Dilution",
                actionDescription: actionDescription,
                amount: 0,
                unit: "",
                instructions: instructions,
                targetParameter: "poolConditions",
                urgency: .advisory,
                doNotRepeatHours: 24
            ))
        }

        return templates
    }

    private func chlorineProduct(
        _ preference: ChlorinePreference,
        volume: Double,
        ppmIncrease: Double
    ) -> ChemicalProduct {
        switch preference {
        case .saltGenerator:
            return ChemicalProduct(
                id: .saltGenerator,
                amount: 0,
                unit: "",
                instructions: "Increase salt generator output or extend pump/generator run time, then verify FC after the adjustment. Precise FC production depends on the generator capacity and run schedule."
            )
        case .tablets:
            return ChemicalProduct(
                id: .trichlorTablets,
                amount: 1,
                unit: "dose per label",
                instructions: "Use tablets in a floater, feeder, or chlorinator for maintenance according to the product label. Tablets dissolve slowly, so for an urgent free-chlorine correction use liquid chlorine or chlorine granules instead."
            )
        case .calHypo:
            let pounds = (volume / 1000) * 0.13 * ppmIncrease
            return ChemicalProduct(
                id: .calHypoGranules,
                amount: pounds.rounded(toPlaces: 2),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water. Add to the pool at dusk with the pump running. Keep swimmers out until free chlorine drops below 4 ppm."
            )
        case .liquidChlorine10:
            let gallons = ppmIncrease * volume / 10000 / 10
            return ChemicalProduct(
                id: .liquidChlorine10,
                amount: gallons.roundedLiquidChlorineDose(),
                unit: "gal",
                instructions: "Pour slowly in front of a return jet at dusk with the pump running. Brush and circulate, then retest free chlorine after 30-60 minutes."
            )
        case .liquidChlorine12_5:
            let gallons = ppmIncrease * volume / 10000 / 12.5
            return ChemicalProduct(
                id: .liquidChlorine12_5,
                amount: gallons.roundedLiquidChlorineDose(),
                unit: "gal",
                instructions: "Pour slowly in front of a return jet at dusk with the pump running. Brush and circulate, then retest free chlorine after 30-60 minutes."
            )
        case .dichlor:
            let pounds = (volume / 1000) * 0.085 * ppmIncrease
            return ChemicalProduct(
                id: .dichlorGranules,
                amount: pounds.rounded(toPlaces: 2),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water and add with the pump running. Dichlor also adds CYA, so avoid repeated use when stabilizer is already high."
            )
        }
    }

    private func pHIncreaserProduct(_ preference: PHIncreaserPreference, ounces: Double) -> ChemicalProduct {
        switch preference {
        case .sodaAsh:
            return ChemicalProduct(
                id: .sodaAsh,
                amount: (ounces / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water. Add solution with the pump running. Retest pH in 4-6 hours."
            )
        case .borax:
            return ChemicalProduct(
                id: .borax,
                amount: ((ounces * 1.9) / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Add slowly with the pump running, brushing any settled product. Borax has less impact on alkalinity than soda ash. Retest pH in 4-6 hours."
            )
        }
    }

    private func pHDecreaserProduct(_ preference: PHDecreaserPreference, ounces: Double) -> ChemicalProduct {
        switch preference {
        case .muriaticAcid:
            let cappedOunces = conservativeSingleLiquidAcidDose(fluidOunces: ounces)
            let dose = practicalLiquidAcidDose(fluidOunces: cappedOunces)
            let uncappedDose = practicalLiquidAcidDose(fluidOunces: ounces)
            return ChemicalProduct(
                id: .muriaticAcid31,
                amount: dose.amount,
                unit: dose.unit,
                instructions: "Add slowly to the deep end with the pump running. Never pre-mix with other chemicals. Retest pH in 4 hours before adding more.",
                calculatedAmountBeforeCap: uncappedDose.amount,
                calculatedUnitBeforeCap: uncappedDose.unit,
                wasCapped: cappedOunces < ounces
            )
        case .lowFumeMuriaticAcid:
            let lowFumeOunces = ounces * (31.45 / 20.0)
            let cappedOunces = conservativeSingleLiquidAcidDose(fluidOunces: lowFumeOunces)
            let dose = practicalLiquidAcidDose(fluidOunces: cappedOunces)
            let uncappedDose = practicalLiquidAcidDose(fluidOunces: lowFumeOunces)
            return ChemicalProduct(
                id: .muriaticAcid20,
                amount: dose.amount,
                unit: dose.unit,
                instructions: "Add slowly to the deep end with the pump running. Low-fume acid is weaker than 31.45% muriatic acid, so it requires more liquid volume for the same pH change. Retest pH in 4 hours before adding more.",
                calculatedAmountBeforeCap: uncappedDose.amount,
                calculatedUnitBeforeCap: uncappedDose.unit,
                wasCapped: cappedOunces < lowFumeOunces
            )
        case .dryAcid:
            let dryAcidOunces = dryAcidOuncesEquivalent(toMuriaticAcid31FluidOunces: ounces)
            let cappedOunces = conservativeSingleDryAcidDose(ounces: dryAcidOunces)
            return ChemicalProduct(
                id: .dryAcid,
                amount: (cappedOunces / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water and add slowly with the pump running. Dry acid adds sulfate over time, so avoid using it as a frequent large-dose product unless it is the product you intentionally maintain. Retest pH in 4 hours before adding more.",
                calculatedAmountBeforeCap: (dryAcidOunces / 16).rounded(toPlaces: 1),
                calculatedUnitBeforeCap: "lbs",
                wasCapped: cappedOunces < dryAcidOunces
            )
        }
    }

    private func dryAcidOuncesEquivalent(toMuriaticAcid31FluidOunces fluidOunces: Double) -> Double {
        max(0, fluidOunces) * 0.30
    }

    private func conservativeSingleLiquidAcidDose(fluidOunces: Double) -> Double {
        min(max(0, fluidOunces), 256)
    }

    private func conservativeSingleDryAcidDose(ounces: Double) -> Double {
        min(max(0, ounces), 256)
    }

    private func practicalLiquidAcidDose(fluidOunces: Double) -> (amount: Double, unit: String) {
        let ounces = max(0, fluidOunces)

        if ounces < 32 {
            return (ounces.rounded(toPlaces: ounces < 10 ? 1 : 0), "fl oz")
        }

        if ounces < 128 {
            return (((ounces / 32) * 2).rounded() / 2, "qt")
        }

        return ((ounces / 128).rounded(toPlaces: 1), "gal")
    }

    private func stabilizerProduct(_ preference: StabilizerPreference, pounds: Double) -> ChemicalProduct {
        switch preference {
        case .granularCYA:
            return ChemicalProduct(
                id: .granularCYA,
                amount: pounds.rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Place stabilizer in a sock or mesh bag in front of a return jet with the pump running. Do not leave undissolved stabilizer sitting in the skimmer basket. It can take up to a week to fully register on tests."
            )
        case .liquidConditioner:
            return ChemicalProduct(
                id: .liquidStabilizer,
                amount: (pounds * 0.96).rounded(toPlaces: 1),
                unit: "gal",
                instructions: "Add according to the product label for the CYA equivalent shown. Liquid conditioner usually registers faster than granular stabilizer, but retest after circulation."
            )
        }
    }

    // MARK: - Helpers

    private func trend(current: Double, previous: Double) -> ChemicalReading.Trend {
        let delta = current - previous
        if abs(delta) < 0.05 { return .stable }
        return delta > 0 ? .rising : .falling
    }
}

struct RecommendationConfidenceInput {
    let hasChemistryData: Bool
    let hasPoolConditions: Bool
    let hasVisualIndicators: Bool
    let hasRecentHistory: Bool
    let hasCompletedTreatmentHistory: Bool
    let chlorineDemandScore: Int
    let waterChangeScore: Int
}

private struct ChemicalProduct {
    let id: ChemicalProductID
    let name: String
    let amount: Double
    let unit: String
    let instructions: String
    let calculatedAmountBeforeCap: Double
    let calculatedUnitBeforeCap: String
    let wasCapped: Bool

    init(
        id: ChemicalProductID,
        amount: Double,
        unit: String,
        instructions: String,
        calculatedAmountBeforeCap: Double? = nil,
        calculatedUnitBeforeCap: String? = nil,
        wasCapped: Bool = false
    ) {
        self.id = id
        self.name = id.displayName
        self.amount = amount
        self.unit = unit
        self.instructions = instructions
        self.calculatedAmountBeforeCap = calculatedAmountBeforeCap ?? amount
        self.calculatedUnitBeforeCap = calculatedUnitBeforeCap ?? unit
        self.wasCapped = wasCapped
    }
}

// MARK: - Treatment Template (value type for rule engine output)

struct TreatmentTemplate {
    var chemicalName: String
    var actionDescription: String
    var amount: Double
    var unit: String
    var instructions: String
    var targetParameter: String
    var urgency: TreatmentUrgency
    var minutesBeforeNext: Int = 0
    var sortOrder: Int = 0
    var expectedEffectParameter: String = ""
    var expectedDelta: Double = 0
    var effectDelayHours: Int = 0
    var effectDurationHours: Int = 0
    var doNotRepeatHours: Int = 0
    var productID: ChemicalProductID?
    var globalPreferenceProductID: ChemicalProductID?
    var calculatedDoseBeforeCap: Double = 0
    var calculatedDoseBeforeCapUnit: String = ""
    var wasDoseCapped: Bool = false

    var sequencePriority: Int {
        if urgency == .advisory { return 8 }

        switch targetParameter {
        case "pH":
            return urgency == .immediate ? 0 : 4
        case "freeChlorine":
            return urgency == .immediate ? 1 : 3
        case "visualIndicators":
            return 2
        case "totalAlkalinity":
            return 5
        case "calciumHardness":
            return 6
        case "cyanuricAcid":
            return 7
        case "saltLevel":
            return 9
        default: return 10
        }
    }

    func isSafeToRepeat(despite activeTreatment: Treatment) -> Bool {
        targetParameter != "cyanuricAcid"
    }

    var isAcidTreatment: Bool {
        let name = chemicalName.lowercased()
        return name.contains("muriatic acid")
            || name.contains("dry acid")
            || name.contains("ph decreaser")
            || (targetParameter == "pH" && expectedDelta < 0)
            || (targetParameter == "totalAlkalinity" && expectedDelta < 0 && name.contains("acid"))
    }

    func toTreatment(linkedTo test: PoolTest) -> Treatment {
        Treatment(
            chemicalName: chemicalName,
            actionDescription: actionDescription,
            amount: amount,
            unit: unit,
            productIdentifier: productID?.rawValue,
            globalPreferenceIdentifier: globalPreferenceProductID?.rawValue,
            calculatedDoseBeforeCap: calculatedDoseBeforeCap,
            calculatedDoseBeforeCapUnit: calculatedDoseBeforeCapUnit,
            wasDoseCapped: wasDoseCapped,
            instructions: instructions,
            urgency: urgency,
            isAIGenerated: true,
            targetParameter: targetParameter,
            minutesBeforeNext: minutesBeforeNext,
            sortOrder: sortOrder,
            expectedEffectParameter: expectedEffectParameter.isEmpty ? targetParameter : expectedEffectParameter,
            expectedDelta: expectedDelta,
            effectDelayHours: effectDelayHours,
            effectDurationHours: effectDurationHours,
            doNotRepeatBefore: doNotRepeatHours > 0 ? Date().addingTimeInterval(TimeInterval(doNotRepeatHours * 3600)) : nil,
            poolTest: test
        )
    }
}

// MARK: - Double Rounding Helper

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }

    func roundedLiquidChlorineDose() -> Double {
        if self < 0.25 {
            return rounded(toPlaces: 1)
        }
        if self <= 2.0 {
            return (self * 4).rounded() / 4
        }
        return (self * 2).rounded() / 2
    }

    var formattedTreatmentAmount: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", self)
        }

        let cents = Int((rounded(toPlaces: 2) * 100).rounded())
        if cents % 10 == 0 {
            return String(format: "%.1f", Double(cents) / 100)
        }

        return String(format: "%.2f", Double(cents) / 100)
    }
}
