import Foundation

/// Pool configuration stored in UserDefaults via AppStorage.
/// Not a SwiftData model — settings are single-instance, not queried.
struct PoolConfiguration: Codable, Equatable {

    var name: String = "My Pool"
    var volumeGallons: Double = 15000
    var poolType: PoolType = .inground
    var surfaceType: SurfaceType = .plaster
    var testMethod: TestMethod = .testStrips
    var isSaltwater: Bool = false
    var hasCover: Bool = false
    var chlorinePreference: ChlorinePreference = .calHypo
    var pHIncreaserPreference: PHIncreaserPreference = .sodaAsh
    var pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid
    var alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate
    var calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride
    var stabilizerPreference: StabilizerPreference = .granularCYA
    var location: String = ""
    var latitude: Double?
    var longitude: Double?

    init(
        name: String = "My Pool",
        volumeGallons: Double = 15000,
        poolType: PoolType = .inground,
        surfaceType: SurfaceType = .plaster,
        testMethod: TestMethod = .testStrips,
        isSaltwater: Bool = false,
        hasCover: Bool = false,
        chlorinePreference: ChlorinePreference = .calHypo,
        pHIncreaserPreference: PHIncreaserPreference = .sodaAsh,
        pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid,
        alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate,
        calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride,
        stabilizerPreference: StabilizerPreference = .granularCYA,
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.name = name
        self.volumeGallons = volumeGallons
        self.poolType = poolType
        self.surfaceType = surfaceType
        self.testMethod = testMethod
        self.isSaltwater = isSaltwater
        self.hasCover = hasCover
        self.chlorinePreference = chlorinePreference
        self.pHIncreaserPreference = pHIncreaserPreference
        self.pHDecreaserPreference = pHDecreaserPreference
        self.alkalinityIncreaserPreference = alkalinityIncreaserPreference
        self.calciumIncreaserPreference = calciumIncreaserPreference
        self.stabilizerPreference = stabilizerPreference
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "My Pool"
        volumeGallons = try container.decodeIfPresent(Double.self, forKey: .volumeGallons) ?? 15000
        poolType = try container.decodeIfPresent(PoolType.self, forKey: .poolType) ?? .inground
        surfaceType = try container.decodeIfPresent(SurfaceType.self, forKey: .surfaceType) ?? .plaster
        testMethod = try container.decodeIfPresent(TestMethod.self, forKey: .testMethod) ?? .testStrips
        isSaltwater = try container.decodeIfPresent(Bool.self, forKey: .isSaltwater) ?? false
        hasCover = try container.decodeIfPresent(Bool.self, forKey: .hasCover) ?? false
        chlorinePreference = try container.decodeIfPresent(ChlorinePreference.self, forKey: .chlorinePreference) ?? .calHypo
        pHIncreaserPreference = try container.decodeIfPresent(PHIncreaserPreference.self, forKey: .pHIncreaserPreference) ?? .sodaAsh
        pHDecreaserPreference = try container.decodeIfPresent(PHDecreaserPreference.self, forKey: .pHDecreaserPreference) ?? .muriaticAcid
        alkalinityIncreaserPreference = try container.decodeIfPresent(AlkalinityIncreaserPreference.self, forKey: .alkalinityIncreaserPreference) ?? .sodiumBicarbonate
        calciumIncreaserPreference = try container.decodeIfPresent(CalciumIncreaserPreference.self, forKey: .calciumIncreaserPreference) ?? .calciumChloride
        stabilizerPreference = try container.decodeIfPresent(StabilizerPreference.self, forKey: .stabilizerPreference) ?? .granularCYA
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }

    // MARK: - Persistence key
    static let defaultsKey = "poolConfiguration"

    static var current: PoolConfiguration {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: defaultsKey),
                let config = try? JSONDecoder().decode(PoolConfiguration.self, from: data)
            else { return PoolConfiguration() }
            return config
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Whether configuration has been saved at least once
    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: defaultsKey) != nil
    }

    /// Removes all saved configuration (sign out)
    static func clearCurrent() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Supporting Enums

