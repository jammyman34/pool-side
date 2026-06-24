import SwiftUI
import SwiftData

struct DashboardView: View {

    @Binding var showingAddTest: Bool
    @Binding var showingSettings: Bool
    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    @State private var showingHistory = false
    @State private var editRoute: DashboardEditRoute? = nil
    @State private var swipedTestID: UUID? = nil
    @State private var welcomeMessage = DashboardWelcomeMessage.random()
    @State private var weather = PoolWeatherService()
    @State private var showingRefreshToast = false
    @State private var refreshToastMessage = ""
    @State private var refreshToastIsError = false
    @State private var isRefreshingWeather = false

    var latestTest: PoolTest? { tests.first }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Hero header
                        headerSection
                            .padding(.horizontal, 28)
                            .padding(.top, 18)
                            .padding(.bottom, 18)

                        if let test = latestTest {
                            // Score + readings card
                            scoreCard(test: test)
                                .padding(.horizontal, 28)

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
                .refreshable {
                    print("[Weather] User-initiated pull-to-refresh")
                    await MainActor.run { isRefreshingWeather = true }
                    await refreshWeatherIfPossible(force: true)
                    await MainActor.run {
                        if weather.lastRefreshSucceeded {
                            refreshToastMessage = "Weather updated"
                            refreshToastIsError = false
                        } else {
                            refreshToastMessage = weather.lastErrorMessage ?? "Weather update failed"
                            refreshToastIsError = true
                        }
                        withAnimation { showingRefreshToast = true }
                        let dismissDelay: TimeInterval = refreshToastIsError ? 5.0 : 1.4
                        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
                            withAnimation { showingRefreshToast = false }
                        }
                        isRefreshingWeather = false
                    }
                }

