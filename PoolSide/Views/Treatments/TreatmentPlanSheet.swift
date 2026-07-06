import SwiftUI
import SwiftData
import UserNotifications
import UIKit

/// Full-page sheet shown after saving a test. Displays AI/rule-based treatment recommendations.
/// Each card has a checkbox at top-right; checking a treatment that has a wait interval
/// auto-schedules a local notification and shows a toast.
struct TreatmentPlanSheet: View {

    var test: PoolTest
    var embedsInNavigationStack: Bool = true
    var showsCloseButton: Bool = true
    var showsDoneButton: Bool = true
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    @State private var toastMessage: ToastMessage? = nil
    @State private var showingPermissionAlert: Bool = false
    @State private var openSwipeTreatmentID: UUID? = nil
    @State private var isWhyThisPlanExpanded: Bool = false

    private var allTreatments: [Treatment] {
        test.treatments
            .filter { !shouldSuppressSavedAcidTreatment($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var pendingTreatments: [Treatment] {
        treatmentSteps.filter { !$0.isCompleted && !$0.isSkipped }
    }

    private var treatmentSteps: [Treatment] {
        allTreatments.filter { !$0.isSkipped && !$0.isWatchlistItem }
    }

    private var watchlistItems: [Treatment] {
        allTreatments.filter { !$0.isSkipped && $0.isWatchlistItem }
    }

    private var skippedTreatments: [Treatment] {
        allTreatments.filter { $0.isSkipped && !$0.isWatchlistItem }
    }

    private var recentHistory: [PoolTest] {
        viewModel.recentHistory(before: test, in: tests, limit: 10)
    }

    private var previousTest: PoolTest? {
        viewModel.previousTest(before: test, in: tests)
    }

    private var chemistryReadings: [ChemicalReading] {
        viewModel.readings(for: test, previousTest: previousTest)
    }

    private var currentScore: Int {
        viewModel.overallScore(for: test, previousTest: previousTest, recentHistory: recentHistory)
    }

    private var confidenceInput: RecommendationConfidenceInput {
        ChemistryEngine().recommendationConfidenceInput(for: test, recentHistory: recentHistory)
    }

    private var confidenceLabel: WhyPlanConfidence {
        WhyPlanConfidence(input: confidenceInput, test: test, config: viewModel.poolConfig)
    }

    private func shouldSuppressSavedAcidTreatment(_ treatment: Treatment) -> Bool {
        test.pH <= 7.4
            && !test.visualIndicators.contains(VisualIndicator.scaling.rawValue)
            && treatment.isAcidTreatment
    }

    var body: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack {
                    content
                }
            } else {
                content
            }
        }
        .toast($toastMessage)
        .alert("Allow Notifications", isPresented: $showingPermissionAlert) {
            Button("Allow") {
                Task {
                    let granted = await NotificationService.shared.requestPermission()
                    if !granted {
                        toastMessage = ToastMessage(
                            text: "Enable notifications in Settings for step reminders",
                            icon: "bell.slash",
                            color: PoolColor.secondaryText
                        )
                    }
                }
            }
            Button("Not Now", role: .cancel) { }
        } message: {
            Text("Pool Side can remind you when it's time for your next treatment step.")
        }
    }

    private var content: some View {
        ZStack(alignment: .bottom) {
            PoolColor.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroBanner

                    VStack(alignment: .leading, spacing: 16) {
                        if allTreatments.isEmpty {
                            emptyState
                        } else {
                            recommendationSectionCard(title: "Treatment Steps", count: treatmentSteps.count) {
                                if treatmentSteps.isEmpty {
                                    noTreatmentStepsState
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(Array(treatmentSteps.enumerated()), id: \.element.id) { index, treatment in
                                            treatmentStepCard(treatment, showsDivider: index < treatmentSteps.count - 1)
                                        }
                                    }
                                }
                            }

                            if !watchlistItems.isEmpty {
                                recommendationSectionCard(title: "Watchlist", count: watchlistItems.count) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(watchlistItems.enumerated()), id: \.element.id) { index, treatment in
                                            watchlistCard(treatment, showsDivider: index < watchlistItems.count - 1)
                                        }
                                    }
                                }
                            }

