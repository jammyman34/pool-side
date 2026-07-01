import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

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
                            testingCadenceCard
                            poolScoreCard
                            chemicalBalanceCard
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

    // MARK: - Testing Cadence

    private var testingCadenceCard: some View {
        chartCard(title: "Testing Cadence", subtitle: "Last 30 days") {
            let days = cadenceDays()
            if last30DaysTests.isEmpty {
                Text("No test data in the last 30 days")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
                        spacing: 6
                    ) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(cadenceColor(for: day.count))
                                .frame(height: 22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(day.isToday ? PoolColor.primaryText.opacity(0.35) : .clear, lineWidth: 1)
                                )
                                .accessibilityLabel("\(day.label): \(day.count) test\(day.count == 1 ? "" : "s")")
                        }
                    }

                    HStack(spacing: 8) {
                        cadenceStat(title: "Last Tested", value: lastTestedText())
                        cadenceStat(title: "30-Day Tests", value: "\(last30DaysTests.count)")
                        cadenceStat(title: "Avg Gap", value: averageTestGapText())
                    }

                    HStack(spacing: 8) {
                        cadenceLegendSwatch(count: 0, label: "None")
                        cadenceLegendSwatch(count: 1, label: "1")
                        cadenceLegendSwatch(count: 2, label: "2")
                        cadenceLegendSwatch(count: 3, label: "3+")
                    }
                }
            }
        }
    }

    // MARK: - Pool Score Line Chart

    private var poolScoreCard: some View {
        chartCard(title: "Pool Score", subtitle: "Trend over time") {
            let data = poolScoreData()
            if data.count < 2 {
                Text("Need at least 2 tests to show a trend")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
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
            }
        }
    }

    // MARK: - Chemical Balance Donut

    private var chemicalBalanceCard: some View {
        chartCard(title: "Chemical Balance", subtitle: "All readings from last 30 days") {
            let segments = chemicalBalanceData()
            if segments.allSatisfy({ $0.count == 0 }) {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                HStack(spacing: 24) {
                    Chart(segments) { seg in
                        SectorMark(
                            angle: .value("Readings", seg.count),
                            innerRadius: .ratio(0.52),
                            angularInset: 2
                        )
                        .foregroundStyle(seg.color)
                        .cornerRadius(3)
                    }
                    .frame(width: 130, height: 130)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(segments.filter { $0.count > 0 }, id: \.label) { seg in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(seg.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(seg.label)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(PoolColor.primaryText)
                                    let total = segments.reduce(0) { $0 + $1.count }
                                    let pct = total > 0 ? Int(Double(seg.count) / Double(total) * 100) : 0
                                    Text("\(pct)%")
                                        .font(.caption2)
                                        .foregroundStyle(PoolColor.secondaryText)
                                }
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Card Shell

    private func chartCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 52))
                .foregroundStyle(PoolColor.poolTeal.opacity(0.5))
            Text("No data yet")
                .font(.headline)
                .foregroundStyle(PoolColor.primaryText)
            Text("Log a few tests and your trends will appear here.")
                .font(.subheadline)
                .foregroundStyle(PoolColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    // MARK: - Data Helpers

    struct CadenceDay: Identifiable {
        let id = UUID()
        let date: Date
        let label: String
        let count: Int
        let isToday: Bool
    }

    struct ScorePoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Int
    }

    struct BalanceSegment: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
        let color: Color
    }

    private func cadenceDays() -> [CadenceDay] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: last30DaysTests) { test in
            cal.startOfDay(for: test.date)
        }
        let df = DateFormatter()
        df.dateFormat = "MMM d"

        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -29, to: today) else {
            return []
        }

        return (0..<30).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return CadenceDay(
                date: day,
                label: df.string(from: day),
                count: grouped[day]?.count ?? 0,
                isToday: cal.isDateInToday(day)
            )
        }
    }

    private func cadenceColor(for count: Int) -> Color {
        switch count {
        case 0:
            return PoolColor.divider.opacity(0.45)
        case 1:
            return PoolColor.poolTeal.opacity(0.35)
        case 2:
            return PoolColor.poolTeal.opacity(0.62)
        default:
            return PoolColor.poolTeal
        }
    }

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

    private func cadenceLegendSwatch(count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(cadenceColor(for: count))
                .frame(width: 12, height: 12)

            Text(label)
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText)
        }
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
        let cal = Calendar.current
        let uniqueDays = Array(Set(tests.map { cal.startOfDay(for: $0.date) })).sorted()
        guard uniqueDays.count >= 2 else { return "Need 2" }

        let gaps = zip(uniqueDays.dropFirst(), uniqueDays).compactMap { current, previous in
            cal.dateComponents([.day], from: previous, to: current).day
        }
        guard !gaps.isEmpty else { return "Need 2" }

        let average = Double(gaps.reduce(0, +)) / Double(gaps.count)
        if average >= 10 {
            return "\(Int(average.rounded()))d"
        }
        return String(format: "%.1fd", average)
    }

    private func poolScoreData() -> [ScorePoint] {
        let chronologicalTests = tests.sorted { $0.date < $1.date }
        return chronologicalTests.enumerated().map { index, test in
            let previousTest = index > 0 ? chronologicalTests[index - 1] : nil
            return ScorePoint(
                date: test.date,
                score: viewModel.overallScore(for: test, previousTest: previousTest)
            )
        }
    }

    private func scoreChartWidth(for pointCount: Int) -> CGFloat {
        max(320, CGFloat(pointCount) * 64)
    }

    private func chemicalBalanceData() -> [BalanceSegment] {
        var ideal = 0, slight = 0, offRange = 0, critical = 0

        for test in last30DaysTests {
            let readings = viewModel.readings(for: test)
            for r in readings {
                switch r.status {
                case .ideal:                        ideal += 1
                case .slightlyLow, .slightlyHigh:   slight += 1
                case .low, .high:                   offRange += 1
                case .critical, .testing:           critical += 1
                }
            }
        }

        return [
            BalanceSegment(label: "In Range",       count: ideal,    color: PoolColor.statusIdeal),
            BalanceSegment(label: "Slightly Off",   count: slight,   color: PoolColor.statusSlight),
            BalanceSegment(label: "Needs Attention",count: offRange,  color: PoolColor.statusOffRange),
            BalanceSegment(label: "Critical",       count: critical, color: PoolColor.statusCritical)
        ]
    }
}

// MARK: - Preview

#Preview {
    InsightsView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
