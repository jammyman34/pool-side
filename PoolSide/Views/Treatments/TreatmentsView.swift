import SwiftUI
import SwiftData

struct TreatmentsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]
    @State private var showingCompleted: Bool = false

    private var pendingTreatments: [Treatment] {
        viewModel.pendingTreatments(from: tests)
    }

    private var completedTreatments: [Treatment] {
        viewModel.completedTreatments(from: tests)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                if pendingTreatments.isEmpty && completedTreatments.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "No Treatments",
                        message: "Log a test to generate AI-powered treatment recommendations for your pool."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Summary banner
                            if !pendingTreatments.isEmpty {
                                summaryBanner
                            }

                            // Pending treatments
                            if !pendingTreatments.isEmpty {
                                pendingSection
                            }

                            // Completed toggle
                            if !completedTreatments.isEmpty {
                                completedSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Treatments")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Sections

    private var summaryBanner: some View {
        let immediateCount = pendingTreatments.filter { $0.urgency == .immediate }.count
        let total = pendingTreatments.count

        return HStack(spacing: 12) {
            Image(systemName: immediateCount > 0 ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.title2)
                .foregroundStyle(immediateCount > 0 ? PoolColor.statusCritical : PoolColor.sunshine)

            VStack(alignment: .leading, spacing: 2) {
                Text(immediateCount > 0 ? "Immediate Action Needed" : "\(total) Treatment\(total == 1 ? "" : "s") Pending")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.cloudWhite)
                Text(immediateCount > 0
                    ? "\(immediateCount) critical item\(immediateCount == 1 ? "" : "s") require\(immediateCount == 1 ? "s" : "") attention now."
                    : "Complete these to keep your pool balanced."
                )
                .font(.caption)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
            }
            Spacer()
        }
        .padding(16)
        .background(
            immediateCount > 0
                ? AnyShapeStyle(PoolColor.statusCritical.opacity(0.12))
                : AnyShapeStyle(PoolColor.sunshine.opacity(0.1)),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    immediateCount > 0 ? PoolColor.statusCritical.opacity(0.3) : PoolColor.sunshine.opacity(0.2),
                    lineWidth: 1
                )
        )
    }

    private var pendingSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "To Do (\(pendingTreatments.count))")

            VStack(spacing: 1) {
                ForEach(pendingTreatments) { treatment in
                    TreatmentRowView(treatment: treatment, showCheckbox: true) {
                        viewModel.completeTreatment(treatment)
                    }
                    .background(PoolColor.oceanBlue)

                    if treatment.id != pendingTreatments.last?.id {
                        Divider().overlay(PoolColor.cloudWhite.opacity(0.07))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var completedSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingCompleted.toggle()
                }
            } label: {
                HStack {
                    Text("Completed (\(completedTreatments.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Image(systemName: showingCompleted ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.4))
                }
            }

            if showingCompleted {
                VStack(spacing: 1) {
                    ForEach(completedTreatments.prefix(20)) { treatment in
                        TreatmentRowView(treatment: treatment, showCheckbox: false)
                            .background(PoolColor.oceanBlue.opacity(0.6))

                        if treatment.id != completedTreatments.prefix(20).last?.id {
                            Divider().overlay(PoolColor.cloudWhite.opacity(0.05))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .opacity(0.75)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TreatmentsView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
        .preferredColorScheme(.dark)
}
