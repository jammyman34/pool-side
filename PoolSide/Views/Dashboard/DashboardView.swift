import SwiftUI
import SwiftData

struct DashboardView: View {

    @Binding var showingAddTest: Bool
    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    var latestTest: PoolTest? { tests.first }
    var previousTest: PoolTest? { tests.dropFirst().first }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 20) {
                        // Hero header
                        headerSection

                        if let test = latestTest {
                            // Overall score
                            scoreSection(test: test)

                            // AI Assessment card
                            if let assessment = test.aiAssessment {
                                assessmentCard(text: assessment)
                            }

                            // Chemical readings grid
                            readingsSection(test: test)

                            // Quick access to pending treatments
                            let pending = viewModel.pendingTreatments(from: tests)
                            if !pending.isEmpty {
                                pendingTreatmentsTeaser(treatments: pending)
                            }
                        } else {
                            firstTimePrompt
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }

                // AI loading overlay
                if viewModel.isGeneratingRecommendations {
                    VStack {
                        Spacer()
                        AILoadingOverlay()
                        Spacer().frame(height: 120)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(viewModel.poolConfig.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                if let test = latestTest {
                    await generateRecommendations(for: test)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.cloudWhite)
                if let test = latestTest {
                    Text("Last tested \(test.date.relativeDisplay.lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
                }
            }
            Spacer()
            if let test = latestTest {
                let status = viewModel.overallStatus(for: test)
                StatusBadge(status: status)
            }
        }
        .padding(.top, 8)
    }

    private func scoreSection(test: PoolTest) -> some View {
        HStack(spacing: 16) {
            ScoreRing(score: test.overallScore, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text(scoreLabel(test.overallScore))
                    .font(.headline)
                    .foregroundStyle(PoolColor.cloudWhite)
                Text(scoreSubtitle(for: test))
                    .font(.caption)
                    .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer()

            Button {
                Task { await generateRecommendations(for: test) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.aiServiceAvailable ? "sparkles" : "wand.and.stars")
                        .font(.system(size: 18))
                    Text("Analyse")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(PoolColor.deepWater)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PoolColor.sunshine, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isGeneratingRecommendations)
        }
        .padding(16)
        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))
    }

    private func assessmentCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.aiServiceAvailable ? "sparkles" : "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(PoolColor.poolTeal)
                Text(viewModel.aiServiceAvailable ? "AI Assessment" : "Assessment")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [PoolColor.poolTeal.opacity(0.15), PoolColor.oceanBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PoolColor.poolTeal.opacity(0.3), lineWidth: 1)
        )
    }

    private func readingsSection(test: PoolTest) -> some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Chemical Readings")

            let readings = viewModel.readings(for: test, previousTest: previousTest)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(readings) { reading in
                    ChemicalStatusCard(reading: reading)
                }
            }
        }
    }

    private func pendingTreatmentsTeaser(treatments: [Treatment]) -> some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Pending Treatments")

            VStack(spacing: 0) {
                ForEach(Array(treatments.prefix(3).enumerated()), id: \.element.id) { index, treatment in
                    TreatmentTeaser(treatment: treatment)
                    if index < min(treatments.count, 3) - 1 {
                        Divider().overlay(PoolColor.cloudWhite.opacity(0.1))
                    }
                }
            }
            .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 16))

            if treatments.count > 3 {
                Text("+ \(treatments.count - 3) more")
                    .font(.caption)
                    .foregroundStyle(PoolColor.poolTeal)
            }
        }
    }

    private var firstTimePrompt: some View {
        EmptyStateView(
            icon: "drop.fill",
            title: "Log Your First Test",
            message: "Tap the + button to record your pool's chemical readings and get personalised treatment recommendations.",
            actionLabel: "Log Test",
            action: { showingAddTest = true }
        )
        .padding(.top, 40)
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning ☀️"
        case 12..<17: return "Good afternoon 🌊"
        case 17..<21: return "Good evening 🌅"
        default:      return "Pool Status 🌙"
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return "Excellent"
        case 75..<90:  return "Good"
        case 50..<75:  return "Needs Attention"
        default:       return "Action Required"
        }
    }

    private func scoreSubtitle(for test: PoolTest) -> String {
        let readings = viewModel.readings(for: test)
        let out = readings.filter { $0.status != .ideal }.count
        if out == 0 { return "All parameters in range" }
        return "\(out) parameter\(out == 1 ? "" : "s") out of range"
    }

    private func generateRecommendations(for test: PoolTest) async {
        let recent = Array(tests.dropFirst().prefix(13))
        await viewModel.generateRecommendations(
            for: test,
            recentTests: recent,
            modelContext: modelContext
        )
    }
}

// MARK: - Treatment Teaser Row

struct TreatmentTeaser: View {
    let treatment: Treatment

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(treatment.urgency == .immediate ? PoolColor.statusCritical : PoolColor.sunshine)
                .frame(width: 8, height: 8)
            Text(treatment.chemicalName)
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite)
                .lineLimit(1)
            Spacer()
            Text(treatment.urgency.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(treatment.urgency == .immediate ? PoolColor.statusCritical : PoolColor.cloudWhite.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
