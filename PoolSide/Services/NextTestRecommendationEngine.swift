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

    let recommendedDate: Date
    let interval: TimeInterval
    let reason: String
    let title: String
    let body: String
    let urgency: Urgency
    let source: Source

    var relativeLabel: String {
        Self.relativeFormatter.localizedString(for: recommendedDate, relativeTo: Date())
    }

    var scheduledReason: String {
        body.isEmpty ? reason : body
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}

struct NextTestRecommendationEngine {
    func recommendation(
        for test: PoolTest,
        treatmentSteps: [Treatment],
        watchlist: [Treatment],
        recentHistory: [PoolTest],
        config: PoolConfiguration
    ) -> NextTestRecommendation {
        let confidence = ChemistryEngine().recommendationConfidenceInput(for: test, recentHistory: recentHistory)
        let pendingSteps = treatmentSteps.filter { !$0.isCompleted && !$0.isSkipped }

        if let chlorine = pendingSteps.first(where: { $0.targetParameter == "freeChlorine" && shouldRetestAfterChlorine($0) }) {
            let minutes = chlorineRetestMinutes(for: chlorine)
            return make(
                from: test.date,
                minutes: minutes,
                reason: "FC needs correction and should be confirmed after circulation.",
                title: "Retest FC and CC",
                body: "Retest FC and CC after adding chlorine so Pool Side can confirm the correction worked.",
                urgency: chlorine.urgency == .immediate ? .urgent : .retest,
                source: .chlorineCorrection
            )
        }

        if let pH = pendingSteps.first(where: { $0.targetParameter == "pH" && $0.effectDelayHours >= 4 }) {
            return make(
                from: test.date,
                minutes: 240,
                reason: pH.urgency == .immediate ? "pH is unsafe and needs a same-day confirmation." : "pH treatment should be checked after circulation.",
                title: "Retest pH",
                body: "Retest pH after circulation before adding more pH product.",
                urgency: pH.urgency == .immediate ? .urgent : .retest,
                source: .pHCorrection
            )
        }

        if pendingSteps.contains(where: { $0.targetParameter == "cyanuricAcid" }) {
            return make(
                from: test.date,
                hours: 72,
                reason: "Stabilizer changes slowly and needs time to register.",
                title: "Retest CYA",
                body: "Retest CYA after the stabilizer has circulated and dissolved.",
                urgency: .watch,
                source: .stabilizer
            )
        }

        if confidence.waterChangeScore >= 2 || watchlist.contains(where: { $0.chemicalName.localizedCaseInsensitiveContains("Dilution") }) {
            return make(
                from: test.date,
                hours: 24,
                reason: "Recent rain or water addition can dilute readings.",
                title: "Next pool test",
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
                title: "Next pool test",
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
                title: "Next pool test",
                body: "Pool Side recommends your next routine test based on current stability and recent demand.",
                urgency: .routine,
                source: .stablePool
            )
        }

        return make(
            from: test.date,
            hours: 24,
            reason: "A treatment plan is active, so Pool Side should confirm the pool response soon.",
            title: "Next pool test",
            body: "Test again in about 24 hours to confirm the treatment plan worked.",
            urgency: .retest,
            source: .treatmentPlan
        )
    }

    func treatmentRetestRecommendation(for treatment: Treatment, completedAt: Date = Date()) -> NextTestRecommendation? {
        guard !treatment.isWatchlistItem else { return nil }

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
                hours: 72,
                reason: "Stabilizer needs time to dissolve and register.",
                title: "Retest CYA",
                body: "Retest CYA after 48-72 hours before adding more stabilizer.",
                urgency: .watch,
                source: .stabilizer
            )
        }

        return nil
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
        treatment.urgency == .immediate || treatment.urgency == .recommended
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
            source: source
        )
    }
}
