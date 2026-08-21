import Foundation

struct TreatmentApplicationPolicy {
    struct DoseApplication {
        let currentAmount: Double
        let currentUnit: String
        let totalCalculatedAmount: Double
        let totalCalculatedUnit: String
        let remainingEstimatedAmount: Double
        let remainingEstimatedUnit: String
        let isApplicationLimited: Bool
    }

    // HASA 31.45% muriatic acid directions used for generic 31.45% acid application policy:
    // maximum 1 quart per 20,000 gallons per 24 hours, with circulation running during addition.
    static let muriaticAcid31MaxFluidOuncesPer20kGallonsPer24Hours = 32.0
    static let muriaticAcid31EarliestRepeatDoseHours = 24
    static let muriaticAcidMinimumCirculationHours = 1

    // Poolife sodium bicarbonate directions support allowing 6-8 hours of circulation before retesting TA.
    static let bakingSodaRetestWindowHours: ClosedRange<Double> = 6.0...8.0

    // Calcium chloride labels commonly call for several hours of circulation; CH testing is treated as next-day.
    static let calciumChlorideRetestHours = 24

    // Generic pure CYA is calculated by mass balance; application policy keeps CYA testing delayed.
    static let granularCYARetestWindowHours: ClosedRange<Double> = 24.0...48.0
    static let granularCYACanonicalRetestHours = 48

    static func muriaticAcid31CurrentApplication(
        totalFluidOunces: Double,
        volumeGallons: Double,
        displayDose: (Double) -> (amount: Double, unit: String)
    ) -> DoseApplication {
        let totalOunces = max(0, totalFluidOunces)
        let limitOunces = muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: volumeGallons)
        let currentOunces = min(totalOunces, limitOunces)
        let totalDose = displayDose(totalOunces)
        let currentDose = displayDose(currentOunces)
        let remainingDose = displayDose(max(0, totalOunces - currentOunces))

        return DoseApplication(
            currentAmount: currentDose.amount,
            currentUnit: currentDose.unit,
            totalCalculatedAmount: totalDose.amount,
            totalCalculatedUnit: totalDose.unit,
            remainingEstimatedAmount: remainingDose.amount,
            remainingEstimatedUnit: remainingDose.unit,
            isApplicationLimited: currentOunces < totalOunces
        )
    }

    static func muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: Double) -> Double {
        max(0, volumeGallons) / 20_000.0 * muriaticAcid31MaxFluidOuncesPer20kGallonsPer24Hours
    }

    // MARK: - Product-agnostic acid staging
    //
    // Acid staging is defined on the *corrective acid load*, expressed as an equivalent volume of
    // 31.45% muriatic acid (the reference product). Every acid product's dose is derived from the
    // same 31.45%-equivalent demand, so staging the load once and then translating into the selected
    // product's own units keeps the safe current application chemically equivalent across products.
    // This removes the prior asymmetry where 20% low-fume acid and dry acid bypassed the volume-scaled
    // single-application limit that 31.45% muriatic already honored.
    struct AcidStagedLoad {
        /// Safe current application, in 31.45%-equivalent fluid ounces.
        let currentEquivalent31FluidOunces: Double
        /// Total theoretical correction, in 31.45%-equivalent fluid ounces (never discarded).
        let totalEquivalent31FluidOunces: Double
        /// True when the total demand exceeds one safe application and was staged.
        let isApplicationLimited: Bool
    }

    static func stagedAcidLoad(equivalent31FluidOunces total: Double, volumeGallons: Double) -> AcidStagedLoad {
        let totalOunces = max(0, total)
        let limitOunces = muriaticAcid31CurrentApplicationLimitFluidOunces(volumeGallons: volumeGallons)
        let currentOunces = min(totalOunces, limitOunces)
        return AcidStagedLoad(
            currentEquivalent31FluidOunces: currentOunces,
            totalEquivalent31FluidOunces: totalOunces,
            isApplicationLimited: currentOunces < totalOunces
        )
    }
}
