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
        guard let stored = PoolConfiguration.persisted else {
            // No valid persisted config yet (first use, or a load failure). Surface defaults in memory for
            // display, but never persist them here — writing back would cement struct defaults over an
            // absent/recoverable config. The intentional setup/Settings save paths own first persistence.
            poolConfig = PoolConfiguration.current
            return
        }
        let recovered = PoolConfiguration.recoveredFromTestHistory(stored, tests: tests)
        if recovered != stored {
            PoolConfiguration.current = recovered
        }
        poolConfig = recovered
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

    /// Backfills missing coordinates from a saved location string by forward-geocoding it. Fixes weather
    /// for users who typed a location (which never captured coordinates) rather than using "Use Current
    /// Location". Returns true when coordinates are available afterward.
    @MainActor
    @discardableResult
    func resolveCoordinatesIfNeeded() async -> Bool {
        if poolConfig.latitude != nil && poolConfig.longitude != nil { return true }
        guard !poolConfig.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        guard let coords = await PoolLocationService.coordinates(for: poolConfig.location) else { return false }
        var updated = poolConfig
        updated.latitude = coords.latitude
        updated.longitude = coords.longitude
        saveConfig(updated)
        return true
    }

    func updateConfig(_ update: (inout PoolConfiguration) -> Void) {
        // A partial read-modify-write (e.g. "save this test method / product as default") must never turn a
        // missing/invalid persisted config into saved struct defaults. With no valid stored config there is
        // nothing to amend, so leave storage untouched — intentional setup/Settings saves own creation.
        guard var latest = PoolConfiguration.persisted else { return }
        update(&latest)
        saveConfig(latest)
    }

    /// Reprices unfinished AI-generated chemical treatment steps in the active (latest) plan to the
    /// current product preferences, recalculating dose in place. This never rewrites history: completed
    /// and skipped treatments, completed/skipped Checks, step identity, sequencing, and notification
    /// ownership are all preserved. Only pending future chemical steps are updated, so the reprice does
    /// not carry a theoretical remainder and does not change the score (chemistry evidence is unchanged).
    @MainActor
    @discardableResult
    func repriceUnfinishedTreatmentsForPreferenceChange(in tests: [PoolTest], modelContext: ModelContext) -> Bool {
        guard let latest = latestTest(in: tests) else { return false }
        let unfinished = latest.treatments.filter {
            $0.isAIGenerated && !$0.isCompleted && !$0.isSkipped
                && !$0.isFocusedCheckStep && !$0.isWatchlistItem && $0.amount > 0
        }

        var didChange = false
        for treatment in unfinished {
            guard let newProductID = preferredProductID(for: treatment) else { continue }
            let newGlobalRaw = newProductID.rawValue

            // Already the preferred product — just realign the recorded global-preference identifier.
            if treatment.productIdentifier == newGlobalRaw {
                if treatment.globalPreferenceIdentifier != newGlobalRaw {
                    treatment.globalPreferenceIdentifier = newGlobalRaw
                    didChange = true
                }
                continue
            }

            guard let repriced = chemistryEngine.repricedTreatmentTemplate(
                from: treatment, test: latest, productID: newProductID, config: poolConfig
            ) else { continue }

            treatment.chemicalName = repriced.chemicalName
            treatment.actionDescription = repriced.actionDescription
            treatment.amount = repriced.amount
            treatment.unit = repriced.unit
            treatment.instructions = repriced.instructions
            treatment.productIdentifier = repriced.productID?.rawValue
            treatment.globalPreferenceIdentifier = newGlobalRaw
            treatment.calculatedDoseBeforeCap = repriced.calculatedDoseBeforeCap
            treatment.calculatedDoseBeforeCapUnit = repriced.calculatedDoseBeforeCapUnit
            treatment.wasDoseCapped = repriced.wasDoseCapped
            treatment.expectedDelta = repriced.expectedDelta
            didChange = true
        }

        if didChange { try? modelContext.save() }
        return didChange
    }

    /// The product the current preferences would use for a given treatment's parameter and direction.
    private func preferredProductID(for treatment: Treatment) -> ChemicalProductID? {
        switch treatment.targetParameter {
        case "freeChlorine":
            return poolConfig.chlorinePreference.productID
        case "pH":
            return treatment.isAcidTreatment
                ? poolConfig.pHDecreaserPreference.productID
                : poolConfig.pHIncreaserPreference.productID
        case "totalAlkalinity":
            return treatment.isAcidTreatment
                ? poolConfig.pHDecreaserPreference.productID
                : poolConfig.alkalinityIncreaserPreference.productID
        case "cyanuricAcid":
            return poolConfig.stabilizerPreference.productID
        case "calciumHardness":
            return poolConfig.calciumIncreaserPreference.productID
        default:
            return nil
        }
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

    /// Canonical structured Pool Score for a test using this pool's explicit configuration + history.
    /// The single production entry point that Views/exports consume for score, grade, and drivers.
    func scoreAssessment(for test: PoolTest, in tests: [PoolTest]) -> PoolScoreAssessment {
        chemistryEngine.scoreAssessment(
            for: test,
            previousTest: previousTest(before: test, in: tests),
            recentHistory: recentHistory(before: test, in: tests),
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

    /// Canonical score → grade label. Delegates to the single engine mapping used by the assessment.
    func scoreGrade(_ score: Int) -> String {
        ChemistryEngine.scoreGrade(for: score)
    }

    // MARK: - Dashboard workflow items (Active / Completed)

    /// Splits every test into its evolving-workflow row model. Active rows are ordered by the next
    /// required action (earliest first); completed rows are newest-first and carry the final
    /// evidence-based score/grade (recomputed through the canonical score engine — never a View-side
    /// or theoretical value). A root test appears in exactly one section.
    ///
    /// Active ordering tie-break: (1) actionable/overdue before future, (2) earlier next-action date,
    /// (3) newer original test date.
    func dashboardWorkflows(
        from tests: [PoolTest],
        evaluationDate: Date = Date()
    ) -> (active: [DashboardWorkflowItem], completed: [DashboardWorkflowItem]) {
        var active: [DashboardWorkflowItem] = []
        var completed: [DashboardWorkflowItem] = []

        for test in tests {
            let state = workflowEngine.workflowState(for: test, evaluationDate: evaluationDate)
            switch state {
            case .completed:
                let score = overallScore(
                    for: test,
                    previousTest: previousTest(before: test, in: tests),
                    recentHistory: recentHistory(before: test, in: tests)
                )
                completed.append(DashboardWorkflowItem(
                    rootTestID: test.id,
                    originalTestDate: test.date,
                    state: .completed,
                    nextActionDate: nil,
                    isActionable: false,
                    finalScore: score,
                    finalGrade: scoreGrade(score)
                ))
            case .treatmentNeeded, .awaitingPoolCheck:
                let nextAction = workflowEngine.nextActionDate(for: test, state: state, evaluationDate: evaluationDate)
                active.append(DashboardWorkflowItem(
                    rootTestID: test.id,
                    originalTestDate: test.date,
                    state: state,
                    nextActionDate: nextAction,
                    isActionable: (nextAction ?? evaluationDate) <= evaluationDate,
                    finalScore: nil,
                    finalGrade: nil
                ))
            }
        }

        active.sort { lhs, rhs in
            if lhs.isActionable != rhs.isActionable { return lhs.isActionable && !rhs.isActionable }
            let lDate = lhs.nextActionDate ?? evaluationDate
            let rDate = rhs.nextActionDate ?? evaluationDate
            if lDate != rDate { return lDate < rDate }
            return lhs.originalTestDate > rhs.originalTestDate
        }
        completed.sort { $0.originalTestDate > $1.originalTestDate }

        return (active, completed)
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
            // A focused Check is created only when the result is actually required (swim safety, a staged
            // corrective dose, or surface/equipment protection). Recommended optimizations on an already-safe
            // pool get no Check.
            guard workflowEngine.requiresFocusedCheck(for: treatment, config: poolConfig) else { continue }
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
    /// Outcome of completing a treatment, describing what follow-up (if any) was scheduled so the UI can
    /// present accurate feedback.
    enum TreatmentCompletionOutcome: Equatable {
        case completed                              // nothing scheduled
        case awaitingCheck                          // a focused Check owns the verification reminder
        case nextStepScheduled                      // reminder for the next chemical step
        case waitCompleteScheduled(fireDate: Date)  // "safe to swim" wait-complete reminder scheduled
    }

    @MainActor
    @discardableResult
    func completeTreatment(_ treatment: Treatment, in tests: [PoolTest], modelContext: ModelContext) async -> TreatmentCompletionOutcome {
        // A focused Check is completed ONLY by submitting a measured result (saveFocusedCheck) — never by the
        // generic completion path. This guard makes it impossible to complete a Check via any treatment caller.
        guard !treatment.isFocusedCheckStep else { return .completed }

        cancelCompletionNotifications(for: treatment)
        treatment.isCompleted = true
        treatment.completedAt = Date()
        treatment.isSkipped = false
        treatment.skippedAt = nil

        let outcome = await scheduleCompletionFollowUp(for: treatment)

        try? modelContext.save()
        let anchorTest = treatment.poolTest ?? latestTest(in: tests)
        await replaceNextPoolTestReminder(for: anchorTest, allTests: tests)
        await reconcileWorkflowNotifications(in: mergedTests(tests, including: anchorTest))
        if let anchorTest {
            runSwimabilityV2ComparisonAfterTreatmentStateChange(
                for: anchorTest,
                recentTests: recentHistory(before: anchorTest, in: tests),
                context: "Treatment Completed"
            )
        }
        return outcome
    }

    /// Product substitutions can happen after a reminder was already scheduled. Cancel the old product's
    /// workflow reminders and, if the treatment is already completed, schedule the current product's one
    /// applicable follow-up without changing the historical completion timestamp.
    @MainActor
    @discardableResult
    func refreshTreatmentNotificationsAfterProductChange(
        _ treatment: Treatment,
        in tests: [PoolTest],
        modelContext: ModelContext
    ) async -> TreatmentCompletionOutcome? {
        cancelCompletionNotifications(for: treatment)
        guard treatment.isCompleted, !treatment.isSkipped else {
            try? modelContext.save()
            return nil
        }

        let outcome = await scheduleCompletionFollowUp(for: treatment)
        try? modelContext.save()
        let anchorTest = treatment.poolTest ?? latestTest(in: tests)
        await replaceNextPoolTestReminder(for: anchorTest, allTests: tests)
        await reconcileWorkflowNotifications(in: mergedTests(tests, including: anchorTest))
        return outcome
    }

    @MainActor
    private func scheduleCompletionFollowUp(
        for treatment: Treatment
    ) async -> TreatmentCompletionOutcome {
        await notifications.checkAuthorizationStatus()
        let remindersEnabled = poolConfig.enableTreatmentStepReminders && notifications.isAuthorized

        var outcome: TreatmentCompletionOutcome = .completed

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
            outcome = .awaitingCheck
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
            outcome = .nextStepScheduled
        } else if remindersEnabled, let waitMinutes = TreatmentTimingGuidance.swimWaitMinutes(for: treatment) {
            // No Check and no following chemical, but this treatment imposes a circulation wait before
            // swimming. Only because the user marked it COMPLETE do we schedule a wait-complete "safe to
            // swim" reminder. (Skipping never schedules this — the user has opted out of the treatment.)
            let fireDate = Date().addingTimeInterval(TimeInterval(waitMinutes * 60))
            let identifier = await notifications.scheduleWaitCompleteReminder(
                treatmentID: treatment.id,
                treatmentName: treatment.chemicalName,
                afterMinutes: waitMinutes
            )
            treatment.reminderNotificationIdentifier = identifier
            treatment.stepReminderNotificationIdentifier = identifier
            if identifier != nil { outcome = .waitCompleteScheduled(fireDate: fireDate) }
        }

        return outcome
    }

    // MARK: - Workflow notification reconciliation

    /// Cancels workflow reminders orphaned by plan regeneration or object removal. The live set is every
    /// notification identifier still stored on a surviving treatment/Check across `tests`; any pending
    /// workflow notification outside that set belonged to an object that was replaced (new UUID), deleted,
    /// skipped, or completed, and is cancelled. Routine next-test reminders are never in the workflow
    /// families, so they always survive. Idempotent.
    @MainActor
    func reconcileWorkflowNotifications(in tests: [PoolTest]) async {
        await notifications.reconcileWorkflowNotifications(
            keeping: liveWorkflowNotificationIdentifiers(in: tests)
        )
    }

    /// The identifiers currently owned by surviving treatments/Checks. A stored identifier is only ever
    /// non-nil while its reminder is meant to be pending; completing/skipping/reverting a step clears it,
    /// so this set is exactly the reminders that should still exist.
    private func liveWorkflowNotificationIdentifiers(in tests: [PoolTest]) -> Set<String> {
        var identifiers: Set<String> = []
        for treatment in tests.flatMap(\.treatments) {
            for identifier in [
                treatment.reminderNotificationIdentifier,
                treatment.stepReminderNotificationIdentifier,
                treatment.retestReminderNotificationIdentifier,
                treatment.checkReminderNotificationIdentifier
            ] {
                if let identifier { identifiers.insert(identifier) }
            }
        }
        return identifiers
    }

    @MainActor
    private func cancelCompletionNotifications(for treatment: Treatment) {
        notifications.cancel(identifier: treatment.reminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.stepReminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.retestReminderNotificationIdentifier)
        notifications.cancel(identifier: treatment.checkReminderNotificationIdentifier)
        treatment.reminderNotificationIdentifier = nil
        treatment.stepReminderNotificationIdentifier = nil
        treatment.retestReminderNotificationIdentifier = nil
        treatment.checkReminderNotificationIdentifier = nil

        guard !treatment.isFocusedCheckStep else { return }
        for check in treatment.poolTest?.treatments ?? [] where check.isFocusedCheckStep && check.parentTreatmentID == treatment.id {
            notifications.cancel(identifier: check.checkReminderNotificationIdentifier)
            check.checkReminderNotificationIdentifier = nil
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

    /// `tests` with `extra` appended if it is not already present. Keeps notification reconciliation robust
    /// when the anchor test (e.g. a treatment's own `poolTest`) is not part of the passed-in array.
    private func mergedTests(_ tests: [PoolTest], including extra: PoolTest?) -> [PoolTest] {
        guard let extra, !tests.contains(where: { $0.id == extra.id }) else { return tests }
        return tests + [extra]
    }

    // NOTE: A focused Check is completed ONLY by the user entering its measured result (`saveFocusedCheck`).
    // There is deliberately no automatic completion path. A later full pool test — even one that measures
    // the Check's parameter after the Check's due time — does NOT verify or complete the Check, because
    // logging a full test does not prove the user actually performed that treatment's follow-up measurement.
    // Purple Check cards remain unchecked until the user checks them. (Removed: full-test supersession.)

    /// Result of a manual Skip/Restore request. Focused Checks that are already resolved (completed by a
    /// measured result, or satisfied by a qualifying full test) or inapplicable (parent skipped) reject
    /// the transition and leave persisted state untouched. Regular treatments always report `.applied`.
    enum CheckTransitionResult: Equatable {
        case applied
        case rejectedCompleted
        case rejectedSuperseded
        case rejectedInapplicable
    }

    /// Returns a rejection reason if the focused Check may NOT be manually skipped/restored, or `nil` when
    /// the transition is eligible (this is also `nil` for any non-Check treatment).
    @MainActor
    func focusedCheckTransitionRejection(_ treatment: Treatment) -> CheckTransitionResult? {
        guard treatment.isFocusedCheckStep else { return nil }
        if treatment.isCompleted {
            let ownTestID = treatment.poolTest?.id
            if let resultID = treatment.checkResultTestID, resultID != ownTestID {
                return .rejectedSuperseded
            }
            return .rejectedCompleted
        }
        // Resolved by valid evidence even if the completion flag was not set — treat as superseded.
        if treatment.checkResultTestID != nil { return .rejectedSuperseded }
        // A Check whose parent was skipped is inapplicable; it is only restored by restoring the parent.
        if let parentID = treatment.parentTreatmentID,
           let parent = treatment.poolTest?.treatments.first(where: { $0.id == parentID }),
           parent.isSkipped {
            return .rejectedInapplicable
        }
        return nil
    }

    @MainActor
    func markTreatmentIncomplete(_ treatment: Treatment) {
        // A focused Check is completed only by the user's measured result; the generic "mark incomplete"
        // path must never revert it.
        guard !treatment.isFocusedCheckStep else { return }

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

    /// One-time data repair for the removed full-test supersession behavior. Reopens any focused Check that
    /// an earlier build auto-completed via a *different* full test. Because a legitimately user-completed
    /// Check always records its own originating test in `checkResultTestID`, a Check whose `checkResultTestID`
    /// points at a different test can only be a stale auto-completion — never a real measured result. This is
    /// precise (it never touches a user's manual completion) and idempotent (reopened Checks clear the link,
    /// so a second run matches nothing). Returns the number of Checks reopened.
    @MainActor
    @discardableResult
    func reopenAutoCompletedChecks(in tests: [PoolTest], modelContext: ModelContext) -> Int {
        var reopened = 0
        for test in tests {
            for check in test.treatments where check.isFocusedCheckStep {
                guard check.isCompleted,
                      let resultID = check.checkResultTestID,
                      resultID != test.id
                else { continue }
                check.isCompleted = false
                check.completedAt = nil
                check.checkResultTestID = nil
                notifications.cancel(identifier: check.checkReminderNotificationIdentifier)
                check.checkReminderNotificationIdentifier = nil
                reopened += 1
            }
        }
        if reopened > 0 { try? modelContext.save() }
        return reopened
    }

    @MainActor
    @discardableResult
    func skipTreatment(_ treatment: Treatment) -> CheckTransitionResult {
        // A resolved or inapplicable focused Check must reject Skip and never be un-completed.
        if let rejection = focusedCheckTransitionRejection(treatment) { return rejection }

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
        return .applied
    }

    @MainActor
    @discardableResult
    func restoreTreatment(_ treatment: Treatment) -> CheckTransitionResult {
        // A completed/superseded Check was never validly skipped — reject Restore and leave it historical.
        if let rejection = focusedCheckTransitionRejection(treatment) { return rejection }

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
        return .applied
    }

    // MARK: - Pending Treatments (across all tests)

    func pendingTreatments(from tests: [PoolTest]) -> [Treatment] {
        // Focused Checks are verification steps handled by their own workflow UI (measurement entry), not
        // completable treatment rows — they must never appear in a list with a completing checkbox.
        tests
            .flatMap { $0.treatments }
            .filter { !$0.isCompleted && !$0.isSkipped && !$0.isFocusedCheckStep }
            .sorted { $0.urgency.sortOrder < $1.urgency.sortOrder }
    }

    func completedTreatments(from tests: [PoolTest]) -> [Treatment] {
        tests
            .flatMap { $0.treatments }
            .filter { $0.isCompleted && !$0.isFocusedCheckStep }
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
        // The Check was completed and the plan regenerated with fresh treatment/Check UUIDs; cancel any
        // reminder left behind by the superseded objects so no orphan retest/wait survives.
        await reconcileWorkflowNotifications(in: mergedTests)

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

        // A Check is only ever completed by the user's own focused result, whose `checkResultTestID` points
        // at the Check's own originating test. If that test is deleted the Check is cascade-removed with it,
        // so no surviving Check can reference a deleted result test — there is nothing to repair here.
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
