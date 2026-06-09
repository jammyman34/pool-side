import Foundation
import SwiftData

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
    var notes: String

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
        notes: String = "",
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
        self.notes = notes
        self.aiAssessment = aiAssessment
        self.treatments = []
    }

    // MARK: - Computed

    /// Combined chlorine (chloramines) = total – free. Should be < 0.5 ppm.
    var combinedChlorine: Double {
        max(0, totalChlorine - freeChlorine)
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
