import Foundation

struct NextTestRecommendation {
    enum Urgency: String {
        case routine
        case watch
        case retest
        case urgent
    }

    enum Source: String {
        // Routine testing cadence anchored to the most recent Full Test Panel.
        case routineFCAndPH
        case routineFullPanel
        // Treatment-specific retest sources (owned by `treatmentRetestRecommendation`).
        case treatmentPlan
        case chlorineCorrection
        case pHCorrection
        case stabilizer
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

/// The canonical routine testing cadence, anchored to the most recent Full Test Panel:
/// a quick FC & pH check at +3 days and the next Full Test Panel at +7 days. This is the single
/// source of truth for the "Next Pool Tests" the user sees; Views must not compute these dates.
/// Treatment-specific Focused Checks and treatment retests are separate and not represented here.
struct NextTestSchedule {
    let fcAndPH: NextTestRecommendation
    let fullPanel: NextTestRecommendation
    /// The single test the user should see next: the FC & pH check while it is still upcoming,
    /// otherwise the Full Test Panel. Completing FC & pH never moves the Full Test Panel date.
    let firstUpcoming: NextTestRecommendation

    var routineTests: [NextTestRecommendation] { [fcAndPH, fullPanel] }
}

struct NextTestRecommendationEngine {
    // MARK: - Routine cadence SSOT

    static let fcAndPHRoutineDays = 3
    static let fullPanelRoutineDays = 7

    /// Builds the routine FC & pH (+3d) and Full Test Panel (+7d) schedule from the most recent Full
    /// Test Panel date. Conditions attached to a test describe events BEFORE that sample, so the sample
    /// already measured their effect — the routine cadence therefore never adds a same-/next-day
    /// "confirmation" retest. Only a new Full Test Panel re-anchors this schedule.
    func routineSchedule(mostRecentFullTestDate anchor: Date, now: Date = Date()) -> NextTestSchedule {
        let fcAndPH = makeRoutineRecommendation(
            from: anchor,
            days: Self.fcAndPHRoutineDays,
            title: "Test FC & pH",
            body: "A quick check between full tests to make sure things are on track.",
            source: .routineFCAndPH
        )
        let fullPanel = makeRoutineRecommendation(
            from: anchor,
            days: Self.fullPanelRoutineDays,
            title: "Full Test Panel",
            body: "Run your complete test panel to reassess overall water balance.",
            source: .routineFullPanel
        )
        let firstUpcoming: NextTestRecommendation = {
            if let due = fcAndPH.recommendedDate, due > now { return fcAndPH }
            return fullPanel
        }()
        return NextTestSchedule(fcAndPH: fcAndPH, fullPanel: fullPanel, firstUpcoming: firstUpcoming)
    }

    private func makeRoutineRecommendation(
        from anchor: Date,
        days: Int,
        title: String,
        body: String,
        source: NextTestRecommendation.Source
    ) -> NextTestRecommendation {
        make(
            from: anchor,
            hours: Double(days * 24),
            reason: body,
            title: title,
            body: body,
            urgency: .routine,
            source: source
        )
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

    private func shouldRetestAfterChlorine(_ treatment: Treatment) -> Bool {
        treatment.urgency.isActionable
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
}
