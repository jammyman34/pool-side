import SwiftUI
import SwiftData

struct DashboardView: View {

    @Binding var showingAddTest: Bool
    @Binding var showingSettings: Bool
    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
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

                            // Active (persistent) / Completed workflow sections.
                            // The next-test badge lives inside the Active Tests header.
                            workflowSections(for: test)
                                .padding(.horizontal, 28)
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
            // Re-check the forecast whenever the app returns to the foreground. This is a non-forced
            // refresh, so PoolWeatherService's freshness cache (30 min) avoids redundant network calls.
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await refreshWeatherIfPossible() }
            }
            .dashboardWalkthrough(isEligible: latestTest != nil)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextTestPill(for test: PoolTest) -> some View {
        // Presentation-only: consume the scheduling authority's firstUpcoming; never derive dates here.
        // Tapping opens Add Test preselected to the scheduled scope. The global + cover resolves the same
        // firstUpcoming scope, so both routes land on the correct FC & pH / Full Test entry.
        return TimelineView(.periodic(from: .now, by: 60)) { context in
            let firstUpcoming = viewModel.nextTestSchedule(for: test, in: tests, now: context.date)?.firstUpcoming
            let label = nextTestPillText(for: firstUpcoming, now: context.date)

            Button {
                showingAddTest = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: nextTestPillIcon(for: firstUpcoming))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolColor.poolTeal)

                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(PoolColor.poolTeal.opacity(0.14), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(PoolColor.poolTeal.opacity(0.40), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint("Opens Add Test for the scheduled test type")
        }
    }

    private func dashboardHeroTitle(for test: PoolTest) -> String {
        // The hero headline is driven first by the canonical Swimability V2 readiness state (mapped via`swimReadinessStatus`). Only when V2 can't produce a definitive readiness (`.unknown`) do we fall back to describing the treatment-plan state.
        switch swimReadinessStatus(for: test) {
        case .readyNow:
            // Shown when Swimability V2 says the pool is ready to swim right now (all swim gates pass, evidence is fresh). This is the "green light" headline.
            return "Pool is ready, enjoy!"
        case .readyAfterWait:
            // Shown when V2 expects the pool to become swim-ready after a wait — e.g. a treatment is circulating or a product needs time to disperse, but no gate currently fails outright.
            return "Almost swim-ready"
        case .notRecommended:
            // Shown when V2 actively blocks swimming (a gate fails — e.g. low sanitizer, high pH/CC, algae/cloudy water). This is the "do not swim / verify first" headline.
            return "Check before swimming"
        case .unknown:
            // V2 has no definitive readiness (e.g. insufficient/stale evidence). Fall through to the treatment-plan-based headlines below.
            break
        }

        // Reached only on `.unknown`. If a required correction is still outstanding, prompt the user to act — surfaced when at least one non-watchlist treatment step is pending at immediate/recommended urgency.
        let pendingActions = test.treatments.filter { !$0.isCompleted && !$0.isSkipped && !$0.isWatchlistItem }
        if pendingActions.contains(where: { $0.urgency.isActionable }) {
            return "Review your plan"
        }

        // Reached on `.unknown` with no required treatment outstanding. If nothing at all is in progress (no incomplete/non-skipped treatments or checks), the workflow is quiet — surface a reassuring "nothing to do" headline.
        let activeTreatments = test.treatments.filter { !$0.isCompleted && !$0.isSkipped }
        if activeTreatments.isEmpty {
            return "All clear for now"
        }

        // Reached on `.unknown` when work is still in progress but nothing is a *required* action right now (e.g. only optional/advisory steps or a pending focused Check remain). A neutral fallback headline.
        return "Latest pool check"
    }

    /// Presentation only: the Dashboard maps the canonical Swimability V2 assessment (the single
    /// production readiness authority) to its hero vocabulary. It performs NO chemistry/readiness
    /// calculation of its own — all thresholds live in ChemistryPolicy / SwimReadinessGateEvaluator.
    private func swimReadinessStatus(for test: PoolTest) -> DashboardSwimReadinessStatus {
        DashboardSwimReadinessStatus(swimabilityState: viewModel.swimReadinessAssessment(for: test, in: tests).state)
    }

    @ViewBuilder
    private var heroTitle: some View {
        if let test = latestTest {
            Text(dashboardHeroTitle(for: test))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
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
                currentStatusRow(for: test)
            }
            .frame(width: 134)

            Rectangle()
                .fill(PoolColor.divider)
                .frame(width: 1)
                .padding(.vertical, 6)

            VStack(spacing: 0) {
                ForEach(dashboardReadings(for: test)) { reading in
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

    private func currentStatusRow(for test: PoolTest) -> some View {
        let summary = viewModel.currentStatusSummary(for: test)

        return Button {
            editRoute = DashboardEditRoute(test: test, startsOnTreatmentPlan: true)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Current Status")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)

                HStack(alignment: .center, spacing: 8) {
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(PoolColor.secondaryText.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current status: \(summary). Open treatment plan")
    }

    private func readingRow(_ reading: ChemicalReading) -> some View {
        HStack(spacing: 12) {
            Text(dashboardAbbreviation(for: reading))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 34, alignment: .leading)

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

    private func workflowSections(for latestTest: PoolTest) -> some View {
        let workflows = viewModel.dashboardWorkflows(from: tests)
        return VStack(alignment: .leading, spacing: 28) {
            // Active Tests is always present. Its header hosts the next-test badge.
            activeTestsSection(items: workflows.active, latestTest: latestTest)

            if !workflows.completed.isEmpty {
                workflowSection(title: "Completed Tests", items: Array(workflows.completed.prefix(12)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Persistent Active Tests section. When there are active rows the next-test badge sits on the
    /// title row (≥24pt gap); when there are none the badge drops beneath the title, centered, with
    /// 32pt top spacing.
    @ViewBuilder
    private func activeTestsSection(items: [DashboardWorkflowItem], latestTest: PoolTest) -> some View {
        let hasBadge = viewModel.nextTestSchedule(for: latestTest, in: tests)?.firstUpcoming.recommendedDate != nil

        VStack(spacing: 0) {
            if items.isEmpty {
                HStack {
                    activeTestsTitle
                    Spacer()
                }
                .padding(.horizontal, 4)

                if hasBadge {
                    nextTestPill(for: latestTest)
                        .padding(.top, 32)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                HStack(alignment: .center) {
                    activeTestsTitle
                    if hasBadge {
                        Spacer(minLength: 24)
                        nextTestPill(for: latestTest)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 12)

                workflowRowsCard(items: items)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var activeTestsTitle: some View {
        Text("Active Tests")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(PoolColor.primaryText)
    }

    private func workflowSection(title: String, items: [DashboardWorkflowItem]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            workflowRowsCard(items: items)
        }
        .frame(maxWidth: .infinity)
    }

    private func workflowRowsCard(items: [DashboardWorkflowItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SwipeToDeleteRow(
                    isOpen: swipedTestID == item.rootTestID,
                    onOpen: { swipedTestID = item.rootTestID },
                    onClose: { swipedTestID = nil },
                    onDelete: { deleteTestID(item.rootTestID) }
                ) {
                    workflowRow(item)
                        .background(Color.white)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if swipedTestID == item.rootTestID {
                                swipedTestID = nil
                            } else if let test = tests.first(where: { $0.id == item.rootTestID }) {
                                editRoute = DashboardEditRoute(test: test, startsOnTreatmentPlan: true)
                            }
                        }
                }

                if index < items.count - 1 {
                    Divider()
                        .overlay(PoolColor.divider)
                        .padding(.leading, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    @ViewBuilder
    private func workflowRow(_ item: DashboardWorkflowItem) -> some View {
        HStack(spacing: 14) {
            // Leading: test-type icon (Active/Completed rows only) + original date/time
            Image(systemName: item.testScope.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PoolColor.poolTeal)
                .frame(width: 20)
                .accessibilityLabel(item.testScope.displayName)

            VStack(alignment: .leading, spacing: 1) {
                Text(shortDate(item.originalTestDate))
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                Text(timeString(item.originalTestDate))
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
            }
            .frame(width: 72, alignment: .leading)

            Spacer(minLength: 8)

            // Center: workflow state or final score
            switch item.state {
            case .treatmentNeeded:
                workflowStateContent(icon: "flask.fill", label: "Treatment Needed", color: PoolColor.treatmentAccent)
            case .awaitingPoolCheck:
                workflowStateContent(icon: "list.bullet.clipboard", label: "Awaiting Pool Check", color: PoolColor.checkAccent)
            case .completed:
                completedStateContent(item)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func workflowStateContent(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func completedStateContent(_ item: DashboardWorkflowItem) -> some View {
        let score = item.finalScore ?? 0
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(scoreColor(score).opacity(0.25), lineWidth: 2)
                Circle().fill(scoreColor(score).opacity(0.1))
                Text("\(score)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(score))
            }
            .frame(width: 38, height: 38)

            Text(item.finalGrade ?? viewModel.scoreGrade(score))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(scoreColor(score))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func deleteTestID(_ id: UUID) {
        guard let test = tests.first(where: { $0.id == id }) else { return }
        deleteTest(test)
    }

    private func score(for test: PoolTest) -> Int {
        viewModel.overallScore(
            for: test,
            previousTest: viewModel.previousTest(before: test, in: tests),
            recentHistory: viewModel.recentHistory(before: test, in: tests)
        )
    }

    private func deleteTest(_ test: PoolTest) {
        if editRoute?.test.id == test.id {
            editRoute = nil
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            swipedTestID = nil
        }

        Task {
            do {
                try await viewModel.deletePoolTestAndRefreshHistory(
                    test,
                    allTests: tests,
                    modelContext: modelContext
                )
            } catch {
                viewModel.lastError = error.localizedDescription
            }
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
            let line = "\(greetingText) \n\(category.shortDescription) C\(current)℉ (H\(high)℉)"
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

        // Backfill coordinates from a typed location string if they were never captured (only "Use Current
        // Location" previously set coordinates). This is what lets weather work for manually entered places.
        if viewModel.poolConfig.latitude == nil || viewModel.poolConfig.longitude == nil {
            await viewModel.resolveCoordinatesIfNeeded()
        }

        guard let latitude = viewModel.poolConfig.latitude, let longitude = viewModel.poolConfig.longitude else {
            let hasLocationText = !viewModel.poolConfig.location.trimmingCharacters(in: .whitespaces).isEmpty
            weather.lastErrorMessage = hasLocationText
                ? "Couldn't find “\(viewModel.poolConfig.location)”. Try a nearby city, or tap Use Current Location in Settings."
                : "Add your location in Settings to see local weather."
            print("[Weather] Decision: SKIP — no coordinates (hasLocationText=\(hasLocationText))")
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
        viewModel.scoreGrade(score)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return PoolColor.statusIdeal
        case 60..<75:  return PoolColor.statusSlight
        case 40..<60:  return PoolColor.statusOffRange
        default:       return PoolColor.statusCritical
        }
    }

    private func dashboardReadings(for test: PoolTest) -> [ChemicalReading] {
        let previousTest = viewModel.previousTest(before: test, in: tests)
        let readings = viewModel.readings(for: test, previousTest: previousTest)
        let dashboardOrder = [
            "freeChlorine",
            "pH",
            "totalAlkalinity",
            "cyanuricAcid",
            "calciumHardness",
            "saltLevel"
        ]

        return dashboardOrder.compactMap { key in
            readings.first { $0.key == key }
        }
    }

    private func dashboardAbbreviation(for reading: ChemicalReading) -> String {
        switch reading.key {
        case "pH": return "pH"
        case "freeChlorine": return "FC"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        case "saltLevel": return "Salt"
        default: return String(reading.parameter.prefix(2))
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
        case "pH":                return CGFloat((reading.value - 6.4) / 2.4).clamped(to: 0.05...1)
        case "freeChlorine":      return CGFloat(reading.value / 12).clamped(to: 0.05...1)
        case "totalAlkalinity":   return CGFloat(reading.value / 180).clamped(to: 0.05...1)
        case "calciumHardness":   return CGFloat(reading.value / 600).clamped(to: 0.05...1)
        case "cyanuricAcid":      return CGFloat(reading.value / 120).clamped(to: 0.05...1)
        case "saltLevel":         return CGFloat(reading.value / 5000).clamped(to: 0.05...1)
        default:                  return 0.5
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

    private func nextTestPillIcon(for recommendation: NextTestRecommendation?) -> String {
        // Match the badge icon to the scheduled scope: a flask for the FC & pH quick test,
        // test tubes for the Full Test Panel. Fall back to the calendar clock when the scope
        // is unknown (e.g. next test only defined after a treatment completes).
        switch recommendation?.source {
        case .routineFCAndPH:   return "flask.fill"
        case .routineFullPanel: return "testtube.2"
        default:                return "calendar.badge.clock"
        }
    }

    private func nextTestPillText(for recommendation: NextTestRecommendation?, now: Date = Date()) -> String {
        guard let recommendation, let date = recommendation.recommendedDate else { return "Next test after treatment" }

        // Distinct content for the two routine tests; date/time formatting is unchanged.
        let name: String
        switch recommendation.source {
        case .routineFCAndPH:   name = "Test FC & pH"
        case .routineFullPanel: name = "Full Test Panel"
        default:                name = "Next test"
        }

        if date <= now {
            return "\(name) today"
        }

        return "\(name) \(nextTestPillDateText(date))"
    }

    private func nextTestPillDateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "today at \(timeString(date))"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow at \(timeString(date))"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: date)) at \(timeString(date))"
    }
}

private struct DashboardEditRoute: Identifiable {
    let test: PoolTest
    let startsOnTreatmentPlan: Bool

    var id: UUID { test.id }
}

/// Pure presentation mapping from the canonical Swimability V2 state to the Dashboard hero vocabulary.
/// Kept `internal` (not private) so it is unit-testable as a presentation layer — it contains no
/// chemistry logic. If V2 gains states this must map them intentionally rather than hide distinctions.
enum DashboardSwimReadinessStatus: Equatable {
    case readyNow
    case readyAfterWait
    case notRecommended
    case unknown

    init(swimabilityState state: SwimabilityState) {
        switch state {
        case .readyToSwim:
            self = .readyNow
        case .expectedReadyAfterTreatment, .expectedReadyAroundTime:
            self = .readyAfterWait
        case .doNotSwim, .testBeforeSwimming:
            self = .notRecommended
        case .moreInformationNeeded:
            self = .unknown
        }
    }
}

private enum DashboardWelcomeMessage {
    static let messages = [
        "Welcome to\nPool Side",
        "Keep your pool\nswim-ready",
        "Clear water\nstarts here",
        "Healthy water,\neasier swims",
        "Test today,\nswim easier",
        "Know what\nto do next",
        "Stay ahead of\npool problems",
        "Simple care,\nclear water",
        "Your pool plan\nstarts here",
        "Better logs,\nbetter swims"
    ]

    static func random() -> String {
        messages.randomElement() ?? "Welcome to\nPool Side"
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
                    .contentShape(Rectangle())
            }
            // Plain style so the action reads as a flush full-height panel — the automatic (destructive)
            // button style would draw a tinted rounded-rect behind the icon, leaving a notch over the red.
            .buttonStyle(.plain)

            content
                .overlay(alignment: .trailing) {
                    Color.clear
                        .frame(width: 56)
                        .contentShape(Rectangle())
                        .gesture(horizontalSwipeGesture)
                        .accessibilityHidden(true)
                }
                .offset(x: rowOffset)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOpen)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: dragOffset)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else {
                    dragOffset = 0
                    return
                }

                let baseOffset = isOpen ? -deleteWidth : 0
                dragOffset = min(0, baseOffset + value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else {
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

#Preview("Active + Completed") {
    @Previewable @State var showingAddTest = false
    @Previewable @State var showingSettings = false
    let container = try! ModelContainer(
        for: PoolTest.self, Treatment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let now = Date()

    // Completed (latest, shown in the score card too)
    let done = PoolTest(date: now, pH: 7.5, freeChlorine: 7, totalChlorine: 7,
                        totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
    // Active — Treatment Needed
    let needs = PoolTest(date: now.addingTimeInterval(-3600), pH: 7.9, freeChlorine: 6, totalChlorine: 6,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
    needs.treatments = [Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20,
                                  unit: "fl oz", instructions: "", urgency: .recommended, targetParameter: "pH",
                                  sortOrder: 1, effectDelayHours: 4, poolTest: needs)]
    // Active — Awaiting Pool Check
    let awaiting = PoolTest(date: now.addingTimeInterval(-7200), pH: 7.8, freeChlorine: 6, totalChlorine: 6,
                            totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
    let parent = Treatment(chemicalName: "Muriatic Acid", actionDescription: "Lower pH", amount: 20, unit: "fl oz",
                           instructions: "", urgency: .recommended, isCompleted: true, completedAt: now.addingTimeInterval(-1800),
                           targetParameter: "pH", sortOrder: 1, effectDelayHours: 4, poolTest: awaiting)
    let check = TreatmentWorkflowEngine().makeCheckStep(after: parent, sortOrder: 2)!
    awaiting.treatments = [parent, check]

    for t in [done, needs, awaiting] { container.mainContext.insert(t) }

    ContextualEducationStore.shared.markSeen(ContextualWalkthroughID.dashboard)
    return DashboardView(showingAddTest: $showingAddTest, showingSettings: $showingSettings)
        .environment(PoolViewModel())
        .modelContainer(container)
}

#Preview("Completed only (empty Active)") {
    @Previewable @State var showingAddTest = false
    @Previewable @State var showingSettings = false
    let container = try! ModelContainer(
        for: PoolTest.self, Treatment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let now = Date()
    let done = PoolTest(date: now, pH: 7.5, freeChlorine: 7, totalChlorine: 7,
                        totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
    let older = PoolTest(date: now.addingTimeInterval(-172_800), pH: 7.4, freeChlorine: 6, totalChlorine: 6,
                         totalAlkalinity: 100, calciumHardness: 350, cyanuricAcid: 60)
    for t in [done, older] { container.mainContext.insert(t) }

    ContextualEducationStore.shared.markSeen(ContextualWalkthroughID.dashboard)
    return DashboardView(showingAddTest: $showingAddTest, showingSettings: $showingSettings)
        .environment(PoolViewModel())
        .modelContainer(container)
}