enum PoolType: String, CaseIterable, Codable, Identifiable {
    case inground    = "inground"
    case aboveGround = "above_ground"
    case spa         = "spa"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inground:    return "In-Ground"
        case .aboveGround: return "Above-Ground"
        case .spa:         return "Spa / Hot Tub"
        }
    }
}

enum SurfaceType: String, CaseIterable, Codable, Identifiable {
    case plaster   = "plaster"
    case vinyl     = "vinyl"
    case fiberglass = "fiberglass"
    case pebble    = "pebble"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plaster:    return "Plaster / Gunite"
        case .vinyl:      return "Vinyl Liner"
        case .fiberglass: return "Fiberglass"
        case .pebble:     return "Pebble / Aggregate"
        }
    }

    /// Recommended calcium hardness range varies by surface
    var calciumHardnessRange: ClosedRange<Double> {
        switch self {
        case .plaster, .pebble: return 200...400
        case .vinyl:             return 150...250
        case .fiberglass:        return 150...250
        }
    }
}

enum TestMethod: String, CaseIterable, Codable, Identifiable {
    case testStrips = "test_strips"
    case liquidDropKit = "liquid_drop_kit"
    case digitalTester = "digital_tester"
    case poolStore = "pool_store"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testStrips: return "Test Strips"
        case .liquidDropKit: return "Liquid Drop Test Kit"
        case .digitalTester: return "Digital Tester"
        case .poolStore: return "Pool Store Test"
        }
    }

    var confidenceNote: String? {
        switch self {
        case .testStrips:
            return "Test strips can vary based on lighting, timing, and color matching. Borderline readings are treated as estimates, so confirm them before adding optional chemicals."
        case .liquidDropKit:
            return "Liquid drop tests are usually more consistent than strips, but clean tubes and exact drop counts still matter."
        case .digitalTester:
            return "Digital testers are generally consistent when calibrated and stored correctly."
        case .poolStore:
            return "Pool store tests are useful reference points, but the app still compares them against your treatment history before recommending more chemicals."
        }
    }

    var shouldSuppressOptionalTreatments: Bool {
        self == .testStrips
    }
}

enum ChlorinePreference: String, CaseIterable, Codable, Identifiable {
    case tablets = "tablets"
    case calHypo = "cal_hypo"
    case liquidChlorine10 = "liquid_chlorine_10"
    case liquidChlorine12_5 = "liquid_chlorine_12_5"
    case dichlor = "dichlor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tablets: return "Chlorine Tablets"
        case .calHypo: return "Chlorine Granules"
        case .liquidChlorine10: return "Liquid Chlorine 10%"
        case .liquidChlorine12_5: return "Liquid Chlorine 12.5%"
        case .dichlor: return "Dichlor Granules"
        }
    }
}

enum PHIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case sodaAsh = "soda_ash"
    case borax = "borax"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sodaAsh: return "pH Increaser / Soda Ash"
        case .borax: return "Borax"
        }
    }
}

enum PHDecreaserPreference: String, CaseIterable, Codable, Identifiable {
    case muriaticAcid = "muriatic_acid"
    case dryAcid = "dry_acid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muriaticAcid: return "pH Decreaser / Muriatic Acid"
        case .dryAcid: return "pH Decreaser / Dry Acid"
        }
    }
}

enum AlkalinityIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case sodiumBicarbonate = "sodium_bicarbonate"

    var id: String { rawValue }
    var displayName: String { "Alkalinity Increaser" }
}

enum CalciumIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case calciumChloride = "calcium_chloride"

    var id: String { rawValue }
    var displayName: String { "Calcium Hardness Increaser" }
}

enum StabilizerPreference: String, CaseIterable, Codable, Identifiable {
    case granularCYA = "granular_cya"
    case liquidConditioner = "liquid_conditioner"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .granularCYA: return "Pool Stabilizer Granules"
        case .liquidConditioner: return "Liquid Pool Stabilizer"
        }
    }
}
