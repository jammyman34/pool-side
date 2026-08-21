import Foundation
import SwiftData

enum WaterClarityAssessment: String, Codable, CaseIterable, Identifiable {
    case clear
    case cloudy
    case cannotTell
    case notRecorded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .cannotTell: return "Cannot tell"
        case .notRecorded: return "Not recorded"
        }
    }
}

enum VisibleAlgaeAssessment: String, Codable, CaseIterable, Identifiable {
    case absent
    case present
    case cannotTell
    case notRecorded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .absent: return "No"
        case .present: return "Yes"
        case .cannotTell: return "Cannot tell"
        case .notRecorded: return "Not recorded"
        }
    }
}

enum VisualIndicator: String, CaseIterable, Identifiable {
    case crystalClear = "Crystal Clear"
    case pleasantSmell = "Pleasant Smell"
    case smoothWalls = "Smooth Walls"
    case greenWater = "Green Water"
    case cloudyWater = "Cloudy Water"
    case algaeSpots = "Algae Spots"
    case foam = "Foam"
    case strongChlorineSmell = "Strong Chlorine Smell"
    case scaling = "Scaling"
    case staining = "Staining"
    case poorCirculation = "Poor Circulation"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .crystalClear:
            return "sparkles"
        case .pleasantSmell:
            return "wind"
        case .smoothWalls:
            return "checkmark.seal.fill"
        case .greenWater:
            return "drop.fill"
        case .cloudyWater:
            return "cloud.fill"
        case .algaeSpots:
            return "leaf.fill"
        case .foam:
            return "bubbles.and.sparkles.fill"
        case .strongChlorineSmell:
            return "nose.fill"
        case .scaling:
            return "circle.grid.cross.fill"
        case .staining:
            return "paintbrush.fill"
        case .poorCirculation:
            return "arrow.triangle.2.circlepath"
        }
    }

    /// `true` when this indicator describes healthy water rather than a problem.
    /// Positive indicators carry no penalty in the chemistry engine.
    var isPositive: Bool {
        switch self {
        case .crystalClear, .pleasantSmell, .smoothWalls:
            return true
        default:
            return false
        }
    }

    /// Indicators whose label is too long for the two-column badge grid.
    /// These render full-width at the bottom of the visual indicators card.
    var requiresFullWidthBadge: Bool {
        switch self {
        case .strongChlorineSmell:
            return true
        default:
            return false
        }
    }

    var representsPrimaryVisualAssessment: Bool {
        switch self {
        case .crystalClear, .cloudyWater, .greenWater, .algaeSpots:
            return true
        default:
            return false
        }
    }
}

@Model
final class PoolTest {

    // MARK: - Identity
    var id: UUID
    var date: Date

    // MARK: - Chemical Readings
    /// pH level (ideal: 7.2 – 7.6)
    var pH: Double

    /// Free chlorine in ppm (ideal: 1 – 3 ppm)
    var freeChlorine: Double

    /// Total chlorine in ppm (should be within 0.5 ppm of free chlorine)
    var totalChlorine: Double

    /// Total alkalinity in ppm (ideal: 80 – 120 ppm)
    var totalAlkalinity: Double

    /// Calcium hardness in ppm (ideal: 200 – 400 ppm)
    var calciumHardness: Double

    /// Cyanuric acid / stabilizer in ppm (ideal: 30 – 50 ppm outdoor)
    var cyanuricAcid: Double

    /// Water temperature in °F (optional)
    var temperatureFahrenheit: Double?

    /// Salt level in ppm — relevant for salt-chlorine systems (ideal: 2700 – 3400 ppm)
    var saltLevel: Double?

    // MARK: - Per-Parameter Evidence
    var freeChlorineMeasuredAt: Date?
    var totalChlorineMeasuredAt: Date?
    var pHMeasuredAt: Date?
    var totalAlkalinityMeasuredAt: Date?
    var calciumHardnessMeasuredAt: Date?
    var cyanuricAcidMeasuredAt: Date?
    var saltLevelMeasuredAt: Date?
    var isFocusedCheck: Bool = false
    var focusedCheckParametersRaw: String = ""
    var sourcePoolTestIDRaw: String?
    var sourceWorkflowStepIDRaw: String?

