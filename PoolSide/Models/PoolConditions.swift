import Foundation

struct PoolConditions: Codable, Equatable {
    var swimmingLoad: SwimmingLoad = .unknown
    var petSwimmingLoad: PetSwimmingLoad = .unknown
    var rainLoad: RainLoad = .unknown
    var coverOpenTime: CoverOpenTime = .unknown
    var organicDebrisLoad: OrganicDebrisLoad = .unknown
    var skimmedDebris: SkimmedDebris = .unknown
    var waterAdded: WaterAdded = .unknown
    var cleaningActivity: CleaningActivity = .unknown
    var poolBrushed: PoolBrushed = .unknown

    static let unknown = PoolConditions()

    init(
        swimmingLoad: SwimmingLoad = .unknown,
        petSwimmingLoad: PetSwimmingLoad = .unknown,
        rainLoad: RainLoad = .unknown,
        coverOpenTime: CoverOpenTime = .unknown,
        organicDebrisLoad: OrganicDebrisLoad = .unknown,
        skimmedDebris: SkimmedDebris = .unknown,
        waterAdded: WaterAdded = .unknown,
        cleaningActivity: CleaningActivity = .unknown,
        poolBrushed: PoolBrushed = .unknown
    ) {
        self.swimmingLoad = swimmingLoad
        self.petSwimmingLoad = petSwimmingLoad
        self.rainLoad = rainLoad
        self.coverOpenTime = coverOpenTime
        self.organicDebrisLoad = organicDebrisLoad
        self.skimmedDebris = skimmedDebris
        self.waterAdded = waterAdded

        switch cleaningActivity {
        case .brushedAndMultipleCycles:
            self.cleaningActivity = .multipleCycles
            self.poolBrushed = .yes
        case .brushedAndEntirePool:
            self.cleaningActivity = .entirePool
            self.poolBrushed = .yes
        default:
            self.cleaningActivity = cleaningActivity
            self.poolBrushed = poolBrushed
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCleaning = try container.decodeIfPresent(CleaningActivity.self, forKey: .cleaningActivity) ?? .unknown
        let decodedBrushed = try container.decodeIfPresent(PoolBrushed.self, forKey: .poolBrushed) ?? .unknown

        self.init(
            swimmingLoad: try container.decodeIfPresent(SwimmingLoad.self, forKey: .swimmingLoad) ?? .unknown,
            petSwimmingLoad: try container.decodeIfPresent(PetSwimmingLoad.self, forKey: .petSwimmingLoad) ?? .unknown,
            rainLoad: try container.decodeIfPresent(RainLoad.self, forKey: .rainLoad) ?? .unknown,
            coverOpenTime: try container.decodeIfPresent(CoverOpenTime.self, forKey: .coverOpenTime) ?? .unknown,
            organicDebrisLoad: try container.decodeIfPresent(OrganicDebrisLoad.self, forKey: .organicDebrisLoad) ?? .unknown,
            skimmedDebris: try container.decodeIfPresent(SkimmedDebris.self, forKey: .skimmedDebris) ?? .unknown,
            waterAdded: try container.decodeIfPresent(WaterAdded.self, forKey: .waterAdded) ?? .unknown,
            cleaningActivity: decodedCleaning,
            poolBrushed: decodedBrushed
        )
    }

    var hasAnyKnownCondition: Bool {
        swimmingLoad != .unknown
            || petSwimmingLoad != .unknown
            || rainLoad != .unknown
            || coverOpenTime != .unknown
            || organicDebrisLoad != .unknown
            || skimmedDebris != .unknown
            || waterAdded != .unknown
            || cleaningActivity != .unknown
            || poolBrushed != .unknown
    }

    var chlorineDemandContribution: Int {
        var score = swimmingLoad.chlorineDemandScore
            + petSwimmingLoad.chlorineDemandScore
            + rainLoad.chlorineDemandScore
            + coverOpenTime.chlorineDemandScore
            + organicDebrisLoad.chlorineDemandScore

        if skimmedDebris == .yes {
            score = max(0, score - 1)
        }

        score = max(0, score - cleaningActivity.organicLoadReductionScore - poolBrushed.organicLoadReductionScore)
        return score
    }

    var waterChangeContribution: Int {
        waterAdded.waterChangeScore + rainLoad.waterChangeScore
    }
}

enum SwimmingLoad: String, CaseIterable, Codable, Identifiable {
    case unknown
    case none
    case low
    case moderate
    case high

    var id: String { rawValue }

    var chlorineDemandScore: Int {
        switch self {
        case .unknown, .none: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }
}

enum PetSwimmingLoad: String, CaseIterable, Codable, Identifiable {
    case unknown
    case none
    case low
    case moderate
    case high

    var id: String { rawValue }

    var chlorineDemandScore: Int {
        switch self {
        case .unknown, .none: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }
}

enum RainLoad: String, CaseIterable, Codable, Identifiable {
    case unknown
    case none
    case light
    case steady
    case heavy

    var id: String { rawValue }

    var chlorineDemandScore: Int {
        switch self {
        case .unknown, .none: return 0
        case .light: return 1
        case .steady: return 2
        case .heavy: return 3
        }
    }

    var waterChangeScore: Int {
        switch self {
        case .unknown, .none, .light: return 0
        case .steady: return 1
        case .heavy: return 2
        }
    }
}

enum CoverOpenTime: String, CaseIterable, Codable, Identifiable {
    case unknown
    case mostlyOpen
    case sixToEighteenHours
    case twoToSixHours
    case lessThanTwoHours

    var id: String { rawValue }

    var chlorineDemandScore: Int {
        switch self {
        case .unknown, .mostlyOpen: return 0
        case .sixToEighteenHours: return 1
        case .twoToSixHours: return 2
        case .lessThanTwoHours: return 3
        }
    }
}

enum OrganicDebrisLoad: String, CaseIterable, Codable, Identifiable {
    case unknown
    case none
    case low
    case moderate
    case high

    var id: String { rawValue }

    var chlorineDemandScore: Int {
        switch self {
        case .unknown, .none: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }
}

enum SkimmedDebris: String, CaseIterable, Codable, Identifiable {
    case unknown
    case no
    case yes

    var id: String { rawValue }
}

enum WaterAdded: String, CaseIterable, Codable, Identifiable {
    case unknown
    case none
    case lessThanOneInch
    case oneToTwoInches
    case moreThanTwoInches

    var id: String { rawValue }

    var waterChangeScore: Int {
        switch self {
        case .unknown, .none: return 0
        case .lessThanOneInch: return 1
        case .oneToTwoInches: return 2
        case .moreThanTwoInches: return 3
        }
    }
}

enum CleaningActivity: String, CaseIterable, Codable, Identifiable {
    case unknown
    case no
    case oneCycle
    case multipleCycles
    case brushedAndMultipleCycles
    case spotVacuumed
    case entirePool
    case brushedAndEntirePool

    var id: String { rawValue }

    var organicLoadReductionScore: Int {
        switch self {
        case .unknown, .no: return 0
        case .oneCycle, .spotVacuumed: return 1
        case .multipleCycles, .entirePool: return 2
        case .brushedAndMultipleCycles, .brushedAndEntirePool: return 3
        }
    }
}

enum PoolBrushed: String, CaseIterable, Codable, Identifiable {
    case unknown
    case no
    case yes

    var id: String { rawValue }

    var organicLoadReductionScore: Int {
        switch self {
        case .unknown, .no: return 0
        case .yes: return 1
        }
    }
}
