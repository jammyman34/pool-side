import Foundation

struct ChemicalDoseCalculator {
    private static let tenThousandGallons = 10_000.0

    // 1 gallon of 10% liquid chlorine raises FC by about 10 ppm in 10,000 gallons.
    static func liquidChlorineGallons(volumeGallons: Double, ppmIncrease: Double, strengthPercent: Double) -> Double {
        guard strengthPercent > 0 else { return 0 }
        return poolUnits(volumeGallons) * max(0, ppmIncrease) / strengthPercent
    }

    // Approx. 2 oz cal-hypo raises FC by 1 ppm in 10,000 gallons.
    static func calHypoPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (2.0 / 16.0) * max(0, ppmIncrease)
    }

    // Approx. 2.5 oz dichlor raises FC by 1 ppm in 10,000 gallons.
    static func dichlorPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (2.5 / 16.0) * max(0, ppmIncrease)
    }

    // Soda ash commonly raises pH by ~0.2 with 6 oz per 10,000 gallons.
    static func sodaAshOunces(volumeGallons: Double, pHIncrease: Double) -> Double {
        poolUnits(volumeGallons) * 6.0 * (max(0, pHIncrease) / 0.2)
    }

    // Borax needs more product than soda ash for the same pH movement.
    static func boraxOunces(volumeGallons: Double, pHIncrease: Double) -> Double {
        sodaAshOunces(volumeGallons: volumeGallons, pHIncrease: pHIncrease) * 1.9
    }

    // 31.45% muriatic acid pH response is approximate and TA-dependent; this is a conservative starting point.
    static func muriaticAcid31FluidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        poolUnits(volumeGallons) * 12.8 * (max(0, pHDecrease) / 0.2)
    }

    static func muriaticAcid20FluidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        muriaticAcid31FluidOuncesForPH(volumeGallons: volumeGallons, pHDecrease: pHDecrease) * (31.45 / 20.0)
    }

    static func dryAcidOuncesForPH(volumeGallons: Double, pHDecrease: Double) -> Double {
        poolUnits(volumeGallons) * 4.8 * (max(0, pHDecrease) / 0.2)
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

    // Granular CYA: about 13 oz raises CYA by 10 ppm in 10,000 gallons.
    static func granularCYAPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        poolUnits(volumeGallons) * (13.0 / 16.0) * (max(0, ppmIncrease) / 10.0)
    }

    // 1 lb salt raises salinity by about 12 ppm in 10,000 gallons.
    static func saltPounds(volumeGallons: Double, ppmIncrease: Double) -> Double {
        max(0, ppmIncrease) * max(0, volumeGallons) / 120_000.0
    }

    private static func poolUnits(_ volumeGallons: Double) -> Double {
        max(0, volumeGallons) / tenThousandGallons
    }
}
