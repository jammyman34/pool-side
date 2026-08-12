import Foundation

struct NextTestRecommendation {
    enum Urgency: String {
        case routine
        case watch
        case retest
        case urgent
    }

    enum Source: String {
        case stablePool
        case treatmentPlan
        case chlorineCorrection
        case pHCorrection
        case stabilizer
        case highDemand
        case possibleDilution
    }

    let recommendedDate: Date?
    let interval: TimeInterval
    let reason: String
    let title: String
    let body: String
    let urgency: Urgency
    let source: Source
    let isPendingTreatmentAction: Bool

    var relativeLabel: String {
        guard let recommendedDate else { return "After treatment is completed" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: recommendedDate, relativeTo: Date())
    }

    var scheduledReason: String {
        body.isEmpty ? reason : body
    }
}

struct NextTestRecommendationEngine {
    func recommendation(
        for test: PoolTest,
        treatmentSteps: [Treatment],
        watchlist: [Treatment],
        recentHistory: [PoolTest],
        config: PoolConfiguration,
        outstandingCheckDueDates: [Date] = []
    ) -> NextTestRecommendation {
        let base = baseRecommendation(
            for: test,
            treatmentSteps: treatmentSteps,
            watchlist: watchlist,
            recentHistory: recentHistory,
            config: config
        )
        return coordinatingWithOutstandingChecks(base, outstandingCheckDueDates: outstandingCheckDueDates)
    }

    /// While a treatment workflow still has an outstanding focused Check, that Check is the immediate
    /// required measurement. The routine full pool test must not be scheduled as a competing event on or
    /// before the Check's due time — otherwise the user is asked for a full panel that duplicates the
    /// verification the Check already provides. Rather than an arbitrary fixed postponement, the routine
    /// test is re-anchored to the Check's own due date and advanced by the engine's normally-computed
    /// cadence (the interval it already chose). If the routine test was independently due later than the
    /// Check anyway, it is left untouched.
    private func coordinatingWithOutstandingChecks(
        _ base: NextTestRecommendation,
        outstandingCheckDueDates: [Date]
    ) -> NextTestRecommendation {
        guard
            let latestCheckDue = outstandingCheckDueDates.max(),
            let routineDate = base.recommendedDate,
            routineDate <= latestCheckDue
        else { return base }

        return NextTestRecommendation(
            recommendedDate: latestCheckDue.addingTimeInterval(base.interval),
            interval: base.interval,
            reason: "A focused re-test is still pending; routine full testing is deferred until after it is recorded.",
            title: base.title,
            body: "Record the pending focused re-test first. Your next full pool test is scheduled for after that result.",
            urgency: base.urgency,
            source: base.source,
            isPendingTreatmentAction: base.isPendingTreatmentAction
        )
    }

