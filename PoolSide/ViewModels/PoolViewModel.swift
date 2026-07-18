import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
final class PoolViewModel {

    // MARK: - State
    var poolConfig: PoolConfiguration = .current
    var isGeneratingRecommendations: Bool = false
    var aiServiceAvailable: Bool = false
    var lastError: String?

    // MARK: - Services
    private let chemistryEngine = ChemistryEngine()
    private let nextTestRecommendationEngine = NextTestRecommendationEngine()
    private var aiService: AIService?

    // MARK: - Init
    init() {
        setupAIService()
    }

    // MARK: - AI Setup

    private func setupAIService() {
        aiService = RuleBasedService()
        aiServiceAvailable = false
    }

    // MARK: - Config

    func saveConfig(_ config: PoolConfiguration) {
        var normalized = config
        normalized.normalizeChemicalPreferences()
        poolConfig = normalized
        PoolConfiguration.current = normalized
    }

    // MARK: - Chemistry

    func readings(for test: PoolTest, previousTest: PoolTest? = nil) -> [ChemicalReading] {
        chemistryEngine.allReadings(for: test, previousTest: previousTest, config: poolConfig)
    }

    func overallStatus(for test: PoolTest) -> ChemicalStatus {
        let readings = chemistryEngine.allReadings(for: test, config: poolConfig)
        let criticals = readings.filter { $0.status == .critical }
        let lows = readings.filter { $0.status == .low || $0.status == .high }
        let slights = readings.filter { $0.status == .slightlyLow || $0.status == .slightlyHigh }

        if !criticals.isEmpty { return .critical }
        if !lows.isEmpty { return .low }
        if !slights.isEmpty { return .slightlyLow }
        return .ideal
    }

    func overallScore(
        for test: PoolTest,
        previousTest: PoolTest? = nil,
        recentHistory: [PoolTest] = []
    ) -> Int {
        chemistryEngine.overallScore(
            for: test,
            previousTest: previousTest,
            recentHistory: recentHistory,
            config: poolConfig
        )
    }

    func currentStatusSummary(for test: PoolTest) -> String {
        chemistryEngine.currentStatusSummary(for: test, treatments: test.treatments, config: poolConfig)
    }

    func previousTest(before test: PoolTest, in tests: [PoolTest]) -> PoolTest? {
        tests
            .filter { $0.id != test.id && $0.date < test.date }
            .sorted { $0.date > $1.date }
            .first
    }

    func recentHistory(before test: PoolTest, in tests: [PoolTest], limit: Int = 10) -> [PoolTest] {
        Array(
            tests
                .filter { $0.id != test.id && $0.date < test.date }
                .sorted { $0.date > $1.date }
                .prefix(limit)
        )
    }

    // MARK: - Generate Recommendations

