import SwiftUI
import SwiftData

struct HistoryView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]
    @State private var selectedTest: PoolTest?
    @State private var showingDeleteConfirm: Bool = false
    @State private var testToDelete: PoolTest?

    private var groupedTests: [(key: String, value: [PoolTest])] {
        let grouped = Dictionary(grouping: tests) { $0.date.monthYearKey }
        return grouped.sorted { a, b in
            guard
                let dateA = tests.first(where: { $0.date.monthYearKey == a.key })?.date,
                let dateB = tests.first(where: { $0.date.monthYearKey == b.key })?.date
            else { return false }
            return dateA > dateB
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                if tests.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.clock",
                        title: "No Tests Yet",
                        message: "Your test history will appear here once you've logged your first reading."
                    )
                } else {
                    List {
                        ForEach(groupedTests, id: \.key) { group in
                            Section(header: monthHeader(group.key)) {
                                ForEach(group.value) { test in
                                    HistoryRow(test: test, viewModel: viewModel)
                                        .listRowBackground(PoolColor.oceanBlue)
                                        .listRowSeparatorTint(PoolColor.cloudWhite.opacity(0.1))
                                        .onTapGesture { selectedTest = test }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                testToDelete = test
                                                showingDeleteConfirm = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $selectedTest) { test in
                TestDetailView(test: test)
            }
            .confirmationDialog(
                "Delete this test?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Test", role: .destructive) {
                    if let test = testToDelete {
                        modelContext.delete(test)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will also delete any associated treatments. This action cannot be undone.")
            }
        }
    }

    private func monthHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(PoolColor.cloudWhite.opacity(0.5))
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let test: PoolTest
    let viewModel: PoolViewModel

    private var status: ChemicalStatus {
        viewModel.overallStatus(for: test)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Date column
            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(PoolColor.cloudWhite)
                Text(monthAbbrev)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.cloudWhite.opacity(0.5))
            }
            .frame(width: 36)

            Divider()
                .frame(height: 36)
                .overlay(status.color.opacity(0.6))

            // Readings preview
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    miniReading(label: "pH", value: String(format: "%.1f", test.pH))
                    miniReading(label: "Cl", value: String(format: "%.1f", test.freeChlorine))
                    miniReading(label: "Alk", value: String(format: "%.0f", test.totalAlkalinity))
                }
                if !test.notes.isEmpty {
                    Text(test.notes)
                        .font(.caption2)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status + treatments count
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: status, compact: true)
                let pending = test.treatments.filter { !$0.isCompleted }.count
                if pending > 0 {
                    Text("\(pending) pending")
                        .font(.caption2)
                        .foregroundStyle(PoolColor.sunshine.opacity(0.8))
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.3))
        }
        .padding(.vertical, 6)
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: test.date)
    }

    private var monthAbbrev: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: test.date).uppercased()
    }

    private func miniReading(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolColor.cloudWhite)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.45))
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
        .preferredColorScheme(.dark)
}
