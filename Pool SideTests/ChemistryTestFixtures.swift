import Foundation
import XCTest
@testable import Pool_Side

enum ChemistryTestFixtures {
    static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
    static let futureDate = Date(timeIntervalSince1970: 4_102_444_800)

    static func config(
        volume: Double = 32_583,
        isSaltwater: Bool = false,
        chlorine: ChlorinePreference = .liquidChlorine12_5,
        pHDecreaser: PHDecreaserPreference = .dryAcid,
        stabilizer: StabilizerPreference = .granularCYA
    ) -> PoolConfiguration {
        PoolConfiguration(
            volumeGallons: volume,
            surfaceType: .plaster,
            testMethod: .liquidDropKit,
            isSaltwater: isSaltwater,
            chlorinePreference: chlorine,
            lastNonSaltChlorinePreference: chlorine.isSaltGenerator ? .liquidChlorine12_5 : chlorine,
            pHDecreaserPreference: pHDecreaser,
            stabilizerPreference: stabilizer
        )
    }

    static func currentPool(
        pH: Double = 7.8,
        freeChlorine: Double = 1,
        totalChlorine: Double = 1,
        totalAlkalinity: Double = 170,
        calciumHardness: Double = 300,
        cyanuricAcid: Double = 55,
        visualIndicators: [String] = [VisualIndicator.crystalClear.rawValue]
    ) -> PoolTest {
        PoolTest(
            date: baseDate,
            pH: pH,
            freeChlorine: freeChlorine,
            totalChlorine: totalChlorine,
            totalAlkalinity: totalAlkalinity,
            calciumHardness: calciumHardness,
            cyanuricAcid: cyanuricAcid,
            testMethod: .liquidDropKit,
            visualIndicators: visualIndicators
        )
    }

    static func pHDriftHistory() -> [PoolTest] {
        [
            historicalTest(daysAgo: 7, pH: 7.6, totalAlkalinity: 160),
            historicalTest(daysAgo: 14, pH: 7.6, totalAlkalinity: 160),
            historicalTest(daysAgo: 21, pH: 7.5, totalAlkalinity: 170),
            historicalTest(daysAgo: 28, pH: 7.5, totalAlkalinity: 170)
        ]
    }

    static func historicalTest(daysAgo: Int, pH: Double, totalAlkalinity: Double) -> PoolTest {
        PoolTest(
            date: baseDate.addingTimeInterval(TimeInterval(-daysAgo * 86_400)),
            pH: pH,
            freeChlorine: 4,
            totalChlorine: 4,
            totalAlkalinity: totalAlkalinity,
            calciumHardness: 300,
            cyanuricAcid: 55,
            testMethod: .liquidDropKit,
            visualIndicators: [VisualIndicator.crystalClear.rawValue]
        )
    }

    static func activeCompletedAcidTreatment() -> Treatment {
        Treatment(
            createdAt: baseDate.addingTimeInterval(-3_600),
            chemicalName: ChemicalProductID.muriaticAcid31.displayName,
            actionDescription: "Completed acid treatment",
            amount: 32,
            unit: "fl oz",
            productIdentifier: ChemicalProductID.muriaticAcid31.rawValue,
            globalPreferenceIdentifier: ChemicalProductID.muriaticAcid31.rawValue,
            instructions: "Completed",
            urgency: .recommended,
            isCompleted: true,
            completedAt: baseDate.addingTimeInterval(-3_600),
            targetParameter: "pH",
            expectedEffectParameter: "pH",
            expectedDelta: -0.2,
            doNotRepeatBefore: futureDate
        )
    }

    static func ounces(amount: Double, unit: String) -> Double {
        switch unit {
        case "fl oz":
            return amount
        case "qt":
            return amount * 32
        case "gal":
            return amount * 128
        case "lbs":
            return amount * 16
        default:
            XCTFail("Unhandled unit \(unit)")
            return amount
        }
    }
}
