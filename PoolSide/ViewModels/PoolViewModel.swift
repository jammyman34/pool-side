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
    private let workflowEngine = TreatmentWorkflowEngine()
    private var aiService: AIService?

    /// Notification effects seam. Defaults to the production `NotificationService.shared`; tests inject a
    /// spy. Resolved lazily inside @MainActor methods so the singleton is not touched at init.
    var notificationSchedulerOverride: PoolNotificationScheduling?
    @MainActor
    private var notifications: PoolNotificationScheduling { notificationSchedulerOverride ?? NotificationService.shared }

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

    func refreshConfigFromStorage() {
        poolConfig = PoolConfiguration.current
    }

    func refreshConfigFromStorage(reconcilingWith tests: [PoolTest]) {
        var latest = PoolConfiguration.current
        let recovered = PoolConfiguration.recoveredFromTestHistory(latest, tests: tests)
        if recovered != latest {
            PoolConfiguration.current = recovered
            latest = recovered
        }
        poolConfig = latest
    }

    func saveConfig(_ config: PoolConfiguration, marksEquipmentChoicesExplicit: Bool = false) {
        var normalized = config
        normalized.normalizeChemicalPreferences()
        poolConfig = normalized
        PoolConfiguration.current = normalized
        if marksEquipmentChoicesExplicit {
            PoolConfiguration.markEquipmentChoicesExplicit(normalized)
        }
    }

    func updateConfig(_ update: (inout PoolConfiguration) -> Void) {
        var latest = PoolConfiguration.current
        update(&latest)
        saveConfig(latest)
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
            let treatmentsToDelete = test.treatments
                .filter { $0.isAIGenerated && (replacingCompletedPlan || (!$0.isCompleted && !$0.isSkipped)) }
            deleteTreatments(treatmentsToDelete, from: test, modelContext: modelContext)

            // Insert new treatments
            for template in response.treatments {
                let treatment = template.toTreatment(linkedTo: test)
                insertAndLinkTreatment(treatment, to: test, modelContext: modelContext)
            }
            appendWorkflowCheckSteps(to: test, modelContext: modelContext)

            // Store the assessment text
            test.aiAssessment = response.assessmentText
            runSwimabilityV2ComparisonIfEnabled(for: request, context: "Normal Generation")

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

            let treatmentsToDelete = test.treatments.filter(\.isAIGenerated)
            deleteTreatments(treatmentsToDelete, from: test, modelContext: modelContext)

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
                insertAndLinkTreatment(treatment, to: test, modelContext: modelContext)
            }
            appendWorkflowCheckSteps(to: test, modelContext: modelContext)

            test.aiAssessment = response.assessmentText
            try modelContext.save()
            runSwimabilityV2ComparisonIfEnabled(for: request, context: "Recalculation")
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    @MainActor
    private func deleteTreatments(_ treatments: [Treatment], from test: PoolTest, modelContext: ModelContext) {
        let deletedIDs = Set(treatments.map(\.id))
        treatments.forEach {
            notifications.cancelTreatmentReminder(for: $0)
            modelContext.delete($0)
        }
        test.treatments.removeAll { deletedIDs.contains($0.id) }
    }

    @MainActor
    private func insertAndLinkTreatment(_ treatment: Treatment, to test: PoolTest, modelContext: ModelContext) {
        modelContext.insert(treatment)
        if !test.treatments.contains(where: { $0.id == treatment.id }) {
            test.treatments.append(treatment)
        }
    }

    @MainActor
    private func appendWorkflowCheckSteps(to test: PoolTest, modelContext: ModelContext) {
        let workflowEngine = TreatmentWorkflowEngine()
        let treatmentSteps = test.treatments
            .filter { !$0.isWatchlistItem && !$0.isFocusedCheckStep }
            .sorted { $0.sortOrder < $1.sortOrder }
        let existingParentIDs = Set(
            test.treatments
                .filter(\.isFocusedCheckStep)
                .compactMap(\.parentTreatmentID)
        )
        var nextSortOrder = (test.treatments.map(\.sortOrder).max() ?? 0) + 1

        for treatment in treatmentSteps where !existingParentIDs.contains(treatment.id) {
            guard let check = workflowEngine.makeCheckStep(after: treatment, sortOrder: treatment.sortOrder + 1) else { continue }
            shiftSortOrders(in: test, startingAt: check.sortOrder)
            if test.treatments.contains(where: { $0.sortOrder == check.sortOrder }) {
                check.sortOrder = nextSortOrder
                nextSortOrder += 1
            }
            insertAndLinkTreatment(check, to: test, modelContext: modelContext)
        }
    }

    private func shiftSortOrders(in test: PoolTest, startingAt sortOrder: Int) {
        for treatment in test.treatments where treatment.sortOrder >= sortOrder {
            treatment.sortOrder += 1
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

    private func runSwimabilityV2ComparisonIfEnabled(for request: AIRecommendationRequest, context: String) {
        guard RecommendationV2FeatureFlags.swimabilityV2ComparisonEnabled else { return }

        #if DEBUG
        print(swimabilityV2Comparison(for: request, context: context).developerDescription)
        #endif
    }

    @MainActor
    @discardableResult
    func runSwimabilityV2ComparisonAfterTreatmentStateChange(
        for test: PoolTest,
        recentTests: [PoolTest],
        context: String,
        generatedAt: Date = Date()
    ) -> SwimabilityV2Comparison? {
        guard RecommendationV2FeatureFlags.swimabilityV2ComparisonEnabled else { return nil }

        var effectiveConfig = poolConfig
        effectiveConfig.testMethod = test.testMethod
        let request = AIRecommendationRequest(
            currentTest: test,
            recentHistory: recentTests,
            poolConfig: effectiveConfig
        )
        let comparison = swimabilityV2Comparison(
            for: request,
            context: context,
            generatedAt: generatedAt
        )

        #if DEBUG
        print(comparison.developerDescription)
        #endif

        return comparison
    }

    @MainActor
    @discardableResult
    func runSwimabilityV2JumpAheadComparison(
        for test: PoolTest,
        recentTests: [PoolTest],
        offset: TreatmentPlanDeveloperJumpAheadOffset,
        actualDate: Date = Date()
    ) -> SwimabilityV2Comparison? {
        guard RecommendationV2FeatureFlags.swimabilityV2ComparisonEnabled else { return nil }

        var effectiveConfig = poolConfig
        effectiveConfig.testMethod = test.testMethod
        let request = AIRecommendationRequest(
            currentTest: test,
            recentHistory: recentTests,
            poolConfig: effectiveConfig
        )
        let simulatedDate = actualDate.addingTimeInterval(offset.timeInterval)
        let comparison = swimabilityV2Comparison(
            for: request,
            context: "Developer Jump Ahead \(offset.displayName)",
            generatedAt: simulatedDate,
            actualEvaluationTimestamp: actualDate
        )

        #if DEBUG
        print(comparison.developerDescription)
        #endif

        return comparison
    }

    func swimabilityV2Comparison(
        for request: AIRecommendationRequest,
        context: String,
        generatedAt: Date = Date(),
        actualEvaluationTimestamp: Date? = nil
    ) -> SwimabilityV2Comparison {
        let normalizedState = PoolStateNormalizer().normalize(request: request, evaluationDate: generatedAt)
        let assessment = SwimabilityV2Engine().assess(request: request, evaluationDate: generatedAt)
        let existingStatus = chemistryEngine.currentStatusSummary(
            for: request.currentTest,
            treatments: request.currentTest.treatments,
            config: request.poolConfig
        )
        let existingScore = chemistryEngine.overallScore(
            for: request.currentTest,
            previousTest: request.recentHistory.first,
            recentHistory: request.recentHistory,
            config: request.poolConfig
        )
        let differences = existingStatus == assessment.state.rawValue
            ? []
            : ["V1 status and v2 observed Swimability use different decision models."]
        return SwimabilityV2Comparison(
            existingStatus: existingStatus,
            existingScore: existingScore,
            v2Assessment: assessment,
            meaningfulDifferences: differences,
            generatedAt: generatedAt,
            actualEvaluationTimestamp: actualEvaluationTimestamp,
            normalizedPoolState: normalizedState,
            evaluationContext: context
        )
    }

    // MARK: - Swim Readiness (production authority)

    /// The single production swim-readiness authority: SwimabilityV2Engine over the canonical normalized
    /// state and ChemistryPolicy gates. Not gated by any DEBUG comparison flag. Presentation layers
    /// (e.g. Dashboard) map this assessment to UI; they must not re-derive readiness themselves.
    func swimReadinessAssessment(
        for test: PoolTest,
        in tests: [PoolTest],
        evaluationDate: Date = Date()
    ) -> SwimabilityV2Assessment {
        var effectiveConfig = poolConfig
        effectiveConfig.testMethod = test.testMethod
        let request = AIRecommendationRequest(
            currentTest: test,
            recentHistory: recentHistory(before: test, in: tests, limit: 10),
            poolConfig: effectiveConfig
        )
        return SwimabilityV2Engine().assess(request: request, evaluationDate: evaluationDate)
    }

    // MARK: - Complete Treatment (single production authority)

    /// The canonical treatment-completion routine. Views call this and must not independently mutate
    /// completion state, compute verification timing, or schedule notifications.
    ///
    /// Establishes completion timing, then — per the Check-owned verification model — schedules the
    /// dependent focused Check's targeted reminder for its due time (completedAt + policy delay). A plain
    /// "next step" reminder is scheduled ONLY when a real subsequent chemical treatment follows (never for
    /// a Check, which already owns its reminder). Finally refreshes the routine Next Full Pool Test.
    @MainActor
    func completeTreatment(_ treatment: Treatment, in tests: [PoolTest], modelContext: ModelContext) async {
        treatment.isCompleted = true
        treatment.completedAt = Date()
        treatment.isSkipped = false
        treatment.skippedAt = nil

        await notifications.checkAuthorizationStatus()
        let remindersEnabled = poolConfig.enableTreatmentStepReminders && notifications.isAuthorized

        if let check = dependentCheck(for: treatment) {
            // Check owns the verification notification, scheduled for its derived due time.
            if remindersEnabled,
               let due = workflowEngine.availableDate(for: check, in: treatment.poolTest?.treatments ?? []) {
                check.checkReminderNotificationIdentifier = await notifications.scheduleCheckReminder(
                    checkID: check.id,
                    parameters: check.checkParameters.isEmpty ? [check.targetParameter] : check.checkParameters,
                    at: due
                )
            }
        } else if treatment.minutesBeforeNext > 0, let next = nextChemicalTreatment(after: treatment) {
            // Only a genuine subsequent chemical treatment gets a next-step reminder.
            if remindersEnabled {
                let identifier = await notifications.scheduleTreatmentStepReminder(
                    treatmentID: treatment.id,
                    nextTreatmentName: next.chemicalName,
                    afterMinutes: treatment.minutesBeforeNext
                )
                treatment.reminderNotificationIdentifier = identifier
                treatment.stepReminderNotificationIdentifier = identifier
            }
        }

        try? modelContext.save()
        let anchorTest = treatment.poolTest ?? latestTest(in: tests)
        await replaceNextPoolTestReminder(for: anchorTest, allTests: tests)
        if let anchorTest {
            runSwimabilityV2ComparisonAfterTreatmentStateChange(
                for: anchorTest,
                recentTests: recentHistory(before: anchorTest, in: tests),
                context: "Treatment Completed"
            )
        }
    }

    /// The uncompleted focused Check that verifies this treatment, if one exists and is still actionable.
    @MainActor
    func dependentCheck(for treatment: Treatment) -> Treatment? {
        guard !treatment.isFocusedCheckStep else { return nil }
        return treatment.poolTest?.treatments.first {
            $0.isFocusedCheckStep && $0.parentTreatmentID == treatment.id && !$0.isCompleted && !$0.isSkipped
        }
    }

    /// The next actionable chemical treatment step after this one (excludes Checks and watchlist items).
    private func nextChemicalTreatment(after treatment: Treatment) -> Treatment? {
        (treatment.poolTest?.treatments ?? [])
            .filter { !$0.isWatchlistItem && !$0.isFocusedCheckStep && !$0.isCompleted && !$0.isSkipped && $0.id != treatment.id && $0.amount > 0 }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { $0.sortOrder > treatment.sortOrder }
    }

    private func latestTest(in tests: [PoolTest]) -> PoolTest? {
        tests.sorted { $0.date > $1.date }.first
    }

    /// §11–12 — A newly logged full test can verify (supersede) a prior pending focused Check, but ONLY
    /// when ALL of the following hold: the full test is newer than the parent treatment's completion; it
    /// is at or after the Check's due time; it measures every Check parameter; and no other treatment
    /// affecting those parameters completed between the parent and this test. A full test logged before
    /// the Check is due never verifies (§12). When a Check is superseded, its verification notification is
    /// cancelled so the user is not nagged to repeat a measurement they have already provided.
    @MainActor
    func resolveChecksSatisfiedByFullTest(_ fullTest: PoolTest, allTests: [PoolTest], modelContext: ModelContext) {
        // A partial focused-check entry is not a full test and never supersedes another Check.
        guard !fullTest.isFocusedCheck else { return }

        let allTreatments = allTests.flatMap(\.treatments)
        let pendingChecks = allTreatments.filter {
            $0.isFocusedCheckStep && !$0.isCompleted && !$0.isSkipped
        }
        guard !pendingChecks.isEmpty else { return }

        var didResolveAny = false
        for check in pendingChecks {
            guard
                let parentID = check.parentTreatmentID,
                let parent = allTreatments.first(where: { $0.id == parentID }),
                parent.isCompleted,
                let parentCompletedAt = parent.completedAt
            else { continue }

            // (1) The full test post-dates the parent's completion.
            guard fullTest.date > parentCompletedAt else { continue }
            // (2) The full test is at or after the Check's due time (§12: earlier tests never verify).
            guard
                let dueDate = workflowEngine.availableDate(for: check, in: parent.poolTest?.treatments ?? []),
                fullTest.date >= dueDate
            else { continue }
            // (3) The full test measures every Check parameter.
            let params = check.checkParameters.isEmpty ? [check.targetParameter] : check.checkParameters
            guard params.allSatisfy({ fullTestContainsParameter(fullTest, $0) }) else { continue }
            // (4) No other treatment affecting those parameters completed between the parent and this test.
            let families = Set(params.map(parameterFamily))
            let hasInterveningTreatment = allTreatments.contains { other in
                other.id != parent.id
                    && other.isCompleted
                    && !other.isFocusedCheckStep
                    && (other.completedAt.map { $0 > parentCompletedAt && $0 < fullTest.date } ?? false)
                    && families.contains(parameterFamily(other.targetParameter))
            }
            guard !hasInterveningTreatment else { continue }

            // All conditions hold — this full test IS the verification the Check was waiting for.
            check.isCompleted = true
            check.completedAt = fullTest.date
            check.checkResultTestID = fullTest.id
            notifications.cancel(identifier: check.checkReminderNotificationIdentifier)
            check.checkReminderNotificationIdentifier = nil
            didResolveAny = true
        }

        if didResolveAny {
            try? modelContext.save()
        }
    }

    /// Canonical parameter family so a chlorine treatment is recognized as affecting both FC and CC.
    private func parameterFamily(_ parameter: String) -> String {
        switch parameter {
        case "freeChlorine", "combinedChlorine", "totalChlorine": return "chlorine"
        default: return parameter
        }
    }

    /// A standard full test always records the core chemistry parameters; salt only when configured.
    private func fullTestContainsParameter(_ test: PoolTest, _ parameter: String) -> Bool {
        switch parameter {
        case "freeChlorine", "combinedChlorine", "totalChlorine", "pH",
             "totalAlkalinity", "calciumHardness", "cyanuricAcid":
            return true
        case "saltLevel":
            return test.saltLevel != nil
        default:
            return false
        }
    }

    @MainActor
    func markTreatmentIncomplete(_ treatment: Treatment) {
        treatment.isCompleted = false
        treatment.completedAt = nil
        notifications.cancel(identifier: treatment.reminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.stepReminderNotificationIdentifier)
        treatment.reminderNotificationIdentifier = nil
        treatment.stepReminderNotificationIdentifier = nil
        // A treatment reverted to incomplete invalidates its Check's due-time notification.
        if let check = treatment.poolTest?.treatments.first(where: { $0.isFocusedCheckStep && $0.parentTreatmentID == treatment.id }) {
            notifications.cancel(identifier: check.checkReminderNotificationIdentifier)
            check.checkReminderNotificationIdentifier = nil
        }
    }

    @MainActor
    func skipTreatment(_ treatment: Treatment) {
        notifications.cancel(identifier: treatment.reminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.stepReminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.retestReminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.checkReminderNotificationIdentifier)
        treatment.reminderNotificationIdentifier = nil
        treatment.stepReminderNotificationIdentifier = nil
        treatment.retestReminderNotificationIdentifier = nil
        treatment.checkReminderNotificationIdentifier = nil

        // Skipping a parent treatment makes its dependent Check inapplicable — it must never become
        // actionable without the treatment having been performed. Cancel its notification and skip it.
        if !treatment.isFocusedCheckStep,
           let check = treatment.poolTest?.treatments.first(where: { $0.isFocusedCheckStep && $0.parentTreatmentID == treatment.id }),
           !check.isCompleted {
            notifications.cancel(identifier: check.checkReminderNotificationIdentifier)
            check.checkReminderNotificationIdentifier = nil
            check.isSkipped = true
            check.skippedAt = Date()
        }

        treatment.isSkipped = true
        treatment.skippedAt = Date()
        treatment.isCompleted = false
        treatment.completedAt = nil
    }

    @MainActor
    func restoreTreatment(_ treatment: Treatment) {
        treatment.isSkipped = false
        treatment.skippedAt = nil
        // Restore a parent's dependent Check to a non-skipped upcoming state. It cannot become due until
        // the parent is completed (its due time derives from the parent's completedAt).
        if !treatment.isFocusedCheckStep,
           let check = treatment.poolTest?.treatments.first(where: { $0.isFocusedCheckStep && $0.parentTreatmentID == treatment.id }),
           check.isSkipped, !check.isCompleted {
            check.isSkipped = false
            check.skippedAt = nil
        }
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
        let treatmentSteps = allTreatments.filter { !$0.isWatchlistItem && !$0.isFocusedCheckStep }
        let watchlist = allTreatments.filter { $0.isWatchlistItem }

        return nextTestRecommendationEngine.recommendation(
            for: test,
            treatmentSteps: treatmentSteps,
            watchlist: watchlist,
            recentHistory: recentHistory(before: test, in: tests, limit: 10),
            config: poolConfig,
            outstandingCheckDueDates: outstandingCheckDueDates(in: tests)
        )
    }

    /// Due dates of all pending focused Checks whose parent treatment has been completed, across every
    /// test. Used to keep routine full-test timing from competing with an outstanding verification.
    private func outstandingCheckDueDates(in tests: [PoolTest]) -> [Date] {
        let allTreatments = tests.flatMap(\.treatments)
        return allTreatments.compactMap { check -> Date? in
            guard
                check.isFocusedCheckStep, !check.isCompleted, !check.isSkipped,
                let parentID = check.parentTreatmentID,
                let parent = allTreatments.first(where: { $0.id == parentID }),
                parent.isCompleted
            else { return nil }
            return workflowEngine.availableDate(for: check, in: parent.poolTest?.treatments ?? [])
        }
    }

    @MainActor
    @discardableResult
    func saveFocusedCheck(
        _ checkStep: Treatment,
        values: [String: Double],
        for test: PoolTest,
        allTests: [PoolTest],
        modelContext: ModelContext,
        measuredAt: Date = Date()
    ) async throws -> FocusedCheckResult {
        // Capture the pre-check readings so the outcome can describe movement (improved / no change /
        // crossed past) at the method's measurement resolution.
        let checkedParameters = checkStep.checkParameters.isEmpty ? Array(values.keys) : checkStep.checkParameters
        let priorValues = priorValuesForCheck(checkedParameters, in: test)

        applyFocusedCheckValues(values, to: test, measuredAt: measuredAt)
        test.isFocusedCheck = test.isFocusedCheck || !values.isEmpty
        test.focusedCheckParameters = Array(Set(test.focusedCheckParameters + values.keys)).sorted()
        checkStep.isCompleted = true
        checkStep.completedAt = measuredAt
        checkStep.isSkipped = false
        checkStep.skippedAt = nil
        checkStep.focusedCheckSummary = focusedCheckSummary(values)
        checkStep.checkResultTestID = test.id
        // The Check owns its verification notification; completing it cancels that reminder so it never
        // fires for an action the user has already performed.
        notifications.cancel(identifier: checkStep.checkReminderNotificationIdentifier)
        checkStep.checkReminderNotificationIdentifier = nil

        let history = recentHistory(before: test, in: allTests, limit: 10)
        await generateRecommendations(
            for: test,
            recentTests: history,
            modelContext: modelContext,
            replacingCompletedPlan: false
        )
        try modelContext.save()

        // The focused Check produced new evidence and a regenerated plan; recompute the routine full-test
        // reminder from the new effective state so a now-stale routine date is not silently retained.
        let mergedTests = allTests.contains(where: { $0.id == test.id }) ? allTests : ([test] + allTests)
        await replaceNextPoolTestReminder(for: latestTest(in: mergedTests) ?? test, allTests: mergedTests)

        // Derive the explicit closure outcome from the POST-check reassessment (ChemistryPolicy operating
        // state + the regenerated plan), consuming Swimability V2 for overall readiness.
        let swimState = swimReadinessAssessment(for: test, in: mergedTests).state
        return FocusedCheckOutcomeEvaluator().result(
            checkedParameters: checkedParameters,
            priorValues: priorValues,
            measuredValues: values,
            postCheckTest: test,
            postCheckTreatments: test.treatments,
            config: poolConfig,
            swimState: swimState
        )
    }

    private func priorValuesForCheck(_ parameters: [String], in test: PoolTest) -> [String: Double] {
        var result: [String: Double] = [:]
        for parameter in parameters {
            switch parameter {
            case "freeChlorine": result[parameter] = test.freeChlorine
            case "combinedChlorine": result[parameter] = test.combinedChlorine
            case "pH": result[parameter] = test.pH
            case "totalAlkalinity": result[parameter] = test.totalAlkalinity
            case "calciumHardness": result[parameter] = test.calciumHardness
            case "cyanuricAcid": result[parameter] = test.cyanuricAcid
            case "saltLevel": if let salt = test.saltLevel { result[parameter] = salt }
            default: break
            }
        }
        return result
    }

    private func applyFocusedCheckValues(_ values: [String: Double], to test: PoolTest, measuredAt: Date) {
        if let fc = values["freeChlorine"] {
            let currentCC = values["combinedChlorine"] ?? test.combinedChlorine
            test.freeChlorine = fc
            test.totalChlorine = fc + currentCC
            test.freeChlorineMeasuredAt = measuredAt
            test.totalChlorineMeasuredAt = measuredAt
        }
        if let cc = values["combinedChlorine"] {
            test.totalChlorine = test.freeChlorine + cc
            test.totalChlorineMeasuredAt = measuredAt
        }
        if let pH = values["pH"] {
            test.pH = pH
            test.pHMeasuredAt = measuredAt
        }
        if let totalAlkalinity = values["totalAlkalinity"] {
            test.totalAlkalinity = totalAlkalinity
            test.totalAlkalinityMeasuredAt = measuredAt
        }
        if let calciumHardness = values["calciumHardness"] {
            test.calciumHardness = calciumHardness
            test.calciumHardnessMeasuredAt = measuredAt
        }
        if let cyanuricAcid = values["cyanuricAcid"] {
            test.cyanuricAcid = cyanuricAcid
            test.cyanuricAcidMeasuredAt = measuredAt
        }
        if let saltLevel = values["saltLevel"] {
            test.saltLevel = saltLevel
            test.saltLevelMeasuredAt = measuredAt
        }
    }

    private func focusedCheckSummary(_ values: [String: Double]) -> String {
        values
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(displayName(forFocusedCheckParameter: key)) \(value.formattedTreatmentAmount)"
            }
            .joined(separator: ", ")
    }

    private func displayName(forFocusedCheckParameter parameter: String) -> String {
        switch parameter {
        case "freeChlorine": return "FC"
        case "combinedChlorine": return "CC"
        case "pH": return "pH"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        case "saltLevel": return "Salt"
        default: return parameter
        }
    }

    @MainActor
    func replaceNextPoolTestReminder(for latestTest: PoolTest?, allTests: [PoolTest]) async {
        guard poolConfig.enableNextPoolTestReminders else {
            notifications.cancelNextPoolTestReminder()
            return
        }

        await notifications.checkAuthorizationStatus()
        guard notifications.isAuthorized, let latestTest else {
            notifications.cancelNextPoolTestReminder()
            return
        }

        let recommendation = nextTestRecommendation(for: latestTest, in: allTests)
        guard let recommendedDate = recommendation.recommendedDate else {
            notifications.cancelNextPoolTestReminder()
            return
        }

        _ = await notifications.replaceNextPoolTestReminder(
            at: recommendedDate,
            reason: recommendation.scheduledReason
        )
    }

    @MainActor
    func deletePoolTest(_ test: PoolTest, modelContext: ModelContext) throws {
        for treatment in test.treatments {
            notifications.cancelTreatmentReminder(for: treatment)
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