    private func baseRecommendation(
        for test: PoolTest,
        treatmentSteps: [Treatment],
        watchlist: [Treatment],
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> NextTestRecommendation {
        let confidence = ChemistryEngine().recommendationConfidenceInput(for: test, recentHistory: recentHistory)
        let pendingSteps = treatmentSteps.filter { !$0.isCompleted && !$0.isSkipped && !$0.isWatchlistItem && !$0.isFocusedCheckStep }

        if hasCompletedOptionalChlorineTopOff(treatmentSteps) {
            return treatmentPlanRoutineFollowUp(from: test.date)
        }

        if confidence.waterChangeScore >= 3 {
            let backwashed = test.resolvedPoolConditions.backwashedFilter == .yes
            let reason = backwashed
                ? "Recent backwashing or water replacement can dilute readings."
                : "Recent rain or water addition can dilute readings."
            return make(
                from: test.date,
                hours: 24,
                reason: reason,
                title: "Next full pool test",
                body: "Retest after circulation or tomorrow to confirm dilution effects before making large corrections.",
                urgency: .watch,
                source: .possibleDilution
            )
        }

        if confidence.chlorineDemandScore >= 3 || watchlist.contains(where: { $0.chemicalName.localizedCaseInsensitiveContains("Chlorine Demand") }) {
            return make(
                from: test.date,
                hours: 24,
                reason: "Recent pool conditions may increase chlorine demand.",
                title: "Next full pool test",
                body: "Test again tomorrow to confirm FC is holding after the recent demand.",
                urgency: .watch,
                source: .highDemand
            )
        }

        if pendingSteps.isEmpty {
            let days = stableCadenceDays(for: test, recentHistory: recentHistory, confidence: confidence)
            return make(
                from: test.date,
                hours: Double(days * 24),
                reason: "Pool is stable and does not need immediate treatment.",
                title: "Next full pool test",
                body: "Run your normal full pool test to check overall water balance.",
                urgency: .routine,
                source: .stablePool
            )
        }

        return treatmentPlanRoutineFollowUp(from: test.date)
    }

    func treatmentRetestRecommendation(for treatment: Treatment, completedAt: Date = Date()) -> NextTestRecommendation? {
        guard !treatment.isWatchlistItem, !treatment.isFocusedCheckStep else { return nil }

        if treatment.targetParameter == "freeChlorine", shouldRetestAfterChlorine(treatment) {
            let minutes = chlorineRetestMinutes(for: treatment)
            return make(
                from: completedAt,
                minutes: minutes,
                reason: "FC correction needs confirmation after circulation.",
                title: "Retest FC and CC",
                body: "Retest FC and CC after the chlorine has circulated.",
                urgency: treatment.urgency == .immediate ? .urgent : .retest,
                source: .chlorineCorrection
            )
        }

        if treatment.targetParameter == "pH", treatment.effectDelayHours >= 4 {
            return make(
                from: completedAt,
                minutes: 240,
                reason: "pH treatment needs confirmation after circulation.",
                title: "Retest pH",
                body: "Retest pH before adding more pH product.",
                urgency: treatment.urgency == .immediate ? .urgent : .retest,
                source: .pHCorrection
            )
        }

        if treatment.targetParameter == "cyanuricAcid" {
            return make(
                from: completedAt,
                hours: Double(TreatmentApplicationPolicy.granularCYACanonicalRetestHours),
                reason: "Stabilizer needs time to dissolve and register.",
                title: "Retest CYA",
                body: "Retest CYA after 24-48 hours before adding more stabilizer.",
                urgency: .watch,
                source: .stabilizer
            )
        }

        if treatment.targetParameter == "totalAlkalinity", !treatment.isAcidTreatment, treatment.effectDelayHours > 0 {
            return make(
                from: completedAt,
                hours: Double(treatment.effectDelayHours),
                reason: "Alkalinity treatment needs circulation before the result is meaningful.",
                title: "Retest TA",
                body: "Retest TA after circulation before making another alkalinity adjustment.",
                urgency: .watch,
                source: .treatmentPlan
            )
        }

        if treatment.targetParameter == "calciumHardness", treatment.effectDelayHours > 0 {
            return make(
                from: completedAt,
                hours: Double(treatment.effectDelayHours),
                reason: "Calcium hardness needs time to circulate before retesting.",
                title: "Retest CH",
                body: "Retest calcium hardness after circulation before adding more calcium increaser.",
                urgency: .watch,
                source: .treatmentPlan
            )
        }

        return nil
    }

    private func treatmentPlanRoutineFollowUp(from testDate: Date) -> NextTestRecommendation {
        make(
            from: testDate,
            hours: 24,
            reason: "A treatment plan is active; routine testing should confirm the overall response tomorrow.",
            title: "Next full pool test",
            body: "Run your normal full pool test to check overall water balance.",
            urgency: .watch,
            source: .treatmentPlan
        )
    }

    private func hasCompletedOptionalChlorineTopOff(_ treatmentSteps: [Treatment]) -> Bool {
        treatmentSteps.contains { treatment in
            treatment.isCompleted
                && !treatment.isSkipped
                && !treatment.isWatchlistItem
                && !treatment.isFocusedCheckStep
                && treatment.targetParameter == "freeChlorine"
                && isMaintenanceChlorineTopOff(treatment)
        }
    }

    /// A maintenance chlorine top-off is a completed FC treatment whose source test FC was at/above the
    /// readiness minimum (ChemistryPolicy recommendedLow, non-swim-blocking). Detected via
    /// ChemistryPolicy rather than the urgency label, since maintenance top-offs are now Recommended
    /// (not Optional) yet must still keep the treatment-plan routine cadence rather than falling to the
    /// stable-pool cadence.
    private func isMaintenanceChlorineTopOff(_ treatment: Treatment) -> Bool {
        guard let test = treatment.poolTest else { return false }
        let classification = ChemistryPolicy.classify(
            .freeChlorine,
            value: test.freeChlorine,
            context: ChemistryPolicyContext(cyanuricAcid: test.cyanuricAcid)
        )
        return classification.actionState == .recommendedLow && !classification.blocksSwimming
    }

    private func stableCadenceDays(
        for test: PoolTest,
        recentHistory: [PoolTest],
        confidence: RecommendationConfidenceInput
    ) -> Int {
        if confidence.chlorineDemandScore >= 2 { return 1 }
        if recentHistory.prefix(3).contains(where: { $0.freeChlorine < 2.0 || $0.combinedChlorine > 0.5 }) { return 2 }
        return 3
    }

    private func shouldRetestAfterChlorine(_ treatment: Treatment) -> Bool {
        treatment.urgency.isActionable
    }

    private func requiresSameDayChlorineVerification(_ treatment: Treatment, test: PoolTest) -> Bool {
        guard treatment.targetParameter == "freeChlorine" else { return false }
        // Act Now and Needs Attention FC both sit below the swim-readiness minimum → verify same day.
        if treatment.urgency == .immediate || treatment.urgency == .needsAttention { return true }

        let indicators = Set(test.visualIndicators)
        let hasProblemWater = indicators.contains(VisualIndicator.cloudyWater.rawValue)
            || indicators.contains(VisualIndicator.greenWater.rawValue)
            || indicators.contains(VisualIndicator.algaeSpots.rawValue)
            || indicators.contains(VisualIndicator.strongChlorineSmell.rawValue)
        if hasProblemWater { return true }

        if treatment.urgency == .recommended && test.combinedChlorine > 0.5 { return true }
        return false
    }

    private func chlorineRetestMinutes(for treatment: Treatment) -> Int {
        if treatment.chemicalName.localizedCaseInsensitiveContains("tablet") {
            return 24 * 60
        }
        if treatment.chemicalName.localizedCaseInsensitiveContains("granule")
            || treatment.chemicalName.localizedCaseInsensitiveContains("dichlor") {
            return 240
        }
        return 60
    }

    private func make(
        from anchor: Date,
        minutes: Int,
        reason: String,
        title: String,
        body: String,
        urgency: NextTestRecommendation.Urgency,
        source: NextTestRecommendation.Source
    ) -> NextTestRecommendation {
        make(
            from: anchor,
            interval: TimeInterval(minutes * 60),
            reason: reason,
            title: title,
            body: body,
            urgency: urgency,
            source: source
        )
    }

    private func make(
        from anchor: Date,
        hours: Double,
        reason: String,
        title: String,
        body: String,
        urgency: NextTestRecommendation.Urgency,
        source: NextTestRecommendation.Source
    ) -> NextTestRecommendation {
        make(
            from: anchor,
            interval: hours * 60 * 60,
            reason: reason,
            title: title,
            body: body,
            urgency: urgency,
            source: source
        )
    }

    private func make(
        from anchor: Date,
        interval: TimeInterval,
        reason: String,
        title: String,
        body: String,
        urgency: NextTestRecommendation.Urgency,
        source: NextTestRecommendation.Source
    ) -> NextTestRecommendation {
        NextTestRecommendation(
            recommendedDate: anchor.addingTimeInterval(interval),
            interval: interval,
            reason: reason,
            title: title,
            body: body,
            urgency: urgency,
            source: source,
            isPendingTreatmentAction: false
        )
    }

    private func pendingTreatmentActionRecommendation() -> NextTestRecommendation {
        NextTestRecommendation(
            recommendedDate: nil,
            interval: 0,
            reason: "Complete or skip the recommended treatment to schedule your next test.",
            title: "After treatment is completed",
            body: "Complete or skip the recommended treatment to schedule your next test.",
            urgency: .watch,
            source: .treatmentPlan,
            isPendingTreatmentAction: true
        )
    }
}