    // MARK: - Meta
    var testMethodRaw: String = TestMethod.testStrips.rawValue
    var liquidDropKitBrandRaw: String?
    /// Taylor K-2006 inputs (only populated when method=liquidDropKit + brand=taylorK2006FASDPD)
    var taylorSampleSizeRaw: String?
    var taylorFCDrops: Int?
    var taylorCCDrops: Int?
    var taylorTADrops: Int?
    var taylorCHDrops: Int?
    var notes: String
    var visualIndicators: [String] = []
    var waterClarityAssessmentRaw: String?
    var visibleAlgaeAssessmentRaw: String?
    var algaeFollowUpResponseRaw: String?
    var cloudinessFollowUpResponseRaw: String?
    var poolConditionsData: Data?

    /// AI-generated assessment text stored alongside the test record
    var aiAssessment: String?

    // MARK: - Relationships
    @Relationship(deleteRule: .cascade, inverse: \Treatment.poolTest)
    var treatments: [Treatment]

    // MARK: - Init
    init(
        id: UUID = UUID(),
        date: Date = Date(),
        pH: Double = 7.4,
        freeChlorine: Double = 2.0,
        totalChlorine: Double = 2.0,
        totalAlkalinity: Double = 100,
        calciumHardness: Double = 300,
        cyanuricAcid: Double = 40,
        temperatureFahrenheit: Double? = nil,
        saltLevel: Double? = nil,
        testMethod: TestMethod = .testStrips,
        liquidDropKitBrand: LiquidDropKitBrand? = nil,
        poolConditions: PoolConditions? = nil,
        notes: String = "",
        visualIndicators: [String] = [],
        waterClarityAssessment: WaterClarityAssessment = .notRecorded,
        visibleAlgaeAssessment: VisibleAlgaeAssessment = .notRecorded,
        algaeFollowUpResponse: VisualFollowUpResponse = .notRecorded,
        cloudinessFollowUpResponse: VisualFollowUpResponse = .notRecorded,
        aiAssessment: String? = nil
    ) {
        self.id = id
        self.date = date
        self.pH = pH
        self.freeChlorine = freeChlorine
        self.totalChlorine = totalChlorine
        self.totalAlkalinity = totalAlkalinity
        self.calciumHardness = calciumHardness
        self.cyanuricAcid = cyanuricAcid
        self.temperatureFahrenheit = temperatureFahrenheit
        self.saltLevel = saltLevel
        self.freeChlorineMeasuredAt = date
        self.totalChlorineMeasuredAt = date
        self.pHMeasuredAt = date
        self.totalAlkalinityMeasuredAt = date
        self.calciumHardnessMeasuredAt = date
        self.cyanuricAcidMeasuredAt = date
        self.saltLevelMeasuredAt = saltLevel == nil ? nil : date
        self.testMethodRaw = testMethod.rawValue
        self.liquidDropKitBrandRaw = liquidDropKitBrand?.rawValue
        self.poolConditionsData = try? poolConditions.map { try JSONEncoder().encode($0) }
        self.notes = notes
        self.visualIndicators = visualIndicators
        self.waterClarityAssessmentRaw = waterClarityAssessment == .notRecorded ? nil : waterClarityAssessment.rawValue
        self.visibleAlgaeAssessmentRaw = visibleAlgaeAssessment == .notRecorded ? nil : visibleAlgaeAssessment.rawValue
        self.algaeFollowUpResponseRaw = algaeFollowUpResponse == .notRecorded ? nil : algaeFollowUpResponse.rawValue
        self.cloudinessFollowUpResponseRaw = cloudinessFollowUpResponse == .notRecorded ? nil : cloudinessFollowUpResponse.rawValue
        self.aiAssessment = aiAssessment
        self.treatments = []
    }

    // MARK: - Computed

    /// Combined chlorine (chloramines) = total – free. Should be < 0.5 ppm.
    var combinedChlorine: Double {
        max(0, totalChlorine - freeChlorine)
    }

    var focusedCheckParameters: [String] {
        get {
            focusedCheckParametersRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            focusedCheckParametersRaw = newValue.joined(separator: ",")
        }
    }

    var sourcePoolTestID: UUID? {
        get { sourcePoolTestIDRaw.flatMap(UUID.init(uuidString:)) }
        set { sourcePoolTestIDRaw = newValue?.uuidString }
    }

