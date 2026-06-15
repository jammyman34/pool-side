import Foundation
import SwiftData

enum VisualIndicator: String, CaseIterable, Identifiable {
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

    // MARK: - Meta
    var testMethodRaw: String = TestMethod.testStrips.rawValue
    var notes: String
    var visualIndicators: [String] = []

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
        notes: String = "",
        visualIndicators: [String] = [],
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
        self.testMethodRaw = testMethod.rawValue
        self.notes = notes
        self.visualIndicators = visualIndicators
        self.aiAssessment = aiAssessment
        self.treatments = []
    }

    // MARK: - Computed

    /// Combined chlorine (chloramines) = total – free. Should be < 0.5 ppm.
    var combinedChlorine: Double {
        max(0, totalChlorine - freeChlorine)
    }

    var testMethod: TestMethod {
        get { TestMethod(rawValue: testMethodRaw) ?? .testStrips }
        set { testMethodRaw = newValue.rawValue }
    }

    /// Overall pool health score 0–100 based on how many parameters are in ideal range
    var overallScore: Int {
        let engine = ChemistryEngine()
        let readings = engine.allReadings(for: self)
        let idealCount = readings.filter { $0.status == .ideal }.count
        guard !readings.isEmpty else { return 0 }
        return Int(Double(idealCount) / Double(readings.count) * 100)
    }
}
