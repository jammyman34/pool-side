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

        static let freeChlorine        = 1.0...3.0
        static let freeChlorineSlight  = 0.5...1.0
        static let freeChlorineHigh    = 3.0...5.0

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
        case Ranges.pH:          return .ideal
        case 7.0..<7.2:         return .slightlyLow
        case 7.6..<7.8:         return .slightlyHigh
        case 6.8..<7.0:         return .low
        case 7.8..<8.2:         return .high
        default:                 return .critical
        }
    }

    func freeChlorineStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case Ranges.freeChlorine: return .ideal
        case 0.5..<1.0:          return .slightlyLow
        case 3.0..<5.0:          return .slightlyHigh
        case 0.0..<0.5:          return .low
        case 5.0..<10.0:         return .high
        default:                  return .critical
        }
    }

    func totalAlkalinityStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case Ranges.totalAlkalinity: return .ideal
        case 60.0..<80.0:           return .slightlyLow
        case 120.0..<150.0:         return .slightlyHigh
        case 40.0..<60.0:           return .low
        case 150.0..<200.0:         return .high
        default:                     return .critical
        }
    }

    func calciumHardnessStatus(_ value: Double, surface: SurfaceType = .plaster) -> ChemicalStatus {
        let ideal = surface.calciumHardnessRange
        switch value {
        case ideal:               return .ideal
        case (ideal.lowerBound - 50)..<ideal.lowerBound: return .slightlyLow
        case ideal.upperBound..<(ideal.upperBound + 100): return .slightlyHigh
        case 0..<(ideal.lowerBound - 50): return .low
        default:                  return .high
        }
    }

    func cyanuricAcidStatus(_ value: Double) -> ChemicalStatus {
        switch value {
        case Ranges.cyanuricAcid:  return .ideal
        case 10.0..<30.0:          return .slightlyLow
        case 50.0..<80.0:          return .slightlyHigh
        case 0.0..<10.0:           return .low
        case 80.0..<100.0:         return .high
        default:                    return .critical // >100 ppm chlorine lock
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
            idealRange: "7.2 – 7.6",
            trend: phTrend
        ))

        let clTrend = previousTest.map { trend(current: test.freeChlorine, previous: $0.freeChlorine) }
        readings.append(ChemicalReading(
            parameter: "Free Chlorine",
            key: "freeChlorine",
            value: test.freeChlorine,
            unit: "ppm",
            status: freeChlorineStatus(test.freeChlorine),
            idealRange: "1 – 3 ppm",
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
            idealRange: "200 – 400 ppm",
            trend: chTrend
        ))

        let caTrend = previousTest.map { trend(current: test.cyanuricAcid, previous: $0.cyanuricAcid) }
        readings.append(ChemicalReading(
            parameter: "Cyanuric Acid",
            key: "cyanuricAcid",
            value: test.cyanuricAcid,
            unit: "ppm",
            status: cyanuricAcidStatus(test.cyanuricAcid),
            idealRange: "30 – 50 ppm",
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

    // MARK: - Rule-Based Treatments

    func ruleTreatments(for test: PoolTest, config: PoolConfiguration = .current) -> [TreatmentTemplate] {
        let readings = allReadings(for: test, config: config)
        var templates: [TreatmentTemplate] = []

        for reading in readings where reading.status != .ideal && reading.status != .testing {
            if let template = treatmentTemplate(for: reading, config: config) {
                templates.append(template)
            }
        }

        // Sort by chemical dependency. In normal pool care, alkalinity and pH corrections
        // should happen before sanitizer so chlorine can work against balanced water.
        var sorted = templates.sorted {
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
        var templates = ruleTreatments(for: test, config: config)
        templates = suppressRecentlyCompletedEffects(templates, recentHistory: recentHistory)
        templates = suppressLowConfidenceOptionalTreatments(templates, config: config)

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

    private func suppressLowConfidenceOptionalTreatments(
        _ templates: [TreatmentTemplate],
        config: PoolConfiguration
    ) -> [TreatmentTemplate] {
        guard config.testMethod.shouldSuppressOptionalTreatments else {
            return templates
        }

        return templates.filter { $0.urgency != .optional }
    }

    // MARK: - Treatment Templates

    private func treatmentTemplate(for reading: ChemicalReading, config: PoolConfiguration) -> TreatmentTemplate? {
        let volume = config.volumeGallons
        let kGal = volume / 1000

        switch reading.key {
        case "pH":
            if reading.value < 7.2 {
                let oz = kGal * 6 * ((7.4 - reading.value) / 0.2)
                let product = pHIncreaserProduct(config.pHIncreaserPreference, ounces: oz)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Raise pH to ideal range (7.2 – 7.6)",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: product.instructions,
                    targetParameter: "pH",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "pH",
                    expectedDelta: 7.4 - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 24,
                    doNotRepeatHours: 12
                )
            } else {
                let oz = kGal * 6 * ((reading.value - 7.4) / 0.2)
                let product = pHDecreaserProduct(config.pHDecreaserPreference, ounces: oz)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Lower pH to ideal range (7.2 – 7.6)",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: product.instructions,
                    targetParameter: "pH",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "pH",
                    expectedDelta: 7.4 - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 24,
                    doNotRepeatHours: 12
                )
            }

        case "freeChlorine":
            if reading.value < 1.0 {
                let ppmIncrease = max(0, 2.0 - reading.value)
                let product = chlorineProduct(config.chlorinePreference, volume: volume, ppmIncrease: ppmIncrease)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Raise free chlorine to safe levels",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: product.instructions,
                    targetParameter: "freeChlorine",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "freeChlorine",
                    expectedDelta: 2.0 - reading.value,
                    effectDelayHours: 1,
                    effectDurationHours: 24,
                    doNotRepeatHours: 4
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
            if reading.value < 80 {
                let lbs = kGal * 1.4 * ((80 - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: config.alkalinityIncreaserPreference.displayName,
                    actionDescription: "Raise total alkalinity to 80 – 120 ppm",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Add directly to pool with pump running. For large doses, split into two additions 4–6 hours apart. Retest next day.",
                    targetParameter: "totalAlkalinity",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "totalAlkalinity",
                    expectedDelta: 80 - reading.value,
                    effectDelayHours: 12,
                    effectDurationHours: 48,
                    doNotRepeatHours: 24
                )
            } else {
                let qts = kGal * 0.8 * ((reading.value - 120) / 10)
                return TreatmentTemplate(
                    chemicalName: "pH Decreaser / Muriatic Acid",
                    actionDescription: "Lower total alkalinity to 80 – 120 ppm",
                    amount: qts.rounded(toPlaces: 1),
                    unit: "quarts",
                    instructions: "Turn off pump. Add acid directly to deep end. Wait 1 hour, then restart pump. Aerate water to help CO₂ off-gas. Retest in 6 hours.",
                    targetParameter: "totalAlkalinity",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "totalAlkalinity",
                    expectedDelta: 120 - reading.value,
                    effectDelayHours: 6,
                    effectDurationHours: 48,
                    doNotRepeatHours: 24
                )
            }

        case "calciumHardness":
            if reading.value < 200 {
                let lbs = kGal * 1.25 * ((200 - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: "Calcium Hardness Increaser (\(config.calciumIncreaserPreference.displayName))",
                    actionDescription: "Raise calcium hardness to prevent surface damage",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Pre-dissolve in water — this is exothermic, use caution. Add slowly around pool perimeter. Retest in 4 hours.",
                    targetParameter: "calciumHardness",
                    urgency: reading.status.treatmentUrgency ?? .optional,
                    expectedEffectParameter: "calciumHardness",
                    expectedDelta: 200 - reading.value,
                    effectDelayHours: 4,
                    effectDurationHours: 72,
                    doNotRepeatHours: 24
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Partial Water Replacement",
                    actionDescription: "Dilute high calcium hardness with fresh water",
                    amount: Double(Int(volume * 0.25)),
                    unit: "gallons to drain/refill",
                    instructions: "Drain 25% of pool water and refill with fresh water. Retest after refilling and circulation for 2 hours.",
                    targetParameter: "calciumHardness",
                    urgency: reading.status.treatmentUrgency ?? .optional,
                    expectedEffectParameter: "calciumHardness",
                    expectedDelta: 0,
                    effectDelayHours: 2,
                    effectDurationHours: 72,
                    doNotRepeatHours: 24
                )
            }

        case "cyanuricAcid":
            if reading.value < 30 {
                let lbs = kGal * 0.5 * ((40 - reading.value) / 10)
                let product = stabilizerProduct(config.stabilizerPreference, pounds: lbs)
                return TreatmentTemplate(
                    chemicalName: product.name,
                    actionDescription: "Raise cyanuric acid to protect chlorine from UV",
                    amount: product.amount,
                    unit: product.unit,
                    instructions: product.instructions,
                    targetParameter: "cyanuricAcid",
                    urgency: reading.status.treatmentUrgency ?? .optional,
                    expectedEffectParameter: "cyanuricAcid",
                    expectedDelta: 40 - reading.value,
                    effectDelayHours: 72,
                    effectDurationHours: 168,
                    doNotRepeatHours: 168
                )
            } else if reading.value > 80 {
                return TreatmentTemplate(
                    chemicalName: "Partial Water Replacement",
                    actionDescription: "Dilute cyanuric acid — chlorine lock risk above 80 ppm",
                    amount: Double(Int(volume * 0.30)),
                    unit: "gallons to drain/refill",
                    instructions: "Drain 30% of pool water, refill with fresh water, and retest. CYA cannot be chemically removed — dilution is the only solution.",
                    targetParameter: "cyanuricAcid",
                    urgency: reading.status.treatmentUrgency ?? .recommended,
                    expectedEffectParameter: "cyanuricAcid",
                    expectedDelta: 0,
                    effectDelayHours: 24,
                    effectDurationHours: 168,
                    doNotRepeatHours: 72
                )
            }
            return nil

        default:
            return nil
        }
    }

    private func chlorineProduct(
        _ preference: ChlorinePreference,
        volume: Double,
        ppmIncrease: Double
    ) -> ChemicalProduct {
        switch preference {
        case .tablets:
            return ChemicalProduct(
                name: "Chlorine Tablets",
                amount: 1,
                unit: "dose per label",
                instructions: "Use tablets in a floater, feeder, or chlorinator for maintenance according to the product label. Tablets dissolve slowly, so for an urgent free-chlorine correction use liquid chlorine or chlorine granules instead."
            )
        case .calHypo:
            let pounds = (volume / 1000) * 0.13 * ppmIncrease
            return ChemicalProduct(
                name: "Chlorine Granules",
                amount: pounds.rounded(toPlaces: 2),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water. Add to the pool at dusk with the pump running. Keep swimmers out until free chlorine drops below 4 ppm."
            )
        case .liquidChlorine10:
            let gallons = ppmIncrease * volume / 10000 / 10
            return ChemicalProduct(
                name: "Liquid Chlorine 10%",
                amount: gallons.rounded(toPlaces: 2),
                unit: "gal",
                instructions: "Pour slowly in front of a return jet at dusk with the pump running. Brush and circulate, then retest free chlorine after 30-60 minutes."
            )
        case .liquidChlorine12_5:
            let gallons = ppmIncrease * volume / 10000 / 12.5
            return ChemicalProduct(
                name: "Liquid Chlorine 12.5%",
                amount: gallons.rounded(toPlaces: 2),
                unit: "gal",
                instructions: "Pour slowly in front of a return jet at dusk with the pump running. Brush and circulate, then retest free chlorine after 30-60 minutes."
            )
        case .dichlor:
            let pounds = (volume / 1000) * 0.085 * ppmIncrease
            return ChemicalProduct(
                name: "Dichlor Chlorine Granules",
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
                name: "pH Increaser / Soda Ash",
                amount: (ounces / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water. Add solution with the pump running. Retest pH in 4-6 hours."
            )
        case .borax:
            return ChemicalProduct(
                name: "pH Increaser (Borax)",
                amount: ((ounces * 1.9) / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Add slowly with the pump running, brushing any settled product. Borax has less impact on alkalinity than soda ash. Retest pH in 4-6 hours."
            )
        }
    }

    private func pHDecreaserProduct(_ preference: PHDecreaserPreference, ounces: Double) -> ChemicalProduct {
        switch preference {
        case .muriaticAcid:
            return ChemicalProduct(
                name: "pH Decreaser / Muriatic Acid",
                amount: (ounces / 32).rounded(toPlaces: 1),
                unit: "qt",
                instructions: "Add slowly to the deep end with the pump running. Never pre-mix with other chemicals. Retest pH in 4 hours."
            )
        case .dryAcid:
            return ChemicalProduct(
                name: "pH Decreaser / Dry Acid",
                amount: (ounces / 16).rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Pre-dissolve in a bucket of pool water and add slowly with the pump running. Retest pH in 4 hours."
            )
        }
    }

    private func stabilizerProduct(_ preference: StabilizerPreference, pounds: Double) -> ChemicalProduct {
        switch preference {
        case .granularCYA:
            return ChemicalProduct(
                name: "Pool Stabilizer Granules",
                amount: pounds.rounded(toPlaces: 1),
                unit: "lbs",
                instructions: "Place stabilizer in a sock or mesh bag in front of a return jet with the pump running. Do not leave undissolved stabilizer sitting in the skimmer basket. It can take up to a week to fully register on tests."
            )
        case .liquidConditioner:
            return ChemicalProduct(
                name: "Liquid Pool Stabilizer",
                amount: pounds.rounded(toPlaces: 1),
                unit: "lbs CYA equivalent",
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

private struct ChemicalProduct {
    let name: String
    let amount: Double
    let unit: String
    let instructions: String
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

    var sequencePriority: Int {
        switch targetParameter {
        case "totalAlkalinity": return 0
        case "pH": return 1
        case "calciumHardness": return 2
        case "cyanuricAcid": return 3
        case "freeChlorine": return 4
        case "saltLevel": return 5
        case "visualIndicators": return 6
        default: return 7
        }
    }

    func isSafeToRepeat(despite activeTreatment: Treatment) -> Bool {
        targetParameter != "cyanuricAcid"
    }

    func toTreatment(linkedTo test: PoolTest) -> Treatment {
        Treatment(
            chemicalName: chemicalName,
            actionDescription: actionDescription,
            amount: amount,
            unit: unit,
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
}
