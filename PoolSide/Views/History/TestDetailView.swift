import SwiftUI

struct TestDetailView: View {

    let test: PoolTest
    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header summary
                        headerCard

                        // AI Assessment if present
                        if let assessment = test.aiAssessment {
                            assessmentCard(assessment)
                        }

                        // All readings
                        VStack(spacing: 12) {
                            SectionHeader(title: "Readings")
                            let readings = viewModel.readings(for: test)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(readings) { reading in
                                    ChemicalStatusCard(reading: reading)
                                }
                            }
                        }

                        // Treatments for this test
                        let treatments = test.treatments.sorted { $0.createdAt < $1.createdAt }
                        if !treatments.isEmpty {
                            treatmentsSection(treatments)
                        }

                        // Notes
                        if !test.notes.isEmpty {
                            notesSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(test.date.relativeDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerCard: some View {
        HStack(spacing: 16) {
            ScoreRing(score: viewModel.overallScore(for: test), size: 68)

            VStack(alignment: .leading, spacing: 6) {
                Text(test.date.fullDisplay)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                let status = viewModel.overallStatus(for: test)
                StatusBadge(status: status)
                let count = test.treatments.count
                if count > 0 {
                    Text("\(count) treatment\(count == 1 ? "" : "s") generated")
                        .font(.caption)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))
    }

    private func assessmentCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Assessment", systemImage: "sparkles")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.poolTeal)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.85))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PoolColor.poolTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(PoolColor.poolTeal.opacity(0.25), lineWidth: 1))
    }

    private func treatmentsSection(_ treatments: [Treatment]) -> some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Treatments")
            VStack(spacing: 1) {
                ForEach(treatments) { treatment in
                    TreatmentRowView(treatment: treatment, showCheckbox: false)
                        .background(PoolColor.oceanBlue)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Notes")
            Text(test.notes)
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.8))
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Preview

#Preview {
    let test = PoolTest(
        pH: 7.5,
        freeChlorine: 1.8,
        totalChlorine: 2.0,
        totalAlkalinity: 100,
        calciumHardness: 280,
        cyanuricAcid: 40,
        notes: "Sunny day, light bather load.",
        aiAssessment: "Pool chemistry is well-balanced. Continue your current routine and retest in 3–4 days."
    )
    return TestDetailView(test: test)
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
        .preferredColorScheme(.dark)
}