                if isRefreshingWeather {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(PoolColor.primaryText)
                            Text("Updating weather…")
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.primaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isRefreshingWeather)
                }

                if showingRefreshToast {
                    VStack {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: refreshToastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(refreshToastIsError ? PoolColor.statusOffRange : PoolColor.statusIdeal)
                            Text(refreshToastMessage)
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.primaryText)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showingRefreshToast)
                    .padding(.horizontal, 16)
                }
            }
            .navigationBarHidden(true)
            .task(id: weatherTaskID) {
                await refreshWeatherIfPossible()
            }
            // Full history sheet
            .sheet(isPresented: $showingHistory) {
                HistoryView()
            }
            // Edit test sheet
            .fullScreenCover(item: $editRoute) { route in
                AddTestView(
                    editingTest: route.test,
                    startsOnTreatmentPlan: route.startsOnTreatmentPlan
                )
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(greetingLineText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PoolColor.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer()

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.circle")
                        .font(.system(size: 40, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(PoolColor.primaryText)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: -12)
                .zIndex(10)
            }
            .padding(.bottom, -24)
            .zIndex(10)

            heroTitle
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 112)
                .background(alignment: .topTrailing) {
                    Image(heroAssetName)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(1.9)
                        .frame(width: 162, height: 160)
                        .offset(x: 24, y: 0)
                        .allowsHitTesting(false)
                        .padding(.top, -24)
                }
                .frame(height: latestTest == nil ? 112 : 112)
                .zIndex(0)
//                .border(.red, width: 0.5)

            if let test = latestTest {
                HStack(spacing: 5) {
                    Text("Latest Test")
                        .fontWeight(.bold)
                        .foregroundStyle(PoolColor.primaryText)
                    Text("• \(test.date.relativeDisplay), \(timeString(test.date))")
                        .foregroundStyle(PoolColor.secondaryText)
                }
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var heroTitle: some View {
        if let test = latestTest {
            let status = viewModel.overallStatus(for: test)
            let score = score(for: test)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your pool looks")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(PoolColor.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(scoreLabel(score).lowercased() + "!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(status == .ideal ? PoolColor.poolTeal : status.color)
                    .lineLimit(1)
            }
        } else {
            Text(welcomeMessage)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.86)
        }
    }

    // MARK: - Score Card

    private func scoreCard(test: PoolTest) -> some View {
        let score = score(for: test)

        return HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 8) {
                ScoreRing(score: score, size: 118)
                Text("Pool Score")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                Text(scoreLabel(score))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(scoreColor(score))
            }
            .frame(width: 134)

            Rectangle()
                .fill(PoolColor.divider)
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(spacing: 0) {
                let readings = Array(viewModel.readings(for: test).prefix(5))
                ForEach(readings) { reading in
                    readingRow(reading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(PoolColor.divider.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }

    private func readingRow(_ reading: ChemicalReading) -> some View {
        HStack(spacing: 12) {
            Text(reading.parameter)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PoolColor.divider)
                        .frame(height: 8)
                    Capsule()
                        .fill(reading.status.color == PoolColor.statusIdeal ? PoolColor.poolTeal : reading.status.color)
                        .frame(width: geo.size.width * barFill(reading), height: 8)
                }
            }
            .frame(width: 84, height: 8)

            Text(formattedValue(reading))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PoolColor.primaryText)
                .frame(width: 42, alignment: .trailing)
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
//                Button("See all") { showingHistory = true }
//                    .font(.subheadline)
//                    .fontWeight(.medium)
//                    .foregroundStyle(PoolColor.poolTeal)
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
                                    editRoute = DashboardEditRoute(
                                        test: test,
                                        startsOnTreatmentPlan: true
                                    )
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
        let score = score(for: test)

        return HStack(spacing: 14) {
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
                    .stroke(scoreColor(score).opacity(0.2), lineWidth: 2)
                Circle()
                    .fill(scoreColor(score).opacity(0.1))
                Text("\(score)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
            }
            .frame(width: 40, height: 40)

            // Status label
            Text(scoreLabel(score))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(scoreColor(score))
                .frame(width: 100, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func score(for test: PoolTest) -> Int {
        viewModel.overallScore(
            for: test,
            previousTest: viewModel.previousTest(before: test, in: tests)
        )
    }

    private func deleteTest(_ test: PoolTest) {
        if editRoute?.test.id == test.id {
            editRoute = nil
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
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .scaleEffect(0.9)
                .clipped()

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
        .padding(16)
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

    private var greetingLineText: String {
        if let category = weather.category, let current = weather.currentTemperatureFahrenheit, let high = weather.highTemperatureFahrenheit {
            let line = "\(greetingText) \(category.shortDescription) C\(current)℉ (H\(high)℉)"
            print("[Weather] Greeting with forecast: \(line)")
            return line
        }
        let fallback = "\(greetingText) It's a great day for a pool day!"
        print("[Weather] Greeting fallback (no forecast): lat=\(viewModel.poolConfig.latitude?.description ?? "nil"), lon=\(viewModel.poolConfig.longitude?.description ?? "nil")")
        return fallback
    }

    private var heroAssetName: String {
        weather.category?.heroAssetName ?? "Sunny Hero"
    }

    private var weatherTaskID: String {
        let lat = viewModel.poolConfig.latitude.map { String(format: "%.3f", $0) } ?? "nil"
        let lon = viewModel.poolConfig.longitude.map { String(format: "%.3f", $0) } ?? "nil"
        return "\(lat),\(lon)"
    }

    private func refreshWeatherIfPossible(force: Bool = false) async {
        let loc = viewModel.poolConfig.location
        let latStr = viewModel.poolConfig.latitude?.description ?? "nil"
        let lonStr = viewModel.poolConfig.longitude?.description ?? "nil"

        print("\n===== WEATHER REFRESH BEGIN =====")
        print("[Weather] Config snapshot: location=\(loc), lat=\(latStr), lon=\(lonStr), force=\(force)")

        guard let latitude = viewModel.poolConfig.latitude, let longitude = viewModel.poolConfig.longitude else {
            print("[Weather] Decision: SKIP — coordinates are nil (cannot query weather provider)")
            print("===== WEATHER REFRESH END =====\n")
            return
        }

        // Cache decision is made inside PoolWeatherService.shouldSkipRefresh; we log before and after.
        print("[Weather] Decision: REQUEST — refreshing weather for lat=\(String(format: "%.6f", latitude)), lon=\(String(format: "%.6f", longitude))")
        await weather.refresh(latitude: latitude, longitude: longitude, force: force)

        let hasForecast = (weather.category != nil && weather.highTemperatureFahrenheit != nil)
        let categoryDesc = weather.category?.rawValue ?? "nil"
        let currentStr = weather.currentTemperatureFahrenheit.map { String($0) } ?? "nil"
        let highStr = weather.highTemperatureFahrenheit.map { String($0) } ?? "nil"
        print("[Weather] Result snapshot: hasForecast=\(hasForecast), category=\(categoryDesc), currentF=\(currentStr), highF=\(highStr)")

        // Greeting preview
        if hasForecast {
            let preview = "\(greetingText) \(weather.category?.shortDescription ?? "?") C\(weather.currentTemperatureFahrenheit ?? 0)℉ (H\(weather.highTemperatureFahrenheit ?? 0)℉)"
            print("[Weather] Greeting preview: \(preview)")
        } else {
            print("[Weather] Greeting preview: \(greetingText) It's a great day for a pool day!")
        }

        // Clipboard-ready summary
        let summary = "WEATHER SUMMARY — location=\(loc), lat=\(latStr), lon=\(lonStr), requested=true, hasForecast=\(hasForecast), category=\(categoryDesc), currentF=\(currentStr), highF=\(highStr)"
        print(summary)
        print("===== WEATHER REFRESH END =====\n")
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 90...100: return "Great"
        case 75..<90:  return "Good"
        case 60..<75:  return "Alright"
        case 40..<60:  return "Not Great"
        default:       return "Real Bad"
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

private struct DashboardEditRoute: Identifiable {
    let test: PoolTest
    let startsOnTreatmentPlan: Bool

    var id: UUID { test.id }
}

private enum DashboardWelcomeMessage {
    static let messages = [
        "Welcome to\nPool Side!",
        "Let's get your\nwater dialed in.",
        "Clear water\nstarts here.",
        "Pool care,\nmade simple.",
        "Quick water check time?",
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
