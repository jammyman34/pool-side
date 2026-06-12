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

                if tests.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            testFrequencyCard
                            poolScoreCard
                            chemicalBalanceCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Test Frequency Bar Chart

    private var testFrequencyCard: some View {
        chartCard(title: "Test Frequency", subtitle: "Last 30 days") {
            let data = testFrequencyData()
            if data.isEmpty {
                Text("No test data in the last 30 days")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Week", item.label),
                        y: .value("Tests", item.count)
                    )
                    .foregroundStyle(PoolColor.poolTeal.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(PoolColor.divider)
                        AxisValueLabel()
                            .foregroundStyle(PoolColor.secondaryText)
                    }
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel()
                            .foregroundStyle(PoolColor.secondaryText)
                    }
                }
                .frame(height: 160)
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
                    AxisMarks(values: .stride(by: .day, count: 7)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(PoolColor.secondaryText)
                    }
                }
                .frame(height: 160)
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

    struct WeeklyCount: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
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

    private func testFrequencyData() -> [WeeklyCount] {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -27, to: cal.startOfDay(for: Date())) else {
            return []
        }
        // 4 weeks
        return (0..<4).compactMap { weekIndex -> WeeklyCount? in
            guard let weekStart = cal.date(byAdding: .day, value: weekIndex * 7, to: start),
                  let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }

            let count = last30DaysTests.filter { $0.date >= weekStart && $0.date < weekEnd }.count
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            return WeeklyCount(label: df.string(from: weekStart), count: count)
        }
    }

    private func poolScoreData() -> [ScorePoint] {
        Array(last30DaysTests.prefix(20).reversed()).map {
            ScorePoint(date: $0.date, score: $0.overallScore)
        }
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
