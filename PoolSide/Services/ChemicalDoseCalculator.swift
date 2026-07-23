import Foundation

struct ChemicalDoseCalculator {
    private static let tenThousandGallons = 10_000.0

    // 1 gallon of 10% liquid chlorine raises FC by about 10 ppm in 10,000 gallons.
    static func liquidChlorineGallons(volumeGallons: Double, ppmIncrease: Double, strengthPercent: Double) -> Double {
        guard strengthPercent > 0 else { return 0 }
        return poolUnits(volumeGallons) * max(0, ppmIncrease) / strengthPercent
    }

    // Generic cal-hypo assumes a typical pool-product available-chlorine strength; exact products vary by label.
    // Approx. 2 oz cal-hypo raises FC by 1 ppm in 10,000 gallons.
    static func calHypoPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (2.0 / 16.0) * max(0, ppmIncrease)
    }

    // Generic dichlor assumes a typical pool-product available-chlorine strength; exact products vary by label.
    // Approx. 2.5 oz dichlor raises FC by 1 ppm in 10,000 gallons.
    static func dichlorPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (2.5 / 16.0) * max(0, ppmIncrease)
    }

    // Soda ash commonly raises pH by ~0.2 with 6 oz per 10,000 gallons at typical buffering.
    static func sodaAshOunces(volumeGallons: Double, pHIncrease: Double) -> Double {
        poolUnits(volumeGallons) * 6.0 * (max(0, pHIncrease) / 0.2)
    }

    static func sodaAshOunces(
        volumeGallons: Double,
        currentPH: Double,
        targetPH: Double,
        totalAlkalinity: Double,
        cyanuricAcid: Double?
    ) -> Double {
        let pHIncrease = max(0, targetPH - currentPH)
        return sodaAshOunces(volumeGallons: volumeGallons, pHIncrease: pHIncrease)
            * bufferDemandMultiplier(totalAlkalinity: totalAlkalinity, cyanuricAcid: cyanuricAcid, pH: currentPH)
    }

    // Borax remains a generic/provisional pool pH-increaser model; exact product directions should control application policy.
    // Borax needs more product than soda ash for the same pH movement.
    static func boraxOunces(volumeGallons: Double, pHIncrease: Double) -> Double {
        sodaAshOunces(volumeGallons: volumeGallons, pHIncrease: pHIncrease) * 1.9
    }

    static func boraxOunces(
        volumeGallons: Double,
        currentPH: Double,
        targetPH: Double,
        totalAlkalinity: Double,
        cyanuricAcid: Double?
    ) -> Double {
        sodaAshOunces(
            volumeGallons: volumeGallons,
            currentPH: currentPH,
            targetPH: targetPH,
            totalAlkalinity: totalAlkalinity,
            cyanuricAcid: cyanuricAcid
        ) * 1.9
    }

    // pH movement is buffered. These pH-dose helpers start from public dosing charts, then scale by
    // carbonate alkalinity, which subtracts pH-dependent CYA alkalinity from measured TA.
    static func muriaticAcid31FluidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        poolUnits(volumeGallons) * 12.8 * (max(0, pHDecrease) / 0.2)
    }

    static func muriaticAcid31FluidOuncesForPH(
        volumeGallons: Double,
        currentPH: Double,
        targetPH: Double,
        totalAlkalinity: Double,
        cyanuricAcid: Double?
    ) -> Double {
        let pHDecrease = max(0, currentPH - targetPH)
        return muriaticAcid31FluidOuncesForPH(volumeGallons: volumeGallons, pHDecrease: pHDecrease)
            * bufferDemandMultiplier(totalAlkalinity: totalAlkalinity, cyanuricAcid: cyanuricAcid, pH: currentPH)
    }

    static func muriaticAcid20FluidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        muriaticAcid31FluidOuncesForPH(volumeGallons: volumeGallons, pHDecrease: pHDecrease) * (31.45 / 20.0)
    }

    static func muriaticAcid20FluidOuncesForPH(
        volumeGallons: Double,
        currentPH: Double,
        targetPH: Double,
        totalAlkalinity: Double,
        cyanuricAcid: Double?
    ) -> Double {
        muriaticAcid31FluidOuncesForPH(
            volumeGallons: volumeGallons,
            currentPH: currentPH,
            targetPH: targetPH,
            totalAlkalinity: totalAlkalinity,
            cyanuricAcid: cyanuricAcid
        ) * (31.45 / 20.0)
    }

    static func dryAcidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        poolUnits(volumeGallons) * 4.8 * (max(0, pHDecrease) / 0.2)
    }

    static func dryAcidOuncesForPH(
        volumeGallons: Double,
        currentPH: Double,
        targetPH: Double,
        totalAlkalinity: Double,
        cyanuricAcid: Double?
    ) -> Double {
        let pHDecrease = max(0, currentPH - targetPH)
        return dryAcidOuncesForPH(volumeGallons: volumeGallons, pHDecrease: pHDecrease)
            * bufferDemandMultiplier(totalAlkalinity: totalAlkalinity, cyanuricAcid: cyanuricAcid, pH: currentPH)
    }

    // Lowering TA intentionally uses more acid than a pH-only correction.
    static func muriaticAcid31FluidOuncesForAlkalinity(volumeGallons: Double, ppmDecrease: Double) -> Double {
        poolUnits(volumeGallons) * 25.6 * (max(0, ppmDecrease) / 10.0)
    }

    static func sodiumBicarbonatePounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * 1.4 * (max(0, ppmIncrease) / 10.0)
    }

    // Calcium chloride 77%: about 1.25 lb raises CH by 10 ppm in 10,000 gallons.
    static func calciumChloridePounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * 1.25 * (max(0, ppmIncrease) / 10.0)
    }

    // Generic pure CYA mass balance: about 13 oz raises CYA by 10 ppm in 10,000 gallons.
    // Some product labels round application doses upward; this calculator intentionally returns the chemistry estimate.
    static func granularCYAPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (13.0 / 16.0) * (max(0, ppmIncrease) / 10.0)
    }

    // 1 lb salt raises salinity by about 12 ppm in 10,000 gallons.
    static func saltPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        max(0, ppmIncrease) * max(0, volumeGallons) / 120_000.0
    }

    static func carbonateAlkalinity(totalAlkalinity: Double, cyanuricAcid: Double?, pH: Double) -> Double {
        max(0, totalAlkalinity - max(0, cyanuricAcid ?? 0) * cyanuricAcidCorrectionFactor(pH: pH))
    }

    static func cyanuricAcidCorrectionFactor(pH: Double) -> Double {
        let points: [(pH: Double, factor: Double)] = [
            (7.0, 0.24),
            (7.2, 0.28),
            (7.4, 0.31),
            (7.6, 0.34),
            (7.8, 0.35),
            (8.0, 0.36)
        ]
        guard let first = points.first, let last = points.last else { return 1.0 / 3.0 }
        if pH <= first.pH { return first.factor }
        if pH >= last.pH { return last.factor }

        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            if pH <= upper.pH {
                let position = (pH - lower.pH) / (upper.pH - lower.pH)
                return lower.factor + (upper.factor - lower.factor) * position
            }
        }
        return 1.0 / 3.0
    }

    private static func bufferDemandMultiplier(totalAlkalinity: Double, cyanuricAcid: Double?, pH: Double) -> Double {
        let carbonateAlkalinity = carbonateAlkalinity(totalAlkalinity: totalAlkalinity, cyanuricAcid: cyanuricAcid, pH: pH)
        return min(1.8, max(0.5, carbonateAlkalinity / 100.0))
    }

    private static func poolUnits(_ volumeGallons: Double) -> Double {
        max(0, volumeGallons) / tenThousandGallons
    }
}
