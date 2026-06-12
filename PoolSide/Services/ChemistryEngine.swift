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
            if let template = treatmentTemplate(for: reading, volume: config.volumeGallons) {
                templates.append(template)
            }
        }

        // Sort by urgency, then assign sequential wait times between steps
        var sorted = templates.sorted { $0.urgency.sortOrder < $1.urgency.sortOrder }
        for i in 0..<sorted.count {
            sorted[i].sortOrder = i
            // Set wait after this step before the next (only if there IS a next step)
            if i < sorted.count - 1 {
                sorted[i].minutesBeforeNext = waitMinutes(for: sorted[i].targetParameter)
            }
        }
        return sorted
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

    // MARK: - Treatment Templates

    private func treatmentTemplate(for reading: ChemicalReading, volume: Double) -> TreatmentTemplate? {
        let kGal = volume / 1000

        switch reading.key {
        case "pH":
            if reading.value < 7.2 {
                let oz = kGal * 6 * ((7.4 - reading.value) / 0.2)
                return TreatmentTemplate(
                    chemicalName: "pH Increaser (Sodium Carbonate)",
                    actionDescription: "Raise pH to ideal range (7.2 – 7.6)",
                    amount: (oz / 16).rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Pre-dissolve in a bucket of pool water. Add solution to pool while pump runs. Retest in 4–6 hours.",
                    targetParameter: "pH",
                    urgency: reading.status.treatmentUrgency ?? .recommended
                )
            } else {
                let oz = kGal * 6 * ((reading.value - 7.4) / 0.2)
                return TreatmentTemplate(
                    chemicalName: "pH Decreaser (Muriatic Acid)",
                    actionDescription: "Lower pH to ideal range (7.2 – 7.6)",
                    amount: (oz / 16).rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Add slowly to deep end of pool while pump runs. Never pre-mix with other chemicals. Retest in 4 hours.",
                    targetParameter: "pH",
                    urgency: reading.status.treatmentUrgency ?? .recommended
                )
            }

        case "freeChlorine":
            if reading.value < 1.0 {
                let lbs = kGal * 0.13 * (2.0 - reading.value)
                return TreatmentTemplate(
                    chemicalName: "Chlorine Shock (Cal-Hypo 68%)",
                    actionDescription: "Raise free chlorine to safe levels",
                    amount: lbs.rounded(toPlaces: 2),
                    unit: "lbs",
                    instructions: "Pre-dissolve in bucket of pool water. Add to pool at dusk with pump running. Keep swimmers out until levels drop below 4 ppm.",
                    targetParameter: "freeChlorine",
                    urgency: reading.status.treatmentUrgency ?? .recommended
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Remove Chlorine Source",
                    actionDescription: "Reduce free chlorine — it's elevated",
                    amount: 0,
                    unit: "",
                    instructions: "Allow levels to drop naturally by running pool in sunlight without adding chlorine. Retest in 24 hours. If urgent, use a chlorine neutralizer (sodium thiosulfate).",
                    targetParameter: "freeChlorine",
                    urgency: reading.status.treatmentUrgency ?? .optional
                )
            }

        case "totalAlkalinity":
            if reading.value < 80 {
                let lbs = kGal * 1.4 * ((80 - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: "Alkalinity Increaser (Sodium Bicarbonate)",
                    actionDescription: "Raise total alkalinity to 80 – 120 ppm",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Add directly to pool with pump running. For large doses, split into two additions 4–6 hours apart. Retest next day.",
                    targetParameter: "totalAlkalinity",
                    urgency: reading.status.treatmentUrgency ?? .recommended
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
                    urgency: reading.status.treatmentUrgency ?? .recommended
                )
            }

        case "calciumHardness":
            if reading.value < 200 {
                let lbs = kGal * 1.25 * ((200 - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: "Calcium Hardness Increaser (Calcium Chloride)",
                    actionDescription: "Raise calcium hardness to prevent surface damage",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Pre-dissolve in water — this is exothermic, use caution. Add slowly around pool perimeter. Retest in 4 hours.",
                    targetParameter: "calciumHardness",
                    urgency: reading.status.treatmentUrgency ?? .optional
                )
            } else {
                return TreatmentTemplate(
                    chemicalName: "Partial Water Replacement",
                    actionDescription: "Dilute high calcium hardness with fresh water",
                    amount: Double(Int(volume * 0.25)),
                    unit: "gallons to drain/refill",
                    instructions: "Drain 25% of pool water and refill with fresh water. Retest after refilling and circulation for 2 hours.",
                    targetParameter: "calciumHardness",
                    urgency: reading.status.treatmentUrgency ?? .optional
                )
            }

        case "cyanuricAcid":
            if reading.value < 30 {
                let lbs = kGal * 0.5 * ((40 - reading.value) / 10)
                return TreatmentTemplate(
                    chemicalName: "Stabilizer / Conditioner (Cyanuric Acid)",
                    actionDescription: "Raise cyanuric acid to protect chlorine from UV",
                    amount: lbs.rounded(toPlaces: 1),
                    unit: "lbs",
                    instructions: "Add directly to skimmer with pump running, or pre-dissolve in warm water. Takes 2–3 days to fully register in tests. Do not backwash for 48 hours.",
                    targetParameter: "cyanuricAcid",
                    urgency: reading.status.treatmentUrgency ?? .optional
                )
            } else if reading.value > 80 {
                return TreatmentTemplate(
                    chemicalName: "Partial Water Replacement",
                    actionDescription: "Dilute cyanuric acid — chlorine lock risk above 80 ppm",
                    amount: Double(Int(volume * 0.30)),
                    unit: "gallons to drain/refill",
                    instructions: "Drain 30% of pool water, refill with fresh water, and retest. CYA cannot be chemically removed — dilution is the only solution.",
                    targetParameter: "cyanuricAcid",
                    urgency: reading.status.treatmentUrgency ?? .recommended
                )
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func trend(current: Double, previous: Double) -> ChemicalReading.Trend {
        let delta = current - previous
        if abs(delta) < 0.05 { return .stable }
        return delta > 0 ? .rising : .falling
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

    func toTreatment(linkedTo test: PoolTest) -> Treatment {
        Treatment(
            chemicalName: chemicalName,
            actionDescription: actionDescription,
            amount: amount,
            unit: unit,
            instructions: instructions,
            urgency: urgency,
            isAIGenerated: false,
            targetParameter: targetParameter,
            minutesBeforeNext: minutesBeforeNext,
            sortOrder: sortOrder,
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