                            if !skippedTreatments.isEmpty {
                                recommendationSectionCard(title: "Skipped", count: skippedTreatments.count) {
                                    VStack(spacing: 0) {
                                        ForEach(skippedTreatments, id: \.id) { treatment in
                                            skippedTreatmentCard(treatment)
                                        }
                                    }
                                }
                            }
                        }

                        whyThisPlanCard

                        validationPromptCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, -20)
                    .padding(.bottom, showsDoneButton ? 100 : 24)
                }
            }
            .ignoresSafeArea(edges: .top)

            if showsDoneButton {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .background(
                            Rectangle()
                                .fill(Color.white.opacity(0.95))
                                .ignoresSafeArea(edges: .bottom)
                        )
                }
            }
        }
        .navigationTitle("Treatment Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
        .onAppear {
            isWhyThisPlanExpanded = shouldExpandWhyThisPlanByDefault
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let headerHeight: CGFloat = 250
        let topPadding: CGFloat = 16
        let contentBottomPadding: CGFloat = 56

        return GeometryReader { proxy in
            ZStack {
                Image("Pool Water BG")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: headerHeight + 160)
                    .offset(y: -80)
                    .clipped()

                PoolColor.poolTeal.opacity(0.78)
            }
            .frame(width: proxy.size.width, height: headerHeight)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("We recommend")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(allTreatments.count) treatment\(allTreatments.count == 1 ? "" : "s")")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if pendingTreatments.isEmpty && !allTreatments.isEmpty {
                        Label("All done!", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.top, 4)
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 210)
                .padding(.bottom, contentBottomPadding)
            }
            .overlay(alignment: .bottomTrailing) {
                Image("Treatment Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .padding(.trailing, 20)
                    .padding(.bottom, -40)
            }
        }
        .padding(.top, topPadding)
        .frame(height: headerHeight + topPadding)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(PoolColor.primaryText)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(PoolColor.divider, in: Capsule())
        }
    }

    private func recommendationSectionCard<Content: View>(
        title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title, count: count)
            content()
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private var noTreatmentStepsState: some View {
        Text("Nothing needs to be added right now.")
            .font(.subheadline)
            .foregroundStyle(PoolColor.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func treatmentStepCard(_ treatment: Treatment, showsDivider: Bool = true) -> some View {
        TreatmentCardView(
            treatment: treatment,
            allowsActions: true,
            presentation: .row,
            showsDivider: showsDivider,
            onComplete: { t in await completeTreatment(t) },
            onMarkIncomplete: { t in await markTreatmentIncomplete(t) },
            onSkip: { t in await skipTreatment(t) },
            onRestore: { t in await restoreTreatment(t) },
            openSwipeTreatmentID: $openSwipeTreatmentID
        )
    }

    private func watchlistCard(_ treatment: Treatment, showsDivider: Bool = true) -> some View {
        TreatmentCardView(
            treatment: treatment,
            allowsActions: false,
            presentation: .row,
            showsDivider: showsDivider,
            onComplete: { _ in },
            onMarkIncomplete: { _ in },
            onSkip: { _ in },
            onRestore: { _ in },
            openSwipeTreatmentID: $openSwipeTreatmentID
        )
    }

    private func skippedTreatmentCard(_ treatment: Treatment) -> some View {
        TreatmentCardView(
            treatment: treatment,
            allowsActions: true,
            presentation: .row,
            onComplete: { _ in },
            onMarkIncomplete: { t in await markTreatmentIncomplete(t) },
            onSkip: { _ in },
            onRestore: { t in await restoreTreatment(t) },
            openSwipeTreatmentID: $openSwipeTreatmentID
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(PoolColor.statusIdeal)
            Text("Your pool is in great shape!")
                .font(.headline)
                .foregroundStyle(PoolColor.primaryText)
            Text("No treatments needed right now. Keep testing regularly to stay on top of your water chemistry.")
                .font(.subheadline)
                .foregroundStyle(PoolColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Why This Plan

    private var shouldExpandWhyThisPlanByDefault: Bool {
        allTreatments.contains { $0.urgency == .immediate }
            || confidenceLabel == .low
            || currentScore < 60
            || chemistryReadings.contains { $0.status == .critical }
    }

    private var whyThisPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isWhyThisPlanExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Why This Plan")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Image(systemName: isWhyThisPlanExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolColor.poolTeal)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isWhyThisPlanExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    whyPlanSection(title: "Summary", lines: whyPlanSummary)
                    confidenceSection
                    whyPlanSection(title: "Key Factors", lines: keyFactors)
                    whyPlanSection(title: "Expected Outcome", lines: expectedOutcomes)
                    whyPlanSection(title: "Next Test Timing", lines: [nextTestTiming])

                    if confidenceLabel != .high {
                        Text("Logging pool conditions and visual indicators helps Pool Side explain what changed and tune future recommendations.")
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PoolColor.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func whyPlanSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Text("• \(line)")
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var confidenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Recommendation Confidence")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)
                Text(confidenceLabel.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(confidenceLabel.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confidenceLabel.color.opacity(0.12), in: Capsule())
            }

            if !confidenceBasedOn.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Based on:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                    ForEach(confidenceBasedOn, id: \.self) { item in
                        Text("✓ \(item)")
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                    }
                }
            }

            if !confidenceMissingOrLimited.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Missing or limited:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                    ForEach(confidenceMissingOrLimited, id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                    }
                }
            }
        }
    }

    private var validationPromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("External Review", systemImage: "square.and.arrow.up")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.primaryText)

            Text("Share the current pool profile, test data, treatment history, and proposed plan for an outside review.")
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)

            HStack(spacing: 12) {
                ShareLink(item: validationPrompt) {
                    Label("Validate Plan", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    UIPasteboard.general.string = validationPrompt
                    toastMessage = ToastMessage(
                        text: "Validation prompt copied",
                        icon: "doc.on.doc",
                        color: PoolColor.poolTeal
                    )
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.headline)
                        .foregroundStyle(PoolColor.poolTeal)
                        .frame(width: 44, height: 44)
                        .background(PoolColor.poolTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Copy Validation Prompt")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PoolColor.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var whyPlanSummary: [String] {
        var lines: [String] = []
        let engine = ChemistryEngine()
        let fcRange = engine.freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)

        if treatmentSteps.isEmpty {
            lines.append("Based on the data logged, your pool does not need an added treatment step right now.")
        } else if test.freeChlorine < fcRange.lowerBound {
            lines.append("Your pool is mostly stable, but free chlorine is below the target for your current CYA.")
        } else {
            lines.append("Based on the data logged, this plan prioritizes the items most likely to affect pool safety and comfort.")
        }

        if confidenceInput.chlorineDemandScore >= 3 {
            lines.append("Recent logged pool conditions increased expected chlorine demand.")
        } else if !confidenceInput.hasPoolConditions {
            lines.append("Pool conditions were not logged, so this plan is based mostly on chemistry and history.")
        }

        if test.totalAlkalinity > 140 && (7.2...7.8).contains(test.pH) {
            lines.append("Your pH is safe, so elevated alkalinity is being monitored instead of treated.")
        }

        return Array(lines.prefix(3))
    }

    private var confidenceBasedOn: [String] {
        var items = ["Chemistry readings"]
        if confidenceInput.hasPoolConditions { items.append("Pool conditions") }
        if confidenceInput.hasVisualIndicators { items.append("Visual indicators") }
        if confidenceInput.hasRecentHistory { items.append("Recent test history") }
        if confidenceInput.hasCompletedTreatmentHistory { items.append("Completed treatment history") }
        return items
    }

    private var confidenceMissingOrLimited: [String] {
        var items: [String] = []
        if !confidenceInput.hasPoolConditions { items.append("Pool conditions not logged") }
        if !confidenceInput.hasVisualIndicators { items.append("Visual indicators not logged") }
        if !confidenceInput.hasRecentHistory { items.append("Limited history") }
        if test.testMethod == .testStrips { items.append("Test-strip readings have wider uncertainty") }
        if test.totalChlorine + 0.3 < test.freeChlorine { items.append("Chlorine readings appear internally inconsistent") }
        return items
    }

    private var keyFactors: [String] {
        var factors: [String] = []
        let engine = ChemistryEngine()
        let fcRange = engine.freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)

        if test.freeChlorine < fcRange.lowerBound {
            factors.append("FC is below the CYA-adjusted target.")
        }
        if test.cyanuricAcid > 50 && test.cyanuricAcid < 90 {
            factors.append("CYA is elevated but manageable, so FC must run higher.")
        }
        if test.totalAlkalinity > 140 && (7.2...7.8).contains(test.pH) {
            factors.append("pH is safe; acid is not currently needed.")
        }
        if confidenceInput.chlorineDemandScore >= 3 {
            factors.append("Logged pool conditions increased expected chlorine demand.")
        }
        if test.resolvedPoolConditions.hasOrganicLoadReduction {
            factors.append("Skimming, cleaning, or brushing may have reduced some organic load.")
        }
        if confidenceInput.waterChangeScore >= 2 {
            factors.append("Recent water addition or rain may have diluted stabilizer, hardness, alkalinity, salt, or chlorine.")
        }
        if test.visualIndicators.contains(VisualIndicator.crystalClear.rawValue) && test.combinedChlorine <= 0.5 {
            factors.append("Water is clear and CC is low, so this does not look like an algae recovery case.")
        } else if !confidenceInput.hasVisualIndicators {
            factors.append("Visual condition was not logged.")
        }

        if factors.isEmpty {
            factors.append("The app is watching trends and current chemistry for changes that need action.")
        }

        return Array(factors.prefix(6))
    }

    private var expectedOutcomes: [String] {
        var outcomes: [String] = []

        if let chlorine = treatmentSteps.first(where: { $0.targetParameter == "freeChlorine" }) {
            outcomes.append("Adding \(chlorine.amount.formattedTreatmentAmount) \(chlorine.unit) of \(chlorine.chemicalName) should raise FC toward the normal target range.")
        }
        if !treatmentSteps.contains(where: { $0.isAcidTreatment }) && (7.2...7.8).contains(test.pH) {
            outcomes.append("No acid is recommended because pH is currently safe.")
        }
        if !watchlistItems.isEmpty {
            outcomes.append("The watchlist items do not need check-off actions; they identify conditions to monitor on the next test.")
        }
        if outcomes.isEmpty {
            outcomes.append("Continue circulation and normal testing so Pool Side can confirm the pool remains stable.")
        }

        outcomes.append("Retest after the recommended wait time so the app can confirm the treatment worked.")
        return Array(outcomes.prefix(4))
    }

    private var nextTestTiming: String {
        if let chlorine = treatmentSteps.first(where: { $0.targetParameter == "freeChlorine" && $0.urgency == .immediate }) {
            return "Retest FC and CC after \(chlorineRetestLabel(for: chlorine)) before adding more."
        }
        if let pH = treatmentSteps.first(where: { $0.targetParameter == "pH" }) {
            return pH.urgency == .immediate ? "Retest pH after 4 hours." : "Retest pH after circulation, about 4 hours."
        }
        if treatmentSteps.contains(where: { $0.targetParameter == "cyanuricAcid" }) {
            return "Retest CYA after 48–72 hours."
        }
        if confidenceInput.waterChangeScore >= 2 {
            return "Retest after circulation or tomorrow."
        }
        if confidenceInput.chlorineDemandScore >= 3 {
            return "Retest tomorrow."
        }
        if treatmentSteps.isEmpty {
            return "Retest in 1–3 days."
        }
        return "Retest in 24 hours."
    }

    private func chlorineRetestLabel(for treatment: Treatment) -> String {
        if treatment.chemicalName.contains("Granules") || treatment.chemicalName.contains("Dichlor") {
            return "4 hours"
        }
        if treatment.chemicalName.contains("Tablets") {
            return "24 hours"
        }
        return "60 minutes"
    }

    private var validationPrompt: String {
        let config = viewModel.poolConfig
        let previousLogs = Array(recentHistory.prefix(5))

        return """
        POOL SIDE EXTERNAL REVIEW EXPORT

        1. Pool Configuration
        - Name: \(config.name)
        - Pool volume: \(Int(config.volumeGallons).formatted()) gallons
        - Pool type / surface type: \(config.poolType.displayName) / \(config.surfaceType.displayName)
        - Saltwater / salt chlorinator: \(config.isSaltwater ? "Yes" : "No")
        - Has cover: \(config.hasCover ? "Yes" : "No")
        - Pets regularly swim: \(config.petsRegularlySwim ? "Yes" : "No")
        - Robotic cleaner: \(config.usesRoboticCleaner ? "Yes" : "No")
        - Sanitizer preference: \(config.chlorinePreference.displayName)
        - Default test method: \(config.testMethod.displayName)
        - Location: \(config.location.isEmpty ? "Not provided" : config.location)

        2. Current Test Log
        - Timestamp/date: \(Self.promptDateFormatter.string(from: test.date))
        - FC: \(formatPPM(test.freeChlorine))
        - CC: \(formatPPM(test.combinedChlorine))
        - TC: \(formatPPM(test.totalChlorine))
        - pH: \(formatNumber(test.pH))
        - TA: \(formatPPM(test.totalAlkalinity))
        - CH/TH: \(formatPPM(test.calciumHardness))
        - CYA: \(formatPPM(test.cyanuricAcid))
        - Salt: \(saltExportLine(for: test, config: config))
        - Water temperature: \(test.temperatureFahrenheit.map { "\(Int($0.rounded()))°F" } ?? "not available")
        - Test method used: \(testMethodDescription(for: test))
        - Notes: \(test.notes.isEmpty ? "None" : test.notes)

        3. Pool Conditions Since Last Test Log
        \(poolConditionsExport(for: test.resolvedPoolConditions, config: config))

        4. Visual Indicators
        \(visualIndicatorsExport(for: test))

        5. Recent History Used
        \(previousLogs.isEmpty ? "No prior test logs available." : previousLogs.map(recentHistoryExport).joined(separator: "\n\n"))

        6. Derived Engine Signals
        - Chlorine demand score: \(confidenceInput.chlorineDemandScore)
        - Water change / dilution score: \(confidenceInput.waterChangeScore)
        - Estimated FC loss rate: \(estimatedFCLossRateText())
        - Expected FC loss: Not available as a separate engine estimate.
        - Actual FC loss: \(actualFCLossText())
        - Recommendation confidence label: \(confidenceLabel.rawValue)
        - Confidence inputs used: \(confidenceBasedOn.isEmpty ? "None" : confidenceBasedOn.joined(separator: ", "))
        - Missing/limited data: \(confidenceMissingOrLimited.isEmpty ? "None" : confidenceMissingOrLimited.joined(separator: ", "))

        7. Current Pool Score
        - Score: \(currentScore)
        - Label: \(scoreLabel(currentScore))
        - Main score drivers: \(scoreDriverSummary())

        8. Treatment Steps
        \(treatmentSteps.isEmpty ? "No actionable treatment steps." : treatmentSteps.map(treatmentStepExport).joined(separator: "\n\n"))

        9. Watchlist
        \(watchlistItems.isEmpty ? "No watchlist items." : watchlistItems.map(watchlistExport).joined(separator: "\n\n"))

        10. Why This Plan
        Summary:
        \(bulletedLines(whyPlanSummary))

        Confidence:
        - \(confidenceLabel.rawValue)

        Key factors:
        \(bulletedLines(keyFactors))

        Expected outcome:
        \(bulletedLines(expectedOutcomes))

        Next test timing:
        - \(nextTestTiming)

        11. Suppressed or Avoided Recommendations
        \(suppressedRecommendationsExport())

        12. User Prompt
        Please review this pool test log and treatment plan. Tell me whether the recommendation is chemically sound, whether anything is missing or over-aggressive, and what I should do next.
        """
    }

    private func treatmentStepExport(_ treatment: Treatment) -> String {
        """
        - Title: \(treatment.chemicalName)
          Urgency: \(treatment.urgency.displayName)
          Amount: \(formattedTreatmentAmount(treatment))
          Product: \(treatment.chemicalName)
          Target parameter: \(treatment.targetParameter.isEmpty ? "not specified" : treatment.targetParameter)
          Target value: \(targetValueText(for: treatment))
          Why recommended: \(treatment.actionDescription)
          Expected effect: \(expectedEffectText(for: treatment))
          Retest/wait timing: \(waitTimingText(for: treatment))
          Status: \(treatmentStatusText(treatment))
        """
    }

    private func watchlistExport(_ treatment: Treatment) -> String {
        """
        - Title: \(treatment.chemicalName)
          Reason: \(treatment.actionDescription)
          Monitoring: \(watchlistMonitoringText(for: treatment))
          Source: \(watchlistSourceText(for: treatment))
        """
    }

    private func recentHistoryExport(_ test: PoolTest) -> String {
        let treatments = test.treatments.filter { $0.isCompleted || $0.isSkipped }
        let treatmentSummary = treatments.isEmpty
            ? "none"
            : treatments.map { "\($0.chemicalName) (\($0.isCompleted ? "completed" : "skipped"))" }.joined(separator: ", ")

        return """
        - Date/time: \(Self.promptDateFormatter.string(from: test.date))
          FC: \(formatPPM(test.freeChlorine)); CC: \(formatPPM(test.combinedChlorine)); pH: \(formatNumber(test.pH)); TA: \(formatPPM(test.totalAlkalinity)); CH: \(formatPPM(test.calciumHardness)); CYA: \(formatPPM(test.cyanuricAcid))
          Pool score: \(viewModel.overallScore(for: test, previousTest: viewModel.previousTest(before: test, in: tests), recentHistory: viewModel.recentHistory(before: test, in: tests, limit: 10)))
          Key pool conditions: \(shortConditionsSummary(for: test.resolvedPoolConditions))
          Completed/skipped treatments: \(treatmentSummary)
        """
    }

    private func poolConditionsExport(for conditions: PoolConditions, config: PoolConfiguration) -> String {
        var lines: [String] = [
            "- Swimming: \(conditions.swimmingLoad.exportText)",
            "- Rain: \(conditions.rainLoad.exportText)",
            "- Organic debris: \(conditions.organicDebrisLoad.exportText)",
            "- Water added: \(conditions.waterAdded.exportText)"
        ]

        if config.petsRegularlySwim {
            lines.insert("- Pet swimming: \(conditions.petSwimmingLoad.exportText)", at: 1)
        }

        if config.hasCover {
            let insertIndex = config.petsRegularlySwim ? 3 : 2
            lines.insert("- Pool cover open time: \(conditions.coverOpenTime.exportText)", at: insertIndex)
        }

        if conditions.organicDebrisLoad != .unknown && conditions.organicDebrisLoad != .none {
            lines.append("- Skimmed: \(conditions.skimmedDebris.exportText)")
        }

        let cleaningLabel = config.usesRoboticCleaner ? "Robot cleaned" : "Vacuumed"
        lines.append("- \(cleaningLabel): \(conditions.cleaningActivity.exportText)")
        lines.append("- Pool brushed: \(conditions.poolBrushed.exportText)")

        return lines.joined(separator: "\n")
    }

    private func visualIndicatorsExport(for test: PoolTest) -> String {
        let indicators = test.visualIndicators.compactMap(VisualIndicator.init(rawValue:))
        guard !indicators.isEmpty else { return "not logged" }
        return indicators.map { "- \($0.rawValue)" }.joined(separator: "\n")
    }

    private func suppressedRecommendationsExport() -> String {
        var lines: [String] = []

        if !treatmentSteps.contains(where: { $0.isAcidTreatment }) && (7.2...7.8).contains(test.pH) {
            lines.append("- Acid/pH decreaser suppressed because pH is safe.")
        }
        if confidenceInput.waterChangeScore >= 2 {
            lines.append("- Large CYA/CH/TA corrections avoided because recent water change or rain may explain dilution; retest is preferred unless values are unsafe.")
        }
        if !treatmentSteps.contains(where: { $0.chemicalName.localizedCaseInsensitiveContains("shock") })
            && test.combinedChlorine <= 0.5
            && test.visualIndicators.contains(VisualIndicator.crystalClear.rawValue) {
            lines.append("- Shock avoided because water is clear and CC is low.")
        }
        if test.cyanuricAcid >= 50 {
            lines.append("- Stabilized chlorine avoided or deprioritized because CYA is elevated.")
        }
        if allTreatments.contains(where: { $0.doNotRepeatBefore != nil }) {
            lines.append("- Repeated treatment may be suppressed during an active wait/retest window.")
        }

        return lines.isEmpty ? "No explicit suppressed recommendations were available in the saved plan." : lines.joined(separator: "\n")
    }

    private func scoreDriverSummary() -> String {
        var drivers: [String] = []
        let engine = ChemistryEngine()
        let fcRange = engine.freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)

        if test.freeChlorine < fcRange.lowerBound {
            drivers.append("FC below CYA-adjusted target")
        }
        if !(7.2...7.8).contains(test.pH) {
            drivers.append("pH outside safe range")
        }
        if test.combinedChlorine > 0.5 {
            drivers.append("CC elevated")
        }
        if test.totalAlkalinity > 140 {
            drivers.append("TA elevated")
        }
        if test.cyanuricAcid > 50 {
            drivers.append("CYA elevated")
        }
        if confidenceInput.chlorineDemandScore >= 3 {
            drivers.append("pool conditions increased chlorine demand")
        }
        if confidenceInput.waterChangeScore >= 2 {
            drivers.append("possible dilution")
        }

        return drivers.isEmpty ? "No major score drivers; pool appears stable." : drivers.joined(separator: ", ")
    }

    private func estimatedFCLossRateText() -> String {
        guard let previousTest, previousTest.freeChlorine > test.freeChlorine else {
            return "not available"
        }

        let days = max(test.date.timeIntervalSince(previousTest.date) / 86_400, 0.1)
        let loss = (previousTest.freeChlorine - test.freeChlorine) / days
        return "\(formatNumber(loss)) ppm/day based on previous logged test"
    }

    private func actualFCLossText() -> String {
        guard let previousTest else { return "not available" }
        let delta = test.freeChlorine - previousTest.freeChlorine
        if delta < 0 {
            return "\(formatNumber(abs(delta))) ppm lower than previous logged test"
        }
        if delta > 0 {
            return "\(formatNumber(delta)) ppm higher than previous logged test"
        }
        return "no FC change from previous logged test"
    }

    private func testMethodDescription(for test: PoolTest) -> String {
        if let brand = test.liquidDropKitBrand, test.testMethod.usesBrandPicker {
            return "\(test.testMethod.displayName) / \(brand.displayName)"
        }
        return test.testMethod.displayName
    }

    private func saltExportLine(for test: PoolTest, config: PoolConfiguration) -> String {
        guard config.isSaltwater || test.saltLevel != nil else { return "not relevant / not logged" }
        return test.saltLevel.map(formatPPM) ?? "not logged"
    }

    private func shortConditionsSummary(for conditions: PoolConditions) -> String {
        guard conditions.hasAnyKnownCondition else { return "not logged" }
        return "demand \(conditions.chlorineDemandContribution), dilution \(conditions.waterChangeContribution)"
    }

    private func formattedTreatmentAmount(_ treatment: Treatment) -> String {
        guard treatment.amount > 0 else { return "not applicable" }
        return treatment.unit.isEmpty
            ? treatment.amount.formattedTreatmentAmount
            : "\(treatment.amount.formattedTreatmentAmount) \(treatment.unit)"
    }

    private func targetValueText(for treatment: Treatment) -> String {
        guard !treatment.expectedEffectParameter.isEmpty else { return "not specified" }
        let sign = treatment.expectedDelta > 0 ? "+" : ""
        return "\(treatment.expectedEffectParameter) \(sign)\(formatNumber(treatment.expectedDelta))"
    }

    private func expectedEffectText(for treatment: Treatment) -> String {
        guard !treatment.expectedEffectParameter.isEmpty else { return "not specified" }
        let sign = treatment.expectedDelta > 0 ? "+" : ""
        let delay = treatment.effectDelayHours > 0 ? " after about \(treatment.effectDelayHours)h" : ""
        return "\(treatment.expectedEffectParameter) \(sign)\(formatNumber(treatment.expectedDelta))\(delay)"
    }

    private func waitTimingText(for treatment: Treatment) -> String {
        if treatment.minutesBeforeNext > 0 {
            return NotificationService.waitLabel(minutes: treatment.minutesBeforeNext)
        }
        return treatment.targetParameter == "pH" ? "Retest pH after circulation." : "Retest based on plan timing."
    }

    private func treatmentStatusText(_ treatment: Treatment) -> String {
        if treatment.isCompleted {
            let completed = treatment.completedAt.map { " at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
            return "completed\(completed)"
        }
        if treatment.isSkipped {
            let skipped = treatment.skippedAt.map { " at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
            return "skipped\(skipped)"
        }
        return "pending"
    }

    private func watchlistMonitoringText(for treatment: Treatment) -> String {
        if treatment.targetParameter == "totalAlkalinity" {
            return "pH drift, scaling signs, and whether TA remains elevated on future tests"
        }
        if treatment.targetParameter == "cyanuricAcid" {
            return "CYA trend and whether FC is being maintained at the higher CYA-adjusted target"
        }
        if treatment.targetParameter == "freeChlorine" {
            return "FC holding behavior and signs of increased chlorine demand"
        }
        return treatment.instructions.isEmpty ? "future test results and logged pool conditions" : treatment.instructions
    }

    private func watchlistSourceText(for treatment: Treatment) -> String {
        var sources: [String] = []
        if !treatment.targetParameter.isEmpty { sources.append("chemistry") }
        if confidenceInput.hasRecentHistory { sources.append("history") }
        if confidenceInput.chlorineDemandScore >= 3 || confidenceInput.waterChangeScore >= 2 { sources.append("pool conditions") }
        if confidenceInput.hasVisualIndicators { sources.append("visual indicators") }
        return sources.isEmpty ? "current test" : sources.joined(separator: ", ")
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 85...100: return "Stable"
        case 70..<85: return "Good / watch"
        case 60..<70: return "Needs attention"
        default: return "Problem recovery"
        }
    }

    private func bulletedLines(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private func formatPPM(_ value: Double) -> String {
        "\(formatNumber(value)) ppm"
    }

    private func formatNumber(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func positiveIndicatorList(for test: PoolTest) -> String {
        let names = test.visualIndicators
            .compactMap(VisualIndicator.init(rawValue:))
            .filter { $0.isPositive }
            .map(\.rawValue)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func issueIndicatorList(for test: PoolTest) -> String {
        let names = test.visualIndicators
            .compactMap(VisualIndicator.init(rawValue:))
            .filter { !$0.isPositive }
            .map(\.rawValue)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private static let promptDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Complete Treatment

    @MainActor
    private func completeTreatment(_ treatment: Treatment) async {
        let minutesToWait = treatment.minutesBeforeNext

        // Mark complete
        viewModel.completeTreatment(treatment)

        // Find next pending step
        let nextPending = allTreatments
            .filter { !$0.isCompleted && !$0.isSkipped }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first

        var scheduledReminderLabel: String?

        if minutesToWait > 0, let next = nextPending {
            var canScheduleReminder = NotificationService.shared.isAuthorized
            if !canScheduleReminder {
                canScheduleReminder = await NotificationService.shared.requestPermission()
            }

            if canScheduleReminder {
                let identifier = await NotificationService.shared.scheduleNextStepReminder(
                    nextTreatmentName: next.chemicalName,
                    afterMinutes: minutesToWait
                )
                treatment.reminderNotificationIdentifier = identifier
                scheduledReminderLabel = NotificationService.waitLabel(minutes: minutesToWait)
            }
        }

        do {
            try modelContext.save()
            if let scheduledReminderLabel {
                toastMessage = ToastMessage.notificationSet(label: scheduledReminderLabel)
            } else if minutesToWait > 0, nextPending != nil {
                toastMessage = ToastMessage(
                    text: "Reminder not set. Notifications are off.",
                    icon: "bell.slash",
                    color: PoolColor.secondaryText
                )
            }
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func markTreatmentIncomplete(_ treatment: Treatment) async {
        let reminderCanceled = treatment.reminderNotificationIdentifier != nil
        viewModel.markTreatmentIncomplete(treatment)
        do {
            try modelContext.save()
            if reminderCanceled {
                toastMessage = ToastMessage.treatmentIncomplete(reminderCanceled: true)
            }
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func skipTreatment(_ treatment: Treatment) async {
        viewModel.skipTreatment(treatment)
        do {
            try modelContext.save()
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func restoreTreatment(_ treatment: Treatment) async {
        viewModel.restoreTreatment(treatment)
        do {
            try modelContext.save()
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }
}

private enum WhyPlanConfidence: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    init(input: RecommendationConfidenceInput, test: PoolTest, config: PoolConfiguration) {
        var score = 0

        if input.hasChemistryData { score += 2 }
        if input.hasPoolConditions { score += 1 }
        if input.hasVisualIndicators { score += 1 }
        if input.hasRecentHistory { score += 1 }
        if input.hasCompletedTreatmentHistory { score += 1 }
        if test.testMethod != .testStrips { score += 1 }
        if test.totalChlorine + 0.3 < test.freeChlorine { score -= 2 }

        if score >= 6 {
            self = .high
        } else if score >= 3 {
            self = .medium
        } else {
            self = .low
        }
    }

    var color: Color {
        switch self {
        case .high:
            return PoolColor.statusIdeal
        case .medium:
            return PoolColor.statusSlight
        case .low:
            return PoolColor.statusOffRange
        }
    }
}

private extension SwimmingLoad {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .none: return "none"
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        }
    }
}

private extension PetSwimmingLoad {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .none: return "none"
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        }
    }
}

private extension RainLoad {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .none: return "none"
        case .light: return "light"
        case .steady: return "steady"
        case .heavy: return "heavy"
        }
    }
}

private extension CoverOpenTime {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .mostlyOpen: return "mostly open"
        case .sixToEighteenHours: return "6–18 hours open"
        case .twoToSixHours: return "2–6 hours open"
        case .lessThanTwoHours: return "less than 2 hours open"
        }
    }
}

private extension OrganicDebrisLoad {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .none: return "none"
        case .low: return "low"
        case .moderate: return "moderate"
        case .high: return "high"
        }
    }
}

