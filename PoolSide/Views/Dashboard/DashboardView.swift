import SwiftUI
import SwiftData

struct DashboardView: View {

    @Binding var showingAddTest: Bool
    @Binding var showingSettings: Bool
    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    @State private var showingHistory = false
    @State private var editingTest: PoolTest? = nil
    @State private var swipedTestID: UUID? = nil
    @State private var welcomeMessage = DashboardWelcomeMessage.random()

    var latestTest: PoolTest? { tests.first }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hero header
                        headerSection
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 20)

                        if let test = latestTest {
                            // Score + readings card
                            scoreCard(test: test)
                                .padding(.horizontal, 16)

                            // Recent tests
                            recentTestsSection
                                .padding(.top, 28)
                        } else {
                            firstTimeCard
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                        }

                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationBarHidden(true)
            // Full history sheet
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            // Edit test sheet
            .fullScreenCover(item: $editingTest) { test in
                AddTestView(editingTest: test)
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)

                Group {
                    if let test = latestTest {
                        let status = viewModel.overallStatus(for: test)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Your pool looks")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(PoolColor.primaryText)
                            Text(scoreLabel(test.overallScore).lowercased() + "!")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(status == .ideal ? PoolColor.poolTeal : status.color)
                        }
                    } else {
                        Text(welcomeMessage)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(PoolColor.primaryText)
                            .lineLimit(3)
                    }
                }

                if let test = latestTest {
                    Text("Latest Test • \(test.date.relativeDisplay), \(timeString(test.date))")
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                        .padding(.top, 4)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Image("Dashboard Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 140)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
    }

    // MARK: - Score Card

    private func scoreCard(test: PoolTest) -> some View {
        HStack(alignment: .center, spacing: 20) {
            // Score ring
            VStack(spacing: 6) {
                ScoreRing(score: test.overallScore, size: 84)
                Text("Pool Score")
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
                Text(scoreLabel(test.overallScore))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(scoreColor(test.overallScore))
            }
            .frame(width: 90)

            // Readings list
            VStack(spacing: 0) {
                let readings = viewModel.readings(for: test)
                ForEach(readings) { reading in
                    readingRow(reading)
                    if reading.id != readings.last?.id {
                        Divider()
                            .overlay(PoolColor.divider)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private func readingRow(_ reading: ChemicalReading) -> some View {
        HStack(spacing: 10) {
            // Chemical icon
            Image(reading.parameter == "Free Chlorine" ? "Free Chlorine"
                : reading.parameter == "Total Chlorine" ? "Total Chlorine"
                : reading.parameter == "Total Alkalinity" ? "Alkalinity"
                : reading.parameter == "Calcium Hardness" ? "Hardness"
                : reading.parameter == "Cyanuric Acid" ? "CYA"
                : reading.parameter == "Salt Level" ? "Free Chlorine" // fallback
                : "pH")
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)

            Text(reading.parameter)
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            // Mini bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PoolColor.divider).frame(height: 5)
                    Capsule()
                        .fill(reading.status.color)
                        .frame(width: geo.size.width * barFill(reading), height: 5)
                }
            }
            .frame(height: 5)

            Text(formattedValue(reading))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.primaryText)
                .frame(width: 36, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Recent Tests

    private var recentTestsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Tests")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)
                Spacer()
                Button("See all") { showingHistory = true }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PoolColor.poolTeal)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(tests.prefix(7).enumerated()), id: \.element.id) { index, test in
                    SwipeToDeleteRow(
                        isOpen: swipedTestID == test.id,
                        onOpen: { swipedTestID = test.id },
                        onClose: { swipedTestID = nil },
                        onDelete: { deleteTest(test) }
                    ) {
                        recentTestRow(test)
                            .background(Color.white)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if swipedTestID == test.id {
                                    swipedTestID = nil
                                } else {
                                    editingTest = test
                                }
                            }
                    }

                    if index < min(tests.count, 7) - 1 {
                        Divider()
                            .overlay(PoolColor.divider)
                            .padding(.leading, 20)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            .padding(.horizontal, 16)
        }
    }

    private func recentTestRow(_ test: PoolTest) -> some View {
        HStack(spacing: 14) {
            // Date
            VStack(alignment: .leading, spacing: 1) {
                Text(shortDate(test.date))
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                Text(timeString(test.date))
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Score circle
            ZStack {
                Circle()
                    .stroke(scoreColor(test.overallScore).opacity(0.2), lineWidth: 2)
                Circle()
                    .fill(scoreColor(test.overallScore).opacity(0.1))
                Text("\(test.overallScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(test.overallScore))
            }
            .frame(width: 40, height: 40)

            // Status label
            Text(scoreLabel(test.overallScore))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(scoreColor(test.overallScore))
                .frame(width: 100, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func deleteTest(_ test: PoolTest) {
        if editingTest?.id == test.id {
            editingTest = nil
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            swipedTestID = nil
            modelContext.delete(test)
        }

        do {
            try modelContext.save()
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }

    private var firstTimeCard: some View {
        VStack(spacing: 16) {
            Image("Test Data Hero")
                .resizable()
                .scaledToFit()
                .frame(height: 140)

            VStack(spacing: 6) {
                Text("Log your first test")
                    .font(.headline)
                    .foregroundStyle(PoolColor.primaryText)
                Text("Tap + to record your pool's readings and get personalised treatment recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .multilineTextAlignment(.center)
            }

        }
        .padding(24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return "Good morning!"
        case 12..<17:
            return "Good afternoon!"
        default:
            return "Good evening!"
        }
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return "Great"
        case 75..<90:  return "Good"
        case 60..<75:  return "Fair"
        case 40..<60:  return "Needs Attention"
        default:       return "Critical"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return PoolColor.statusIdeal
        case 60..<75:  return PoolColor.statusSlight
        case 40..<60:  return PoolColor.statusOffRange
        default:       return PoolColor.statusCritical
        }
    }

    private func formattedValue(_ reading: ChemicalReading) -> String {
        reading.parameter == "pH"
            ? String(format: "%.1f", reading.value)
            : reading.value >= 100
                ? String(format: "%.0f", reading.value)
                : String(format: "%.1f", reading.value)
    }

    private func barFill(_ reading: ChemicalReading) -> CGFloat {
        switch reading.key {
        case "pH":              return CGFloat((reading.value - 6.4) / 2.4).clamped(to: 0.05...1)
        case "freeChlorine":    return CGFloat(reading.value / 6).clamped(to: 0.05...1)
        case "totalAlkalinity": return CGFloat(reading.value / 180).clamped(to: 0.05...1)
        case "calciumHardness": return CGFloat(reading.value / 600).clamped(to: 0.05...1)
        case "cyanuricAcid":    return CGFloat(reading.value / 120).clamped(to: 0.05...1)
        default:                return 0.5
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

private enum DashboardWelcomeMessage {
    static let messages = [
        "Welcome to\nPool Side!",
        "Let's get your\nwater dialed in.",
        "Clear water\nstarts here.",
        "Pool care,\nmade simple.",
        "Ready for a\nquick water check?",
        "Your pool plan\nstarts here.",
        "Fresh readings,\nbetter swims.",
        "Time to tune up\nthe water.",
        "Keep your pool\nswim-ready.",
        "A balanced pool\nis a happy pool.",
        "Let's make the\nwater sparkle.",
        "Test today,\nswim easier."
    ]

    static func random() -> String {
        messages.randomElement() ?? "Welcome to\nPool Side!"
    }
}

private struct SwipeToDeleteRow<Content: View>: View {
    let isOpen: Bool
    let onOpen: () -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var dragOffset: CGFloat = 0

    private let deleteWidth: CGFloat = 92
    private let fullSwipeDistance: CGFloat = 220

    private var rowOffset: CGFloat {
        if dragOffset < 0 {
            return dragOffset
        }
        return isOpen ? -deleteWidth : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            PoolColor.statusCritical

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
            }

            content
                .offset(x: rowOffset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }

                            let baseOffset = isOpen ? -deleteWidth : 0
                            dragOffset = min(0, baseOffset + value.translation.width)
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                dragOffset = 0
                                return
                            }

                            let didFullSwipe = rowOffset < -fullSwipeDistance
                                || abs(value.predictedEndTranslation.width) > fullSwipeDistance

                            if didFullSwipe {
                                onDelete()
                            } else if rowOffset < -(deleteWidth * 0.45) {
                                onOpen()
                            } else {
                                onClose()
                            }

                            dragOffset = 0
                        }
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOpen)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: dragOffset)
        }
        .clipped()
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showingAddTest = false
    @Previewable @State var showingSettings = false
    DashboardView(
        showingAddTest: $showingAddTest,
        showingSettings: $showingSettings
    )
    .environment(PoolViewModel())
    .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