    @MainActor
    func generateRecommendations(
        for test: PoolTest,
        recentTests: [PoolTest],
        modelContext: ModelContext,
        replacingCompletedPlan: Bool = false
    ) async {
        isGeneratingRecommendations = true
        lastError = nil

        defer { isGeneratingRecommendations = false }

        do {
            guard let service = aiService else { return }
            var effectiveConfig = poolConfig
            effectiveConfig.testMethod = test.testMethod

            let request = AIRecommendationRequest(
                currentTest: test,
                recentHistory: recentTests,
                poolConfig: effectiveConfig
            )

            let response = try await service.generateRecommendations(for: request)

            // Remove the previous AI-generated plan. Completed steps are preserved for normal regeneration,
            // skipped steps are preserved for normal regeneration, but both are replaced when
            // edited test readings require a fresh treatment plan.
            test.treatments
                .filter { $0.isAIGenerated && (replacingCompletedPlan || (!$0.isCompleted && !$0.isSkipped)) }
                .forEach {
                    NotificationService.shared.cancelTreatmentReminder(for: $0)
                    modelContext.delete($0)
                }

            // Insert new treatments
            for template in response.treatments {
                let treatment = template.toTreatment(linkedTo: test)
                modelContext.insert(treatment)
            }

            // Store the assessment text
            test.aiAssessment = response.assessmentText

        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func recalculateRecommendations(
        for test: PoolTest,
        recentTests: [PoolTest],
        modelContext: ModelContext
    ) async throws {
        guard let service = aiService else { return }

        isGeneratingRecommendations = true
        lastError = nil
        defer { isGeneratingRecommendations = false }

        var effectiveConfig = poolConfig
        effectiveConfig.testMethod = test.testMethod

        let request = AIRecommendationRequest(
            currentTest: test,
            recentHistory: recentTests,
            poolConfig: effectiveConfig
        )

        do {
            let response = try await service.generateRecommendations(for: request)
            let stateSnapshots = safelyMatchableTreatmentStates(from: test.treatments)

            test.treatments
                .filter(\.isAIGenerated)
                .forEach {
                    NotificationService.shared.cancelTreatmentReminder(for: $0)
                    modelContext.delete($0)
                }

            let regeneratedTreatments = response.treatments.map { $0.toTreatment(linkedTo: test) }
            let regeneratedKeyCounts = Dictionary(
                grouping: regeneratedTreatments.compactMap(\.statePreservationKey),
                by: { $0 }
            ).mapValues(\.count)

            for treatment in regeneratedTreatments {
                if
                    let key = treatment.statePreservationKey,
                    regeneratedKeyCounts[key] == 1,
                    let snapshot = stateSnapshots[key] {
                    treatment.applyStateSnapshot(snapshot)
                }
                modelContext.insert(treatment)
            }

            test.aiAssessment = response.assessmentText
            try modelContext.save()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func safelyMatchableTreatmentStates(from treatments: [Treatment]) -> [String: TreatmentStateSnapshot] {
        let snapshots = treatments
            .filter { $0.isAIGenerated && ($0.isCompleted || $0.isSkipped) }
            .compactMap { treatment -> (String, TreatmentStateSnapshot)? in
                guard let key = treatment.statePreservationKey else { return nil }
                return (key, TreatmentStateSnapshot(treatment: treatment))
            }
        let grouped = Dictionary(grouping: snapshots, by: \.0)

        return grouped.reduce(into: [:]) { result, item in
            guard item.value.count == 1, let snapshot = item.value.first?.1 else { return }
            result[item.key] = snapshot
        }
    }

    // MARK: - Complete Treatment

    @MainActor
    func completeTreatment(_ treatment: Treatment) {
        treatment.isCompleted = true
        treatment.completedAt = Date()
        treatment.isSkipped = false
        treatment.skippedAt = nil
    }

    @MainActor
    func markTreatmentIncomplete(_ treatment: Treatment) {
        treatment.isCompleted = false
        treatment.completedAt = nil
        NotificationService.shared.cancelTreatmentReminder(for: treatment)
    }

    @MainActor
    func skipTreatment(_ treatment: Treatment) {
        NotificationService.shared.cancelTreatmentReminder(for: treatment)
        treatment.isSkipped = true
        treatment.skippedAt = Date()
        treatment.isCompleted = false
        treatment.completedAt = nil
    }

    @MainActor
    func restoreTreatment(_ treatment: Treatment) {
        treatment.isSkipped = false
        treatment.skippedAt = nil
    }

    // MARK: - Pending Treatments (across all tests)

    func pendingTreatments(from tests: [PoolTest]) -> [Treatment] {
        tests
            .flatMap { $0.treatments }
            .filter { !$0.isCompleted && !$0.isSkipped }
            .sorted { $0.urgency.sortOrder < $1.urgency.sortOrder }
    }

    func completedTreatments(from tests: [PoolTest]) -> [Treatment] {
        tests
            .flatMap { $0.treatments }
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    func nextTestRecommendation(for test: PoolTest, in tests: [PoolTest]) -> NextTestRecommendation {
        let allTreatments = test.treatments
            .filter { !($0.isSkipped && $0.isWatchlistItem) }
            .sorted { $0.sortOrder < $1.sortOrder }
        let treatmentSteps = allTreatments.filter { !$0.isWatchlistItem }
        let watchlist = allTreatments.filter { $0.isWatchlistItem }

        return nextTestRecommendationEngine.recommendation(
            for: test,
            treatmentSteps: treatmentSteps,
            watchlist: watchlist,
            recentHistory: recentHistory(before: test, in: tests, limit: 10),
            config: poolConfig
        )
    }

    @MainActor
    func replaceNextPoolTestReminder(for latestTest: PoolTest?, allTests: [PoolTest]) async {
        guard poolConfig.enableNextPoolTestReminders else {
            NotificationService.shared.cancelNextPoolTestReminder()
            return
        }

        await NotificationService.shared.checkAuthorizationStatus()
        guard NotificationService.shared.isAuthorized, let latestTest else {
            NotificationService.shared.cancelNextPoolTestReminder()
            return
        }

        let recommendation = nextTestRecommendation(for: latestTest, in: allTests)
        _ = await NotificationService.shared.replaceNextPoolTestReminder(
            at: recommendation.recommendedDate,
            reason: recommendation.scheduledReason
        )
    }

    @MainActor
    func deletePoolTest(_ test: PoolTest, modelContext: ModelContext) throws {
        for treatment in test.treatments {
            NotificationService.shared.cancelTreatmentReminder(for: treatment)
        }

        modelContext.delete(test)
        try modelContext.save()
    }

    @MainActor
    func deletePoolTestAndRefreshHistory(
        _ test: PoolTest,
        allTests: [PoolTest],
        modelContext: ModelContext
    ) async throws {
        let deletedID = test.id
        let deletedDate = test.date
        let remainingTests = allTests
            .filter { $0.id != deletedID }
            .sorted { $0.date < $1.date }

        try deletePoolTest(test, modelContext: modelContext)

        for remainingTest in remainingTests where remainingTest.date > deletedDate {
            let recentTests = recentHistory(before: remainingTest, in: remainingTests, limit: 10)
            await generateRecommendations(
                for: remainingTest,
                recentTests: recentTests,
                modelContext: modelContext,
                replacingCompletedPlan: false
            )
        }

        try modelContext.save()

        let latestRemaining = remainingTests.sorted { $0.date > $1.date }.first
        await replaceNextPoolTestReminder(for: latestRemaining, allTests: remainingTests)
    }

    // MARK: - Trend Analysis

    /// Returns true if a parameter has been worsening over the last N tests
    func isTrendingBad(parameter: String, in tests: [PoolTest], count: Int = 3) -> Bool {
        let recent = Array(tests.prefix(count))
        guard recent.count >= 2 else { return false }

        let values: [Double] = recent.compactMap { test in
            switch parameter {
            case "pH":              return test.pH
            case "freeChlorine":    return test.freeChlorine
            case "totalAlkalinity": return test.totalAlkalinity
            default:                return nil
            }
        }

        guard values.count >= 2 else { return false }

        // Check if the latest reading moved further from ideal
        let engine = ChemistryEngine()
        let latestStatus = parameterStatus(parameter: parameter, value: values[0], engine: engine)
        let prevStatus = parameterStatus(parameter: parameter, value: values[1], engine: engine)

        // Trending bad = status got worse (higher severity)
        return severity(latestStatus) > severity(prevStatus)
    }

    private func parameterStatus(parameter: String, value: Double, engine: ChemistryEngine) -> ChemicalStatus {
        switch parameter {
        case "pH":              return engine.pHStatus(value)
            case "freeChlorine":    return engine.freeChlorineStatus(value, cyanuricAcid: nil)
        case "totalAlkalinity": return engine.totalAlkalinityStatus(value)
        default:                return .testing
        }
    }

    private func severity(_ status: ChemicalStatus) -> Int {
        switch status {
        case .ideal:                   return 0
        case .slightlyLow, .slightlyHigh: return 1
        case .low, .high:              return 2
        case .critical:                return 3
        case .testing:                 return -1
        }
    }
}

private struct TreatmentStateSnapshot {
    let isCompleted: Bool
    let completedAt: Date?
    let isSkipped: Bool
    let skippedAt: Date?

    init(treatment: Treatment) {
        isCompleted = treatment.isCompleted
        completedAt = treatment.completedAt
        isSkipped = treatment.isSkipped
        skippedAt = treatment.skippedAt
    }
}

private extension Treatment {
    var statePreservationKey: String? {
        guard let productIdentifier, !productIdentifier.isEmpty else { return nil }
        return [
            productIdentifier,
            targetParameter,
            expectedEffectParameter,
            unit
        ].joined(separator: "|")
    }

    func applyStateSnapshot(_ snapshot: TreatmentStateSnapshot) {
        isCompleted = snapshot.isCompleted
        completedAt = snapshot.completedAt
        isSkipped = snapshot.isSkipped
        skippedAt = snapshot.skippedAt
    }
}
