import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    private var chronologicalTests: [PoolTest] {
        tests.sorted { $0.date < $1.date }
    }

    private var latestTest: PoolTest? {
        tests.first
    }

    private var last30DaysTests: [PoolTest] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return tests.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        heroTitle

                        if tests.isEmpty {
                            emptyState
                        } else {
                            poolPersonalityCard
                            whatsChangingCard
                            testingRhythmCard
                            poolScoreCard
                            chemicalTrendsCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .environment(\.colorScheme, .light)
    }

    private var heroTitle: some View {
        Text("Insights")
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(PoolColor.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pool Personality

    private var poolPersonalityCard: some View {
        insightCard(title: "Pool Personality", subtitle: historyConfidenceText) {
            VStack(alignment: .leading, spacing: 12) {
                let cards = poolPersonalityInsights()
                ForEach(cards) { card in
                    personalityRow(card)
                }

                if !recentConditionsLogged {
                    helperNote("Logging Pool Conditions helps Pool Side explain why chlorine drops faster after swimming, rain, debris, or covered periods.")
                }
            }
        }
    }

    private func personalityRow(_ insight: PersonalityInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(insight.color)
                .frame(width: 28, height: 28)
                .background(insight.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolColor.primaryText)
                Text(insight.message)
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - What's Changing

    private var whatsChangingCard: some View {
        insightCard(title: "What’s Changing", subtitle: "Recent meaningful patterns") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(whatsChangingMessages(), id: \.self) { message in
                    bulletRow(message)
                }
            }
        }
    }

    // MARK: - Testing Rhythm

    private var testingRhythmCard: some View {
        insightCard(title: "Testing Rhythm", subtitle: "How often you are checking the pool") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    cadenceStat(title: "Avg Gap", value: averageTestGapText())
                    cadenceStat(title: "Last Tested", value: lastTestedText())
                    cadenceStat(title: "30-Day Tests", value: "\(last30DaysTests.count)")
                }

                Text(testingRhythmMessage())
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pool Score Trend

    private var poolScoreCard: some View {
        insightCard(title: "Pool Score Trend", subtitle: "How pool risk has moved over time") {
            let data = poolScoreData()
            if data.count < 2 {
                Text("Need at least 2 tests to show a score trend.")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Chart(data) { item in
                            LineMark(
                                x: .value("Date", item.date),
                                y: .value("Score", item.score)
                            )
                            .foregroundStyle(PoolColor.poolTeal)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))

                            AreaMark(
                                x: .value("Date", item.date),
                                yStart: .value("Min", 0),
                                yEnd: .value("Score", item.score)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [PoolColor.poolTeal.opacity(0.2), PoolColor.poolTeal.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            PointMark(
                                x: .value("Date", item.date),
                                y: .value("Score", item.score)
                            )
                            .foregroundStyle(PoolColor.poolTeal)
                            .symbolSize(28)
                        }
                        .chartYScale(domain: 0...100)
                        .chartYAxis {
                            AxisMarks(values: [0, 25, 50, 75, 100]) {
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(PoolColor.divider)
                                AxisValueLabel()
                                    .foregroundStyle(PoolColor.secondaryText)
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: data.map(\.date)) {
                                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(PoolColor.divider)
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                    .foregroundStyle(PoolColor.secondaryText)
                            }
                        }
                        .frame(width: scoreChartWidth(for: data.count), height: 160)
                    }
                    .frame(height: 170)

                    Text(scoreTrendMessage(data))
                        .font(.subheadline)
                        .foregroundStyle(PoolColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Chemical Trends

    private var chemicalTrendsCard: some View {
        insightCard(title: "Chemical Trends", subtitle: "Focused readings that affect recommendations") {
            VStack(alignment: .leading, spacing: 0) {
                let trends = chemicalTrendRows()
                ForEach(Array(trends.enumerated()), id: \.element.id) { index, trend in
                    chemicalTrendRow(trend)
                    if index < trends.count - 1 {
                        Divider()
                            .overlay(PoolColor.divider.opacity(0.7))
                            .padding(.leading, 38)
                    }
                }
            }
        }
    }

    private func chemicalTrendRow(_ trend: ChemicalTrend) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trend.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(trend.color)
                .frame(width: 26, height: 26)
                .background(trend.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trend.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Text(trend.value)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(PoolColor.primaryText)
                }

                Text("\(trend.direction) — \(trend.interpretation)")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Card Shell

    private func insightCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
            }
            content()
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(PoolColor.poolTeal)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func helperNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(PoolColor.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PoolColor.poolTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 52))
                .foregroundStyle(PoolColor.poolTeal.opacity(0.5))
            Text("No data yet")
                .font(.headline)
                .foregroundStyle(PoolColor.primaryText)
            Text("Log a few tests and Pool Side will learn your testing rhythm, chlorine demand, and chemistry patterns.")
                .font(.subheadline)
                .foregroundStyle(PoolColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Data Models

    struct PersonalityInsight: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let icon: String
        let color: Color
    }

    struct ScorePoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Int
    }

    struct ChemicalTrend: Identifiable {
        let id = UUID()
        let name: String
        let value: String
        let direction: String
        let interpretation: String
        let icon: String
        let color: Color
    }

    // MARK: - Insight Helpers

    private var historyConfidenceText: String {
        switch tests.count {
        case 0...2:
            return "Learning from early test history"
        case 3...5:
            return "Tentative patterns from recent tests"
        default:
            return "Patterns based on \(tests.count) logged tests"
        }
    }

    private var recentConditionsLogged: Bool {
        tests.prefix(5).contains { $0.poolConditions != nil }
    }

    private func poolPersonalityInsights() -> [PersonalityInsight] {
        if tests.count < 3 {
            return [
                PersonalityInsight(
                    title: "Not enough history yet",
                    message: "Log at least 3 tests to start seeing how your pool behaves over time.",
                    icon: "clock",
                    color: PoolColor.secondaryText
                )
            ]
        }

        return [
            chlorineDemandInsight(),
            pHStabilityInsight(),
            cyaManagementInsight(),
            maintenanceStyleInsight()
        ]
    }

    private func chlorineDemandInsight() -> PersonalityInsight {
        let recent = Array(tests.prefix(6))
        let avgDemand = averageDemandScore(in: recent)
        let lowFCCount = recent.filter { isFreeChlorineLow($0) }.count
        let completedChlorine = completedChlorineTreatmentCount(in: tests)

        if avgDemand >= 5 || lowFCCount >= 3 || completedChlorine >= 3 {
            return PersonalityInsight(
                title: "High Chlorine Demand",
                message: "Recent tests show repeated low FC, higher condition demand, or frequent chlorine corrections.",
                icon: "flame.fill",
                color: PoolColor.statusOffRange
            )
        }

        if avgDemand >= 3 || lowFCCount >= 2 {
            return PersonalityInsight(
                title: "Moderate Chlorine Demand",
                message: "Your pool periodically needs extra sanitizer attention, especially around activity or weather changes.",
                icon: "drop.triangle.fill",
                color: PoolColor.statusSlight
            )
        }

        return PersonalityInsight(
            title: "Low Chlorine Demand",
            message: "Recent logs suggest sanitizer demand is predictable when FC is kept near the CYA-adjusted target.",
            icon: "checkmark.seal.fill",
            color: PoolColor.statusIdeal
        )
    }

    private func pHStabilityInsight() -> PersonalityInsight {
        let recent = Array(tests.prefix(5)).reversed()
        let values = recent.map(\.pH)
        let rising = values.count >= 3 && values.suffix(3).isStrictlyRising()
        let latestTA = latestTest?.totalAlkalinity ?? 0

        if rising {
            return PersonalityInsight(
                title: "Rising pH Trend",
                message: "pH has been moving upward across recent tests. Elevated TA can make that drift more likely.",
                icon: "arrow.up.circle.fill",
                color: PoolColor.statusSlight
            )
        }

        if let latest = latestTest, latest.pH > 7.8 {
            return PersonalityInsight(
                title: "pH Needs Watching",
                message: "The latest pH is above the normal operating range and may need correction if it persists.",
                icon: "exclamationmark.triangle.fill",
                color: PoolColor.statusOffRange
            )
        }

        let taContext = latestTA > 140 ? " TA is elevated, but pH is not rising sharply." : ""
        return PersonalityInsight(
            title: "Stable pH",
            message: "Recent pH readings look steady.\(taContext)",
            icon: "water.waves",
            color: PoolColor.statusIdeal
        )
    }

    private func cyaManagementInsight() -> PersonalityInsight {
        guard let latest = latestTest else {
            return PersonalityInsight(title: "Not enough history yet", message: "Log more tests to evaluate stabilizer behavior.", icon: "chart.line.uptrend.xyaxis", color: PoolColor.secondaryText)
        }

        let recent = Array(tests.prefix(5)).reversed().map(\.cyanuricAcid)
        let rising = recent.count >= 3 && recent.suffix(3).isStrictlyRising()
        let waterChange = latest.resolvedPoolConditions.waterChangeContribution

        if waterChange >= 2 {
            if latest.resolvedPoolConditions.backwashedFilter == .yes {
                return PersonalityInsight(
                    title: "CYA Dilution Watch",
                    message: "Recent backwashing may affect stabilizer or hardness readings. Retest before making large corrections unless values are unsafe.",
                    icon: "arrow.down.forward.circle.fill",
                    color: PoolColor.oceanBlue
                )
            }
            return PersonalityInsight(
                title: "CYA Dilution Watch",
                message: "Recent water addition or rain may affect stabilizer readings. Retest before making large corrections unless values are unsafe.",
                icon: "arrow.down.forward.circle.fill",
                color: PoolColor.oceanBlue
            )
        }

        if rising {
            return PersonalityInsight(
                title: "CYA Rising",
                message: "Stabilizer has been trending upward. Avoid stabilized chlorine when possible.",
                icon: "arrow.up.circle.fill",
                color: PoolColor.statusSlight
            )
        }

        if latest.cyanuricAcid > 50 {
            return PersonalityInsight(
                title: "CYA Elevated but Managed",
                message: "CYA is elevated, so FC targets remain higher. This is a watch item unless FC is not being maintained.",
                icon: "shield.lefthalf.filled",
                color: PoolColor.statusSlight
            )
        }

        return PersonalityInsight(
            title: "CYA Stable",
            message: "Stabilizer is not currently driving major score changes.",
            icon: "checkmark.circle.fill",
            color: PoolColor.statusIdeal
        )
    }

    private func maintenanceStyleInsight() -> PersonalityInsight {
        let scores = poolScoreData().suffix(6).map(\.score)
        let volatility = (scores.max() ?? 0) - (scores.min() ?? 0)
        let recentLowFC = tests.prefix(6).filter { isFreeChlorineLow($0) }.count
        let visualProblems = tests.prefix(6).contains { test in
            test.visualIndicators.contains(VisualIndicator.cloudyWater.rawValue)
                || test.visualIndicators.contains(VisualIndicator.greenWater.rawValue)
                || test.visualIndicators.contains(VisualIndicator.algaeSpots.rawValue)
        }

        if visualProblems {
            return PersonalityInsight(
                title: "Reactive Recovery",
                message: "Recent visual indicators suggest the pool has needed recovery attention, not just routine maintenance.",
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                color: PoolColor.statusOffRange
            )
        }

        if recentLowFC >= 3 || volatility >= 25 {
            return PersonalityInsight(
                title: "Frequent Demand Spikes",
                message: "Recent scores or FC readings are moving enough that closer testing may help catch demand spikes earlier.",
                icon: "waveform.path.ecg",
                color: PoolColor.statusSlight
            )
        }

        return PersonalityInsight(
            title: "Routine Maintenance",
            message: "Recent history looks more like normal maintenance than problem recovery.",
            icon: "calendar.badge.checkmark",
            color: PoolColor.statusIdeal
        )
    }

    private func whatsChangingMessages() -> [String] {
        guard tests.count >= 3 else {
            return ["Log a few more tests to start seeing pool behavior patterns."]
        }

        var messages: [String] = []
        let recent = Array(tests.prefix(3))
        let latest = recent[0]
        let conditions = latest.resolvedPoolConditions

        if recent.map(\.pH).reversed().isStrictlyRising() {
            messages.append("pH is rising across the last 3 tests.")
        } else if recent.allSatisfy({ 7.2...7.8 ~= $0.pH }) {
            messages.append("pH has stayed stable across the last 3 tests.")
        }

        if latest.totalAlkalinity > 140 && 7.2...7.8 ~= latest.pH {
            messages.append("TA remains elevated, but pH is not currently unsafe.")
        }

        if latest.cyanuricAcid > 50 {
            messages.append("CYA is elevated, so FC targets remain higher.")
        }

        if conditions.chlorineDemandContribution >= 3 {
            messages.append("Recent pool conditions may be increasing chlorine demand.")
        } else if !recentConditionsLogged {
            messages.append("Pool conditions have not been logged recently, so trends are based mostly on chemistry.")
        }

        if conditions.organicDebrisLoad.chlorineDemandScore > 0 && conditions.organicLoadReductionScore > 0 {
            messages.append("Debris was logged, but skimming, cleaning, or brushing reduced the expected chlorine demand.")
        } else if recentCleaningAndBrushingCount() >= 3 {
            messages.append("Frequent brushing or cleaning may be helping keep demand lower.")
        }

        if conditions.waterChangeContribution >= 2 {
            if conditions.backwashedFilter == .yes {
                messages.append("Recent backwashing may explain lower stabilizer, hardness, alkalinity, salt, or chlorine.")
            } else {
                messages.append("Recent water addition or rain may explain lower CYA, hardness, alkalinity, salt, or chlorine.")
            }
        }

        if let previous = tests.dropFirst().first, latest.freeChlorine < previous.freeChlorine - 1.0 {
            messages.append("FC dropped faster than the previous reading.")
        }

        return Array(messages.prefix(5)).isEmpty
            ? ["No major changes stand out yet. Pool Side will surface stronger patterns as more tests are logged."]
            : Array(messages.prefix(5))
    }

    private func testingRhythmMessage() -> String {
        let avgGap = averageTestGap()
        let latestDemand = latestTest?.resolvedPoolConditions.chlorineDemandContribution ?? 0
        let recentLowFC = tests.prefix(3).contains { isFreeChlorineLow($0) }

        if latestDemand >= 3 || recentLowFC {
            return "Given recent chlorine demand or low FC, test again tomorrow after circulation."
        }

        if let avgGap, avgGap <= 3 {
            return "Your current rhythm is reasonable for a stable pool. Testing every 2–3 days should catch most changes."
        }

        if tests.count < 3 {
            return "Log a few more tests to establish your normal testing rhythm."
        }

        return "Your average gap is longer than a typical maintenance rhythm. Testing every 2–3 days gives better trend signals."
    }

    private func scoreTrendMessage(_ data: [ScorePoint]) -> String {
        guard let latest = data.last, let previous = data.dropLast().last, let latestTest else {
            return "Pool Side needs more history before explaining score movement."
        }

        let delta = latest.score - previous.score
        if delta <= -8 {
            if isFreeChlorineLow(latestTest) {
                return "Score dropped mostly because FC fell below the CYA-adjusted target."
            }
            if latestTest.pH < 7.2 || latestTest.pH > 7.8 {
                return "Score dropped mostly because pH moved outside the safe operating range."
            }
            return "Score dropped because one or more readings moved further from the normal operating range."
        }

        if delta >= 8 {
            return "Score improved as recent chemistry moved closer to the target ranges."
        }

        if latestTest.totalAlkalinity > 140 || latestTest.cyanuricAcid > 50 {
            return "Score is mostly steady. TA and CYA may still be watchlist items, but they are not driving major score changes by themselves."
        }

        return "Score is mostly steady across recent tests."
    }

    private func chemicalTrendRows() -> [ChemicalTrend] {
        guard let latest = latestTest else { return [] }

        var rows: [ChemicalTrend] = [
            trend(
                name: "FC",
                value: formatPPM(latest.freeChlorine),
                values: recentValues(\.freeChlorine),
                status: ChemistryEngine().freeChlorineStatus(latest.freeChlorine, cyanuricAcid: latest.cyanuricAcid),
                icon: "drop.fill",
                interpretation: freeChlorineInterpretation(latest)
            ),
            trend(
                name: "pH",
                value: formatOneDecimal(latest.pH),
                values: recentValues(\.pH),
                status: ChemistryEngine().pHStatus(latest.pH),
                icon: "testtube.2",
                interpretation: pHInterpretation(latest)
            ),
            trend(
                name: "TA",
                value: formatPPM(latest.totalAlkalinity),
                values: recentValues(\.totalAlkalinity),
                status: ChemistryEngine().totalAlkalinityStatus(latest.totalAlkalinity),
                icon: "rectangle.compress.vertical",
                interpretation: alkalinityInterpretation(latest)
            ),
            trend(
                name: "CYA",
                value: formatPPM(latest.cyanuricAcid),
                values: recentValues(\.cyanuricAcid),
                status: ChemistryEngine().cyanuricAcidStatus(latest.cyanuricAcid),
                icon: "sun.max.fill",
                interpretation: cyaInterpretation(latest)
            ),
            trend(
                name: "CH",
                value: formatPPM(latest.calciumHardness),
                values: recentValues(\.calciumHardness),
                status: ChemistryEngine().calciumHardnessStatus(latest.calciumHardness, surface: viewModel.poolConfig.surfaceType),
                icon: "circle.hexagongrid.fill",
                interpretation: hardnessInterpretation(latest)
            )
        ]

        if viewModel.poolConfig.isSaltwater || latest.saltLevel != nil {
            rows.append(
                trend(
                    name: "Salt",
                    value: latest.saltLevel.map(formatPPM) ?? "Not logged",
                    values: recentOptionalValues(\.saltLevel),
                    status: latest.saltLevel.map { ChemistryEngine().saltStatus($0) } ?? .testing,
                    icon: "sparkles",
                    interpretation: latest.saltLevel == nil ? "Log salt to track saltwater generator readiness." : "Track against your generator’s preferred range."
                )
            )
        }

        return rows
    }

    private func trend(
        name: String,
        value: String,
        values: [Double],
        status: ChemicalStatus,
        icon: String,
        interpretation: String
    ) -> ChemicalTrend {
        ChemicalTrend(
            name: name,
            value: value,
            direction: directionText(values),
            interpretation: interpretation,
            icon: icon,
            color: status.color
        )
    }

    // MARK: - Cadence Helpers

    private func cadenceStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func lastTestedText() -> String {
        guard let latest = tests.first?.date else { return "No tests" }

        let cal = Calendar.current
        if cal.isDateInToday(latest) {
            return "Today"
        }
        if cal.isDateInYesterday(latest) {
            return "Yesterday"
        }

        let days = cal.dateComponents([.day], from: cal.startOfDay(for: latest), to: cal.startOfDay(for: Date())).day ?? 0
        return "\(max(days, 0))d ago"
    }

    private func averageTestGapText() -> String {
        guard let average = averageTestGap() else { return "Need 2" }
        if average >= 10 {
            return "\(Int(average.rounded()))d"
        }
        return String(format: "%.1fd", average)
    }

    private func averageTestGap() -> Double? {
        let cal = Calendar.current
        let uniqueDays = Array(Set(tests.map { cal.startOfDay(for: $0.date) })).sorted()
        guard uniqueDays.count >= 2 else { return nil }

        let gaps = zip(uniqueDays.dropFirst(), uniqueDays).compactMap { current, previous in
            cal.dateComponents([.day], from: previous, to: current).day
        }
        guard !gaps.isEmpty else { return nil }

        return Double(gaps.reduce(0, +)) / Double(gaps.count)
    }

    // MARK: - Score Helpers

    private func poolScoreData() -> [ScorePoint] {
        chronologicalTests.enumerated().map { index, test in
            let previousTest = index > 0 ? chronologicalTests[index - 1] : nil
            let recentHistory = Array(chronologicalTests[..<index].reversed().prefix(10))
            return ScorePoint(
                date: test.date,
                score: viewModel.overallScore(
                    for: test,
                    previousTest: previousTest,
                    recentHistory: recentHistory
                )
            )
        }
    }

    private func scoreChartWidth(for pointCount: Int) -> CGFloat {
        max(320, CGFloat(pointCount) * 64)
    }

    // MARK: - Chemistry Helpers

    private func recentValues(_ keyPath: KeyPath<PoolTest, Double>, limit: Int = 5) -> [Double] {
        Array(tests.prefix(limit).reversed()).map { $0[keyPath: keyPath] }
    }

    private func recentOptionalValues(_ keyPath: KeyPath<PoolTest, Double?>, limit: Int = 5) -> [Double] {
        Array(tests.prefix(limit).reversed()).compactMap { $0[keyPath: keyPath] }
    }

    private func directionText(_ values: [Double]) -> String {
        guard let first = values.first, let last = values.last, values.count >= 2 else {
            return "Learning"
        }

        let delta = last - first
        if abs(delta) < 0.25 {
            return "Stable"
        }

        return delta > 0 ? "Rising" : "Dropping"
    }

    private func freeChlorineInterpretation(_ test: PoolTest) -> String {
        if isFreeChlorineLow(test) {
            if test.resolvedPoolConditions.chlorineDemandContribution >= 3 {
                return "Low, with recent conditions that may increase demand."
            }
            return "Below the CYA-adjusted target."
        }
        return "Maintained near the CYA-adjusted target."
    }

    private func pHInterpretation(_ test: PoolTest) -> String {
        if 7.2...7.8 ~= test.pH {
            return "Safe operating range."
        }
        return test.pH < 7.2 ? "Low; watch for corrosion risk." : "High; watch for scale and comfort issues."
    }

    private func alkalinityInterpretation(_ test: PoolTest) -> String {
        if test.totalAlkalinity > 140 && 7.2...7.8 ~= test.pH {
            return "Elevated, but pH is safe."
        }
        if test.totalAlkalinity > 140 {
            return "Elevated; pH trend matters most."
        }
        return "In the normal buffer range."
    }

    private func cyaInterpretation(_ test: PoolTest) -> String {
        if test.cyanuricAcid > 80 {
            return "High; dilution may eventually be needed."
        }
        if test.cyanuricAcid > 50 {
            return "Elevated; maintain higher FC."
        }
        return "In a manageable range."
    }

    private func hardnessInterpretation(_ test: PoolTest) -> String {
        let status = ChemistryEngine().calciumHardnessStatus(test.calciumHardness, surface: viewModel.poolConfig.surfaceType)
        switch status {
        case .ideal, .slightlyLow, .slightlyHigh:
            return "Acceptable for the current surface."
        case .low:
            return "Low enough to watch corrosion balance."
        case .high, .critical:
            return "High enough to watch scaling risk."
        case .testing:
            return "Still learning from this reading."
        }
    }

    private func isFreeChlorineLow(_ test: PoolTest) -> Bool {
        test.freeChlorine < freeChlorineMinimum(for: test.cyanuricAcid)
    }

    private func freeChlorineMinimum(for cya: Double) -> Double {
        guard cya >= 20 else { return 1.0 }
        return max(1.0, cya * 0.075)
    }

    private func averageDemandScore(in tests: [PoolTest]) -> Double {
        guard !tests.isEmpty else { return 0 }
        let total = tests.reduce(0) { $0 + $1.resolvedPoolConditions.chlorineDemandContribution }
        return Double(total) / Double(tests.count)
    }

    private func completedChlorineTreatmentCount(in tests: [PoolTest]) -> Int {
        tests
            .flatMap(\.treatments)
            .filter { $0.isCompleted && $0.targetParameter == "freeChlorine" }
            .count
    }

    private func recentCleaningAndBrushingCount() -> Int {
        tests.prefix(6).filter { $0.resolvedPoolConditions.organicLoadReductionScore > 0 }.count
    }

    private func formatPPM(_ value: Double) -> String {
        "\(Int(value.rounded())) ppm"
    }

    private func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private extension Array where Element == Double {
    func isStrictlyRising() -> Bool {
        guard count >= 2 else { return false }
        return zip(dropFirst(), self).allSatisfy { current, previous in
            current > previous
        }
    }
}

private extension ArraySlice where Element == Double {
    func isStrictlyRising() -> Bool {
        Array(self).isStrictlyRising()
    }
}

private extension PoolConditions {
    var organicLoadReductionScore: Int {
        (skimmedDebris == .yes ? 1 : 0)
            + cleaningActivity.organicLoadReductionScore
            + poolBrushed.organicLoadReductionScore
    }
}

// MARK: - Preview

#Preview {
    InsightsView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