    var sourceWorkflowStepID: UUID? {
        get { sourceWorkflowStepIDRaw.flatMap(UUID.init(uuidString:)) }
        set { sourceWorkflowStepIDRaw = newValue?.uuidString }
    }

    func evidenceDate(for parameter: String) -> Date {
        switch parameter {
        case "freeChlorine": return freeChlorineMeasuredAt ?? date
        case "combinedChlorine", "totalChlorine": return totalChlorineMeasuredAt ?? date
        case "pH": return pHMeasuredAt ?? date
        case "totalAlkalinity": return totalAlkalinityMeasuredAt ?? date
        case "calciumHardness": return calciumHardnessMeasuredAt ?? date
        case "cyanuricAcid": return cyanuricAcidMeasuredAt ?? date
        case "saltLevel": return saltLevelMeasuredAt ?? date
        default: return date
        }
    }

    var testMethod: TestMethod {
        get { TestMethod(rawValue: testMethodRaw) ?? .testStrips }
        set { testMethodRaw = newValue.rawValue }
    }

    var liquidDropKitBrand: LiquidDropKitBrand? {
        get { liquidDropKitBrandRaw.flatMap(LiquidDropKitBrand.init(rawValue:)) }
        set { liquidDropKitBrandRaw = newValue?.rawValue }
    }

    var taylorSampleSize: TaylorSampleSize? {
        get { taylorSampleSizeRaw.flatMap(TaylorSampleSize.init(rawValue:)) }
        set { taylorSampleSizeRaw = newValue?.rawValue }
    }

    var poolConditions: PoolConditions? {
        get {
            guard let poolConditionsData else { return nil }
            return try? JSONDecoder().decode(PoolConditions.self, from: poolConditionsData)
        }
        set {
            poolConditionsData = try? newValue.map { try JSONEncoder().encode($0) }
        }
    }

    var waterClarityAssessment: WaterClarityAssessment {
        get { waterClarityAssessmentRaw.flatMap(WaterClarityAssessment.init(rawValue:)) ?? .notRecorded }
        set { waterClarityAssessmentRaw = newValue == .notRecorded ? nil : newValue.rawValue }
    }

    var visibleAlgaeAssessment: VisibleAlgaeAssessment {
        get { visibleAlgaeAssessmentRaw.flatMap(VisibleAlgaeAssessment.init(rawValue:)) ?? .notRecorded }
        set { visibleAlgaeAssessmentRaw = newValue == .notRecorded ? nil : newValue.rawValue }
    }

    var algaeFollowUpResponse: VisualFollowUpResponse {
        get { algaeFollowUpResponseRaw.flatMap(VisualFollowUpResponse.init(rawValue:)) ?? .notRecorded }
        set { algaeFollowUpResponseRaw = newValue == .notRecorded ? nil : newValue.rawValue }
    }

    var cloudinessFollowUpResponse: VisualFollowUpResponse {
        get { cloudinessFollowUpResponseRaw.flatMap(VisualFollowUpResponse.init(rawValue:)) ?? .notRecorded }
        set { cloudinessFollowUpResponseRaw = newValue == .notRecorded ? nil : newValue.rawValue }
    }

    var resolvedPoolConditions: PoolConditions {
        poolConditions ?? .unknown
    }

    /// Overall pool health score 0–100 based on weighted chemistry risk.
    ///
    /// Convenience only: uses the globally-saved configuration and no history. Production consumers must
    /// use `PoolViewModel.overallScore(for:previousTest:recentHistory:)` (or `scoreAssessment`), which pass
    /// the explicit pool configuration and history so one pool's score never depends on which pool is
    /// currently selected in `PoolConfiguration.current`.
    var overallScore: Int {
        let engine = ChemistryEngine()
        return engine.overallScore(for: self, config: .current)
    }
}

/// Canonical Pool Score result. Pool Score is a health/maintenance summary — it never decides swim
/// readiness (Swimability V2 is the single readiness authority).
struct PoolScoreAssessment: Equatable {
    let score: Int
    let grade: String
    /// Canonical parameter-state drivers, named by their ChemistryPolicy action state.
    let drivers: [String]
}