private extension SkimmedDebris {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .no: return "no"
        case .yes: return "yes"
        }
    }
}

private extension WaterAdded {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .none: return "none"
        case .lessThanOneInch: return "less than 1 inch"
        case .oneToTwoInches: return "1–2 inches"
        case .moreThanTwoInches: return "more than 2 inches"
        }
    }
}

private extension CleaningActivity {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .no: return "no"
        case .oneCycle: return "one robot cycle"
        case .multipleCycles: return "multiple robot cycles"
        case .brushedAndMultipleCycles: return "brushed + multiple robot cycles"
        case .spotVacuumed: return "spot vacuumed"
        case .entirePool: return "entire pool vacuumed"
        case .brushedAndEntirePool: return "brushed + entire pool vacuumed"
        }
    }
}

private extension PoolBrushed {
    var exportText: String {
        switch self {
        case .unknown: return "unknown / not logged"
        case .no: return "no"
        case .yes: return "yes"
        }
    }
}

private extension PoolConditions {
    var hasOrganicLoadReduction: Bool {
        skimmedDebris == .yes
            || cleaningActivity.organicLoadReductionScore > 0
            || poolBrushed.organicLoadReductionScore > 0
    }
}

// MARK: - Preview

#Preview {
    let test = PoolTest(
        pH: 7.8,
        freeChlorine: 0.4,
        totalChlorine: 0.4,
        totalAlkalinity: 75,
        calciumHardness: 280,
        cyanuricAcid: 25,
        notes: "Sunny day, light bather load.",
        aiAssessment: "Free chlorine is low and pH is trending high — add chlorine shock and acid in sequence."
    )
    return TreatmentPlanSheet(test: test)
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
