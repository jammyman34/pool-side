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
    @State private var isWatchlistExpanded: Bool = false
    @State private var showingDeveloperTools: Bool = false
    @State private var isRecalculatingRecommendations: Bool = false
    @State private var selectedDeveloperToolMode: TreatmentPlanDeveloperToolMode = .recalculate
    @State private var selectedJumpAheadOffset: TreatmentPlanDeveloperJumpAheadOffset = .oneHour
    @State private var activeEducationTipIDs: [ContextualTipID] = []
    @State private var activeEducationTipIndex: Int = 0
    @State private var focusedCheckStep: Treatment? = nil

    private var allTreatments: [Treatment] {
        test.treatments
            .filter { !shouldSuppressSavedAcidTreatment($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var pendingTreatments: [Treatment] {
        workflowSteps.filter { !$0.isCompleted && !$0.isSkipped }
    }

    private var workflowEngine: TreatmentWorkflowEngine { TreatmentWorkflowEngine() }

    private var workflowSteps: [Treatment] {
        workflowEngine.workflowSteps(from: allTreatments)
    }

    private var treatmentSteps: [Treatment] {
        workflowSteps
    }

    /// Actual chemical/action treatment steps only — focused Checks excluded. "Why This Plan" narrative
    /// and any treatment-summary reasoning must use this, never `treatmentSteps` (which includes Checks).
    private var treatmentActions: [Treatment] {
        workflowSteps.filter { !$0.isFocusedCheckStep }
    }

    private var focusedChecks: [Treatment] {
        workflowSteps.filter { $0.isFocusedCheckStep }
    }

    private var watchlistItems: [Treatment] {
        // Watchlist is contextual: drop guidance already handled by an active treatment on the same
        // parameter, de-dupe by title, and order by importance so already-satisfied "continue" notes sink
        // to the bottom rather than appearing prominently every test.
        let activeParameters = Set(
            allTreatments
                .filter { !$0.isWatchlistItem && !$0.isFocusedCheckStep && !$0.isCompleted && !$0.isSkipped && $0.amount > 0 }
                .map(\.targetParameter)
        )
        var seenTitles = Set<String>()
        let items = allTreatments
            .filter { !$0.isSkipped && $0.isWatchlistItem }
            .filter { !activeParameters.contains($0.targetParameter) }
            .filter { seenTitles.insert($0.chemicalName).inserted }

        return items.enumerated()
            .sorted { lhs, rhs in
                let lp = Self.watchlistPriority(lhs.element)
                let rp = Self.watchlistPriority(rhs.element)
                return lp == rp ? lhs.offset < rhs.offset : lp < rp
            }
            .map(\.element)
    }

    /// Lower sorts higher. Already-satisfied "continue as you are" notes are the least actionable, so they
    /// sink to the bottom of the Watchlist.
    private static func watchlistPriority(_ treatment: Treatment) -> Int {
        treatment.chemicalName.localizedCaseInsensitiveContains("continue") ? 100 : 0
    }

    private var skippedTreatments: [Treatment] {
        workflowSteps.filter { $0.isSkipped }
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

    private var nextTestSchedule: NextTestSchedule? {
        viewModel.nextTestSchedule(for: test, in: tests)
    }

    private var activeTreatmentEducationTipID: ContextualTipID? {
        guard activeEducationTipIDs.indices.contains(activeEducationTipIndex) else { return nil }
        return activeEducationTipIDs[activeEducationTipIndex]
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
        .sheet(isPresented: $showingDeveloperTools) {
            TreatmentPlanDeveloperToolsSheet(
                selectedMode: $selectedDeveloperToolMode,
                selectedJumpAheadOffset: $selectedJumpAheadOffset,
                isRecalculating: isRecalculatingRecommendations,
                onRecalculate: {
                    showingDeveloperTools = false
                    recalculateRecommendations()
                },
                onJumpAhead: { offset in
                    runJumpAheadEvaluation(offset)
                    showingDeveloperTools = false
                }
            )
        }
        .sheet(item: $focusedCheckStep) { checkStep in
            FocusedCheckEntrySheet(
                checkStep: checkStep,
                sourceTest: test,
                onSave: { values in
                    try await saveFocusedCheck(checkStep, values: values)
                }
            )
        }
        .overlay {
            if let tipID = activeTreatmentEducationTipID {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        ContextualEducationTipView(
                            content: ContextualTipContent.content(for: tipID),
                            showsCloseButton: true,
                            primaryActionTitle: activeEducationTipIndex == activeEducationTipIDs.count - 1 ? "Got It" : "Next",
                            onClose: dismissTreatmentEducationWalkthrough,
                            onPrimaryAction: advanceTreatmentEducationWalkthrough
                        )
                        .frame(maxWidth: 420)

                        if activeEducationTipIndex > 0 {
                            Button("Previous") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    activeEducationTipIndex -= 1
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PoolColor.poolTeal)
                            .padding(.bottom, 20)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.18), value: activeEducationTipIDs)
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
                            recommendationSectionCard(title: "Treatment Workflow", count: workflowSteps.count) {
                                if treatmentSteps.isEmpty {
                                    noTreatmentStepsState
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(Array(workflowSteps.enumerated()), id: \.element.id) { index, step in
                                            // 6pt of separation between Check cards shown back-to-back.
                                            let previousStepIsCheck = index > 0 && workflowSteps[index - 1].isFocusedCheckStep
                                            let needsCheckGap = step.isFocusedCheckStep && previousStepIsCheck
                                            workflowStepCard(step, index: index)
                                                .padding(.top, needsCheckGap ? 6 : 0)
                                        }
                                    }
                                }
                            }

                            if WatchlistPresentationText.shouldShow(count: watchlistItems.count) {
                                watchlistSectionCard
                            }

                        }

                        whyThisPlanCard

                        nextPoolTestCard

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
            isWhyThisPlanExpanded = savedWhyThisPlanExpandedState
            Task { await NotificationService.shared.checkAuthorizationStatus() }
            scheduleNextEducationTip()
        }
        .onChange(of: treatmentSteps.count) { _, _ in scheduleNextEducationTip() }
        .onChange(of: skippedTreatments.count) { _, _ in scheduleNextEducationTip() }
        .onChange(of: watchlistItems.count) { _, _ in scheduleNextEducationTip() }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let headerHeight: CGFloat = 290
        let contentTopPadding: CGFloat = 24
        let contentBottomPadding: CGFloat = 48

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
                    Text(TreatmentPlanSummaryText.heroTitle(actionableTreatmentCount: treatmentSteps.count))
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
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
            }
            .overlay(alignment: .bottomTrailing) {
                Image("Treatment Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .padding(.trailing, 20)
                    .offset(y: -48)
                    .padding(.bottom, -24)
            }
        }
        .frame(height: headerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .contentShape(Rectangle())
        .highPriorityGesture(recalculateLongPressGesture)
        .ignoresSafeArea(edges: .top)
    }

    private var recalculateLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.5)
            .onEnded { _ in
                guard TreatmentPlanDeveloperRecalculateAction.canPresent(isRecalculating: isRecalculatingRecommendations) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedDeveloperToolMode = .recalculate
                selectedJumpAheadOffset = .oneHour
                showingDeveloperTools = true
            }
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

    private var watchlistSectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isWatchlistExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionHeader("Watchlist", count: watchlistItems.count)
                        Text(WatchlistPresentationText.summary(count: watchlistItems.count))
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolColor.secondaryText)
                        .rotationEffect(.degrees(isWatchlistExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Watchlist, \(WatchlistPresentationText.summary(count: watchlistItems.count))")
            .accessibilityValue(isWatchlistExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)

            if isWatchlistExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(watchlistItems.enumerated()), id: \.element.id) { index, treatment in
                        watchlistCard(treatment, showsDivider: index < watchlistItems.count - 1)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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

    private func treatmentStepCard(
        _ treatment: Treatment,
        nextActionableTreatment: Treatment? = nil,
        showsDivider: Bool = true
    ) -> some View {
        TreatmentCardView(
            treatment: treatment,
            nextActionableTreatment: nextActionableTreatment,
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

    @ViewBuilder
    private func workflowStepCard(_ step: Treatment, index: Int) -> some View {
        let state = workflowEngine.state(for: step, in: workflowSteps)
        let isCurrent: Bool = {
            if case .current = state { return true }
            return false
        }()
        // Consecutive Check cards are separated by a 6pt gap (added at the ForEach), so the joining
        // internal divider is suppressed between two Checks to avoid a divider-then-gap seam.
        let nextStep = index + 1 < workflowSteps.count ? workflowSteps[index + 1] : nil
        let nextStepIsCheck = nextStep?.isFocusedCheckStep ?? false
        let showsDivider = nextStep != nil && !(step.isFocusedCheckStep && nextStepIsCheck)

        if step.isFocusedCheckStep {
            focusedCheckCard(step, state: state, sequenceNumber: index + 1, showsDivider: showsDivider)
        } else {
            TreatmentCardView(
                treatment: step,
                nextActionableTreatment: nextTreatment(after: index),
                allowsActions: isCurrent || step.isCompleted || step.isSkipped,
                presentation: .row,
                showsDivider: showsDivider,
                onComplete: { t in await completeTreatment(t) },
                onMarkIncomplete: { t in await markTreatmentIncomplete(t) },
                onSkip: { t in await skipTreatment(t) },
                onRestore: { t in await restoreTreatment(t) },
                openSwipeTreatmentID: $openSwipeTreatmentID
            )
            .overlay(alignment: .topLeading) {
                sequenceBadge(index + 1, state: state)
                    .offset(x: 6, y: 8)
            }
            .background(workflowBackground(for: state), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func nextTreatment(after index: Int) -> Treatment? {
        workflowSteps
            .dropFirst(index + 1)
            .first { !$0.isFocusedCheckStep && !$0.isCompleted && !$0.isSkipped }
    }

    private func sequenceBadge(_ number: Int, state: TreatmentWorkflowEngine.StepState) -> some View {
        Text("\(number)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(sequenceColor(for: state), in: Circle())
            .accessibilityHidden(true)
    }

    private func sequenceColor(for state: TreatmentWorkflowEngine.StepState) -> Color {
        switch state {
        case .current: return PoolColor.poolTeal
        case .waiting: return PoolColor.statusTesting
        case .upcoming: return PoolColor.secondaryText
        case .completed: return PoolColor.statusIdeal
        case .skipped: return PoolColor.statusSlight
        }
    }

    private func workflowBackground(for state: TreatmentWorkflowEngine.StepState) -> Color {
        switch state {
        case .upcoming, .waiting:
            return PoolColor.appBackground.opacity(0.55)
        default:
            return .clear
        }
    }

    private func focusedCheckCard(
        _ checkStep: Treatment,
        state: TreatmentWorkflowEngine.StepState,
        sequenceNumber: Int,
        showsDivider: Bool
    ) -> some View {
        let isCurrent: Bool = {
            if case .current = state { return true }
            return false
        }()

        // Swipe Skip/Restore is offered only when the canonical ViewModel rule would accept the transition
        // (unresolved, not superseded, parent not skipped) — the UI and ViewModel agree by construction.
        let gestureEnabled = viewModel.focusedCheckTransitionRejection(checkStep) == nil

        let cardBody = VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PoolColor.statusTesting)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 5) {
                    Text(checkStep.chemicalName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                        .strikethrough(checkStep.isSkipped, color: PoolColor.secondaryText)

                    Text(checkStep.actionDescription)
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)

                    Text(checkStateLabel(state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PoolColor.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PoolColor.statusTesting.opacity(0.20), in: Capsule())
                }

                Spacer()

                checkControl(for: checkStep, state: state, isCurrent: isCurrent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Text(checkStep.instructions)
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
                .padding(.horizontal, 58)
                .padding(.bottom, 14)

            if showsDivider {
                Rectangle()
                    .fill(PoolColor.statusTesting.opacity(0.35))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
            }
        }
        .background(PoolColor.statusTesting.opacity(0.20), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(PoolColor.statusTesting, lineWidth: 1)
        )

        return SwipeableSkipRow(
            itemID: checkStep.id,
            isSkipped: checkStep.isSkipped,
            gestureEnabled: gestureEnabled,
            cornerRadius: 14,
            skipAccessibilityLabel: "Skip check",
            restoreAccessibilityLabel: "Restore check",
            openSwipeID: $openSwipeTreatmentID,
            onSkip: { await skipTreatment(checkStep) },
            onRestore: { await restoreTreatment(checkStep) }
        ) {
            cardBody
        }
        .overlay(alignment: .topLeading) {
            sequenceBadge(sequenceNumber, state: state)
                .offset(x: 6, y: 8)
        }
    }

    /// The Check's status control. It NEVER completes the Check — the current-state control only opens the
    /// measurement-entry sheet. A checkmark appears ONLY for a genuinely completed Check; the active step
    /// shows an explicit "Enter" call-to-action so it can never be mistaken for a completed check. Skip/
    /// Restore are handled by the shared swipe row, not inline buttons.
    @ViewBuilder
    private func checkControl(for checkStep: Treatment, state: TreatmentWorkflowEngine.StepState, isCurrent: Bool) -> some View {
        if checkStep.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(PoolColor.statusIdeal)
                .accessibilityLabel("Check complete")
        } else if checkStep.isSkipped {
            Image(systemName: "slash.circle")
                .font(.title3)
                .foregroundStyle(PoolColor.statusSlight)
                .accessibilityLabel("Check skipped")
        } else if isCurrent {
            Button {
                focusedCheckStep = checkStep
            } label: {
                Text("Enter")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(PoolColor.poolTeal, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enter \(checkStep.chemicalName) results")
            .accessibilityHint("Opens measurement entry. The Check is not complete until you save a result.")
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(PoolColor.divider)
                .accessibilityLabel("Check not yet due")
        }
    }

    private func checkStateLabel(_ state: TreatmentWorkflowEngine.StepState) -> String {
        switch state {
        case .current:
            return "Ready to check"
        case .waiting(let availableAt):
            if availableAt > Date() {
                let minutes = max(1, Int(availableAt.timeIntervalSince(Date()) / 60))
                return "Ready in \(NotificationService.waitLabel(minutes: minutes))"
            }
            return "Ready now"
        case .upcoming:
            return "Waiting for earlier steps"
        case .completed:
            return "Check complete"
        case .skipped:
            return "Skipped"
        }
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

    private func scheduleNextEducationTip() {
        guard activeEducationTipIDs.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard activeEducationTipIDs.isEmpty else { return }
            let tips = eligibleTreatmentEducationTips()
            guard !tips.isEmpty else { return }
            activeEducationTipIndex = 0
            activeEducationTipIDs = tips
        }
    }

    private func eligibleTreatmentEducationTips() -> [ContextualTipID] {
        let store = ContextualEducationStore.shared
        let candidates: [ContextualTipID] = [
            .firstTreatmentPlanOverview,
            .firstTreatmentCompletion,
            .firstTreatmentSkip,
            .firstTreatmentReinstate,
            .firstWatchlist,
            .firstNextPoolTest
        ]

        return candidates.filter { tipID in
            !store.hasSeen(tipID)
                && ContextualEducationRules.isTipEligible(
                    tipID,
                    actionableTreatmentCount: treatmentSteps.count,
                    skippedTreatmentCount: skippedTreatments.count,
                    watchlistCount: watchlistItems.count,
                    hasNextPoolTest: true
                )
        }
    }

    private func advanceTreatmentEducationWalkthrough() {
        if activeEducationTipIndex < activeEducationTipIDs.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeEducationTipIndex += 1
            }
        } else {
            dismissTreatmentEducationWalkthrough()
        }
    }

    private func dismissTreatmentEducationWalkthrough() {
        activeEducationTipIDs.forEach { ContextualEducationStore.shared.markSeen($0) }
        withAnimation(.easeOut(duration: 0.18)) {
            activeEducationTipIDs = []
            activeEducationTipIndex = 0
        }
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

    // MARK: - Why This Treatment

    private var whyThisPlanExpansionKey: String {
        "TreatmentPlanSheet.whyThisPlanExpanded.\(test.id.uuidString)"
    }

    private var savedWhyThisPlanExpandedState: Bool {
        UserDefaults.standard.bool(forKey: whyThisPlanExpansionKey)
    }

    private func saveWhyThisPlanExpandedState(_ isExpanded: Bool) {
        UserDefaults.standard.set(isExpanded, forKey: whyThisPlanExpansionKey)
    }

    private var whyThisPlanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isWhyThisPlanExpanded.toggle()
                }
                saveWhyThisPlanExpandedState(isWhyThisPlanExpanded)
            } label: {
                HStack(spacing: 10) {
                    Text("Why This Treatment")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Image(systemName: isWhyThisPlanExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(PoolColor.primaryText)
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

    private var nextPoolTestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Next Pool Tests", systemImage: "calendar.badge.clock")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.primaryText)

            nextPoolTestRow(
                title: "Test FC & pH",
                dateText: routineDateText(nextTestSchedule?.fcAndPH.recommendedDate),
                subtitle: "A quick check between full tests to make sure things are on track."
            )

            nextPoolTestRow(
                title: "Full Test Panel",
                dateText: routineDateText(nextTestSchedule?.fullPanel.recommendedDate),
                subtitle: "Run your complete test panel to reassess overall water balance."
            )

            Text(nextPoolTestReminderStatus)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(PoolColor.sand.opacity(0.45), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(PoolColor.sand, lineWidth: 1)
                )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func nextPoolTestRow(title: String, dateText: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(PoolColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var whyPlanSummary: [String] {
        WhyThisPlanNarrative.summaryLines(
            treatmentActions: treatmentActions,
            focusedChecks: focusedChecks,
            test: test,
            chlorineDemandScore: confidenceInput.chlorineDemandScore,
            hasPoolConditions: confidenceInput.hasPoolConditions
        )
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
            factors.append("FC is below the operating target.")
        }
        if test.cyanuricAcid > 50 && test.cyanuricAcid < 90 {
            factors.append("CYA is elevated but manageable and should be tracked independently.")
        }
        let hasAcidTreatment = treatmentActions.contains(where: { $0.isAcidTreatment })
        if test.totalAlkalinity > 140 && (7.2...7.8).contains(test.pH) && !hasAcidTreatment {
            factors.append("pH is safe; acid is not currently needed.")
        }
        if confidenceInput.chlorineDemandScore >= 3 {
            factors.append("Logged pool conditions increased expected chlorine demand.")
        }
        if test.resolvedPoolConditions.hasOrganicLoadReduction {
            factors.append("Skimming, cleaning, or brushing may have reduced some organic load.")
        }
        if test.resolvedPoolConditions.backwashedFilter == .yes && confidenceInput.waterChangeScore >= 3 {
            let values = viewModel.poolConfig.isSaltwater ? "CYA, hardness, alkalinity, salt, or chlorine" : "CYA, hardness, alkalinity, or chlorine"
            factors.append("Backwashing and water replacement may explain dilution in \(values).")
        } else if confidenceInput.waterChangeScore >= 3 {
            let values = viewModel.poolConfig.isSaltwater ? "stabilizer, hardness, alkalinity, salt, or chlorine" : "stabilizer, hardness, alkalinity, or chlorine"
            factors.append("Recent water addition or rain may have diluted \(values).")
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
        WhyThisPlanNarrative.expectedOutcomes(
            treatmentActions: treatmentActions,
            focusedChecks: focusedChecks,
            test: test
        )
    }

    private var nextTestTiming: String {
        "Test FC & pH: \(routineDateText(nextTestSchedule?.fcAndPH.recommendedDate)). "
        + "Full Test Panel: \(routineDateText(nextTestSchedule?.fullPanel.recommendedDate))."
    }

    /// Export-facing routine timing that consumes the canonical schedule satisfaction state via
    /// `firstUpcoming`: a satisfied/past FC & pH quick check is no longer upcoming (firstUpcoming advances
    /// to the Full Test Panel), so it is omitted here. The Full Test Panel is always reported, and both are
    /// reported while the FC & pH check is still upcoming. No dates are re-derived.
    private var exportNextTestTiming: String {
        ExternalReviewExportBuilder.routineTimingLine(schedule: nextTestSchedule, dateText: routineDateText)
    }

    private func routineDateText(_ date: Date?) -> String {
        guard let date else { return "After your next full test" }
        return relativeText(for: date)
    }

    private func relativeText(for date: Date) -> String {
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow around \(Self.timeFormatter.string(from: date))"
        }
        if Calendar.current.isDateInToday(date) {
            return "Today around \(Self.timeFormatter.string(from: date))"
        }
        return Self.reminderDateFormatter.string(from: date)
    }

    private var nextPoolTestReminderStatus: String {
        if !viewModel.poolConfig.enableNextPoolTestReminders {
            return "Next pool test reminders are off"
        }
        if NotificationService.shared.isAuthorized {
            return "Reminders Scheduled"
        }
        return "Turn on notifications to get these reminders"
    }

    private var validationPrompt: String {
        let config = viewModel.poolConfig
        let previousLogs = Array(recentHistory.prefix(5))
        let swimAssessment = viewModel.swimReadinessAssessment(for: test, in: tests)
        let poolScoreAssessment = viewModel.scoreAssessment(for: test, in: tests)

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
        - Preferred chlorine: \(config.chlorinePreference.displayName) (\(config.chlorinePreference.productID.concentrationLabel))
        - Preferred pH increaser: \(config.pHIncreaserPreference.displayName)
        - Preferred pH decreaser: \(config.pHDecreaserPreference.displayName) (\(config.pHDecreaserPreference.productID.concentrationLabel))
        - Preferred alkalinity increaser: \(config.alkalinityIncreaserPreference.displayName)
        - Preferred calcium increaser: \(config.calciumIncreaserPreference.displayName)
        - Preferred stabilizer: \(config.stabilizerPreference.displayName)
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

        7. Current Pool Score (maintenance/health summary — not a swim-readiness authority)
        - Score: \(poolScoreAssessment.score)
        - Label: \(poolScoreAssessment.grade)
        - Main score drivers (canonical ChemistryPolicy states): \(poolScoreAssessment.drivers.isEmpty ? "All parameters within their operating range." : poolScoreAssessment.drivers.joined(separator: ", "))

        8. Swim Readiness (Swimability V2)
        \(ExternalReviewExportBuilder.swimReadinessSection(swimAssessment))

        9. Treatment Actions
        \(ExternalReviewExportBuilder.treatmentActionsSection(chemicalActions: treatmentSteps, test: test, config: config))

        10. Focused Checks
        \(ExternalReviewExportBuilder.focusedChecksSection(allTreatments: allTreatments, test: test, recentHistory: recentHistory, config: config))

        11. Watchlist / Monitoring
        \(watchlistItems.isEmpty ? "No watchlist items." : watchlistItems.map(watchlistExport).joined(separator: "\n\n"))

        12. Why This Plan
        Summary:
        \(bulletedLines(whyPlanSummary))

        Confidence:
        - \(confidenceLabel.rawValue)

        Key factors:
        \(bulletedLines(keyFactors))

        Expected outcome:
        \(bulletedLines(expectedOutcomes))

        13. Engine Deferrals / Avoided Recommendations
        \(ExternalReviewExportBuilder.engineDeferralsSection(allTreatments: allTreatments))

        14. Next Full Pool Test
        - \(exportNextTestTiming)

        15. Product and Timing Audit
        \(ExternalReviewExportBuilder.treatmentAuditSection(
            config: config,
            test: test,
            treatments: treatmentSteps,
            recentHistory: recentHistory,
            routineNextTestTiming: exportNextTestTiming
        ))

        16. User Prompt
        Please review this pool test log and treatment plan. Tell me whether the recommendation is chemically sound, whether anything is missing or over-aggressive, and what I should do next.
        """
    }

    private func treatmentStepExport(_ treatment: Treatment) -> String {
        """
        - Title: \(treatment.chemicalName)
          Urgency: \(treatment.urgency.displayName)
          Amount: \(formattedTreatmentAmount(treatment))
          Product: \(productExportText(for: treatment))
          Product differs from global preference: \(productDiffersFromGlobalPreference(treatment) ? "Yes" : "No")
          Calculated dose before safety cap: \(calculatedDoseBeforeCapText(for: treatment))
          Final recommended dose: \(formattedTreatmentAmount(treatment))
          Safety cap applied: \(treatment.wasDoseCapped ? "Yes" : "No")
          Target parameter: \(treatment.targetParameter.isEmpty ? "not specified" : treatment.targetParameter)
          Target value: \(targetValueText(for: treatment))
          Why recommended: \(treatment.actionDescription)
          Expected effect: \(expectedEffectText(for: treatment))
          Treatment verification classification: \(verificationClassificationText(for: treatment))
          Treatment verification timing: \(verificationTimingText(for: treatment))
          Recommended next routine test timing: \(exportNextTestTiming)
          Retest/wait timing: \(waitTimingText(for: treatment))
          Status: \(treatmentStatusText(treatment))
        """
    }

    private func productExportText(for treatment: Treatment) -> String {
        guard let productID = treatment.productIdentifier.flatMap(ChemicalProductID.init(rawValue:)) else {
            return treatment.chemicalName
        }
        return "\(productID.displayName) — \(productID.concentrationLabel)"
    }

    private func productDiffersFromGlobalPreference(_ treatment: Treatment) -> Bool {
        guard
            let productID = treatment.productIdentifier,
            let globalID = treatment.globalPreferenceIdentifier
        else { return false }
        return productID != globalID
    }

    private func calculatedDoseBeforeCapText(for treatment: Treatment) -> String {
        guard treatment.calculatedDoseBeforeCap > 0 else { return "Not applicable" }
        return "\(treatment.calculatedDoseBeforeCap.formattedTreatmentAmount) \(treatment.calculatedDoseBeforeCapUnit)"
    }

    private func hasProblemWater(_ test: PoolTest) -> Bool {
        let indicators = Set(test.visualIndicators)
        return indicators.contains(VisualIndicator.cloudyWater.rawValue)
            || indicators.contains(VisualIndicator.greenWater.rawValue)
            || indicators.contains(VisualIndicator.algaeSpots.rawValue)
            || indicators.contains(VisualIndicator.strongChlorineSmell.rawValue)
    }

    private func verificationClassificationText(for treatment: Treatment) -> String {
        guard treatment.amount > 0 && !treatment.isWatchlistItem else { return "Routine next test" }
        switch treatment.targetParameter {
        case "freeChlorine":
            return treatment.urgency == .immediate || hasProblemWater(test) || (treatment.urgency == .recommended && test.combinedChlorine > 0.5)
                ? "Required verification"
                : "Optional verification"
        case "pH", "totalAlkalinity", "cyanuricAcid":
            return "Required verification"
        default:
            return "Routine next test"
        }
    }

    private func verificationTimingText(for treatment: Treatment) -> String {
        switch treatment.targetParameter {
        case "freeChlorine":
            if treatment.urgency == .immediate || test.combinedChlorine > 0.5 || hasProblemWater(test) {
                return "Verify FC/CC after about \(NotificationService.waitLabel(minutes: max(60, treatment.minutesBeforeNext))) of circulation."
            }
            return "Optional FC check after about 1 hour of circulation; routine next test remains separate."
        case "pH", "totalAlkalinity":
            return "Verify pH after circulation, typically about 4 hours for acid or pH increaser."
        case "cyanuricAcid":
            return "Granular stabilizer may take several days to show reliably; liquid stabilizer can be checked sooner after circulation."
        default:
            return waitTimingText(for: treatment)
        }
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
        let treatmentSummary = ExternalReviewExportBuilder.completedOrSkippedStepsSummary(for: test)

        return """
        - Date/time: \(Self.promptDateFormatter.string(from: test.date))
          FC: \(formatPPM(test.freeChlorine)); CC: \(formatPPM(test.combinedChlorine)); pH: \(formatNumber(test.pH)); TA: \(formatPPM(test.totalAlkalinity)); CH: \(formatPPM(test.calciumHardness)); CYA: \(formatPPM(test.cyanuricAcid))
          Pool score: \(viewModel.overallScore(for: test, previousTest: viewModel.previousTest(before: test, in: tests), recentHistory: viewModel.recentHistory(before: test, in: tests, limit: 10)))
          Key pool conditions: \(shortConditionsSummary(for: test.resolvedPoolConditions))
          Completed/skipped workflow steps attached to this prior test log: \(treatmentSummary)
        """
    }

    private func poolConditionsExport(for conditions: PoolConditions, config: PoolConfiguration) -> String {
        var lines: [String] = [
            "- Swimming: \(conditions.swimmingLoad.exportText)",
            "- Rain: \(conditions.rainLoad.exportText)",
            "- Organic debris: \(conditions.organicDebrisLoad.exportText)",
            "- Backwashed filter: \(conditions.backwashedFilter.exportText)",
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
        if confidenceInput.waterChangeScore >= 3 {
            lines.append("- Large CYA/CH/TA corrections avoided because recent water change, backwashing, or rain may explain dilution; retest is preferred unless values are unsafe.")
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
            drivers.append("FC below operating target")
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
        if confidenceInput.waterChangeScore >= 3 {
            drivers.append(test.resolvedPoolConditions.backwashedFilter == .yes ? "possible dilution from backwashing/water replacement" : "possible dilution")
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
        let backwash = conditions.backwashedFilter == .yes ? ", backwashed filter" : ""
        return "demand \(conditions.chlorineDemandContribution), dilution \(conditions.waterChangeContribution)\(backwash)"
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
        TreatmentTimingGuidance.waitTimingText(for: treatment)
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
            return "CYA trend and whether stabilizer is still in the manageable range"
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
        if confidenceInput.chlorineDemandScore >= 3 || confidenceInput.waterChangeScore >= 3 { sources.append("pool conditions") }
        if confidenceInput.hasVisualIndicators { sources.append("visual indicators") }
        return sources.isEmpty ? "current test" : sources.joined(separator: ", ")
    }

    private func scoreLabel(_ score: Int) -> String {
        ChemistryEngine.scoreStatusLabel(
            score: score,
            status: viewModel.currentStatusSummary(for: test)
        )
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

    private static let reminderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Complete Treatment

    @MainActor
    private func completeTreatment(_ treatment: Treatment) async {
        // Single completion authority lives in the ViewModel: it marks complete and schedules the right
        // follow-up (a Check-owned reminder, a next-step reminder, or a wait-complete "safe to swim"
        // reminder). The view presents feedback based on the reported outcome.
        let outcome = await viewModel.completeTreatment(treatment, in: tests, modelContext: modelContext)
        switch outcome {
        case .awaitingCheck:
            toastMessage = ToastMessage(
                text: "Marked complete. We'll remind you when it's time to re-test.",
                icon: "checkmark.circle.fill",
                color: PoolColor.statusIdeal
            )
        case .waitCompleteScheduled(let fireDate):
            toastMessage = ToastMessage(
                text: "Marked complete. We'll remind you when the circulation wait is up (around \(fireDate.formatted(date: .omitted, time: .shortened))).",
                icon: "bell.badge.fill",
                color: PoolColor.poolTeal
            )
        case .nextStepScheduled, .completed:
            toastMessage = ToastMessage(
                text: "Treatment marked complete.",
                icon: "checkmark.circle.fill",
                color: PoolColor.statusIdeal
            )
        }
    }

    private func recalculateRecommendations() {
        guard TreatmentPlanDeveloperRecalculateAction.canPresent(isRecalculating: isRecalculatingRecommendations) else { return }
        isRecalculatingRecommendations = true

        Task {
            do {
                try await viewModel.recalculateRecommendations(
                    for: test,
                    recentTests: recentHistory,
                    modelContext: modelContext
                )
                await viewModel.replaceNextPoolTestReminder(for: test, allTests: tests)
                await MainActor.run {
                    toastMessage = ToastMessage(
                        text: "Recommendations recalculated.",
                        icon: "checkmark.circle.fill",
                        color: PoolColor.statusIdeal
                    )
                    isRecalculatingRecommendations = false
                }
            } catch {
                await MainActor.run {
                    toastMessage = ToastMessage(
                        text: "Could not recalculate recommendations",
                        icon: "exclamationmark.triangle.fill",
                        color: PoolColor.statusOffRange
                    )
                    isRecalculatingRecommendations = false
                }
            }
        }
    }

    @MainActor
    private func runJumpAheadEvaluation(_ offset: TreatmentPlanDeveloperJumpAheadOffset) {
        viewModel.runSwimabilityV2JumpAheadComparison(
            for: test,
            recentTests: recentHistory,
            offset: offset
        )
        toastMessage = ToastMessage(
            text: "Jump Ahead \(offset.displayName) evaluation printed.",
            icon: "terminal.fill",
            color: PoolColor.poolTeal
        )
    }

    @MainActor
    private func saveFocusedCheck(_ checkStep: Treatment, values: [String: Double]) async throws -> FocusedCheckResult {
        // The ViewModel is the single authority: it records evidence, regenerates the plan, recomputes the
        // routine reminder, and returns the explicit closure outcome. The sheet presents that outcome.
        let result = try await viewModel.saveFocusedCheck(
            checkStep,
            values: values,
            for: test,
            allTests: tests,
            modelContext: modelContext
        )
        viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
            for: test,
            recentTests: recentHistory,
            context: "Focused Check Saved"
        )
        return result
    }

    @MainActor
    private func markTreatmentIncomplete(_ treatment: Treatment) async {
        let reminderCanceled = treatment.reminderNotificationIdentifier != nil
            || treatment.stepReminderNotificationIdentifier != nil
            || treatment.retestReminderNotificationIdentifier != nil
        viewModel.markTreatmentIncomplete(treatment)
        do {
            try modelContext.save()
            await viewModel.replaceNextPoolTestReminder(for: test, allTests: tests)
            viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
                for: test,
                recentTests: recentHistory,
                context: "Treatment Marked Incomplete"
            )
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
            await viewModel.replaceNextPoolTestReminder(for: test, allTests: tests)
            viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
                for: test,
                recentTests: recentHistory,
                context: "Treatment Skipped"
            )
        } catch {
            viewModel.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func restoreTreatment(_ treatment: Treatment) async {
        viewModel.restoreTreatment(treatment)
        do {
            try modelContext.save()
            await viewModel.replaceNextPoolTestReminder(for: test, allTests: tests)
            viewModel.runSwimabilityV2ComparisonAfterTreatmentStateChange(
                for: test,
                recentTests: recentHistory,
                context: "Treatment Restored"
            )
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

private extension BackwashedFilter {
    var exportText: String {
        switch self {
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

/// Which Taylor chlorine titration a drop-entry keypad is editing.
private enum FocusedCheckDropTarget: String, Identifiable {
    case freeChlorine
    case combinedChlorine
    var id: String { rawValue }
}

/// How a focused-Check parameter should be measured, given the user's configured testing method. This is
/// the single routing rule shared by the entry sheet (and its tests): a parameter + configured method maps
/// to the appropriate measurement interaction. It never invents behavior for unsupported methods.
enum FocusedCheckEntryMode: Equatable {
    /// Guide the physical Taylor K-2006 FAS-DPD titration (sample size + drop counters → ppm).
    case taylorDropChlorine
    /// Direct numeric entry of the resulting value (used for methods/parameters without a drop workflow).
    case directEntry
}

enum FocusedCheckEntryRouter {
    /// Resolves the measurement interaction for one Check parameter under the configured method. Only the
    /// Taylor K-2006 FAS-DPD kit drives the drop-count chlorine workflow, and only for FC/CC. Everything
    /// else (pH, other liquid-drop brands, digital meters, strips, pool-store) uses direct numeric entry.
    static func mode(for parameter: String, config: PoolConfiguration) -> FocusedCheckEntryMode {
        let isTaylorK2006 = config.testMethod == .liquidDropKit
            && config.liquidDropKitBrand == .taylorK2006FASDPD
        if isTaylorK2006, parameter == "freeChlorine" || parameter == "combinedChlorine" {
            return .taylorDropChlorine
        }
        return .directEntry
    }
}

/// Method-aware focused-Check entry. It resolves the user's configured testing method and, for the
/// Taylor K-2006 FAS-DPD kit measuring FC/CC, guides the physical drop-count test (sample size + drop
/// counters) exactly like normal Add Test — the user supplies drop counts and Pool Side computes ppm via
/// the canonical `TaylorFASDPDReading`. Other methods / parameters keep the direct numeric entry. Only the
/// Check's own parameters are ever shown, and saving still flows through the unchanged `saveFocusedCheck`.
private struct FocusedCheckEntrySheet: View {
    let checkStep: Treatment
    let sourceTest: PoolTest
    let onSave: ([String: Double]) async throws -> FocusedCheckResult

    @Environment(\.dismiss) private var dismiss
    @Environment(PoolViewModel.self) private var viewModel

    // Direct numeric entry (non-Taylor methods and non-chlorine parameters).
    @State private var values: [String: String] = [:]
    // Taylor FAS-DPD drop entry (Taylor K-2006 chlorine parameters). Drops are the physical observation.
    @State private var sampleSize: TaylorSampleSize = .twentyFiveMl
    @State private var fcDrops: Int? = nil
    @State private var ccDrops: Int? = nil
    @State private var dropEntryTarget: FocusedCheckDropTarget? = nil
    @State private var dropEntryText: String = ""
    @State private var dropEntryWantsFocus: Bool = false
    @State private var didSeed = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var result: FocusedCheckResult?

    // MARK: Configured method routing

    private var parameters: [String] { checkStep.checkParameters }
    private func isTaylorDropParameter(_ parameter: String) -> Bool {
        FocusedCheckEntryRouter.mode(for: parameter, config: viewModel.poolConfig) == .taylorDropChlorine
    }
    private var usesTaylorChlorine: Bool { parameters.contains(where: isTaylorDropParameter) }

    var body: some View {
        NavigationStack {
            if let result {
                FocusedCheckResultView(result: result) { dismiss() }
                    .navigationTitle("Check Result")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                entryForm
            }
        }
    }

    private var entryForm: some View {
        Form {
            Section {
                Text(checkStep.instructions)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
            }

            if usesTaylorChlorine {
                Section("Sample Size") {
                    Picker("Sample Size", selection: $sampleSize) {
                        ForEach(TaylorSampleSize.allCases) { size in
                            Text(size.displayLabel).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("1 drop = \(sampleSize.ppmPerDrop.formattedTreatmentAmount) ppm")
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                }
            }

            Section("Measurements") {
                ForEach(parameters, id: \.self) { parameter in
                    if isTaylorDropParameter(parameter) {
                        taylorChlorineRow(parameter)
                    } else {
                        genericRow(parameter)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(PoolColor.statusOffRange)
                }
            }
        }
        .navigationTitle(checkStep.chemicalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Check") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .onAppear(perform: seedValues)
        .sheet(item: $dropEntryTarget) { target in
            dropEntrySheet(for: target)
        }
    }

    // MARK: Taylor drop row (same interaction as Add Test)

    @ViewBuilder
    private func taylorChlorineRow(_ parameter: String) -> some View {
        let profile = chlorineProfile(for: parameter)
        let drops = chlorineDrops(for: parameter).wrappedValue
        let ppm = TaylorFASDPDReading.chlorinePPM(drops: drops ?? 0, sampleSize: sampleSize)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let field = ChemicalField(rawValue: parameter) {
                    ChemicalIcon(field: field, size: 40)
                }
                Text(displayName(for: parameter))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PoolColor.primaryText)
                Spacer()
                Text(drops == nil ? "—" : String(format: "%.1f ppm", ppm))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(drops == nil ? PoolColor.secondaryText : PoolColor.primaryText)
                    .monospacedDigit()
            }

            chlorineMeter(value: ppm, range: profile.range, goodRange: profile.good, hasValue: drops != nil)

            HStack(spacing: 12) {
                Text("Drops")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                Spacer()
                dropStepper(for: parameter)
            }
        }
        .padding(.vertical, 4)
    }

    private func chlorineMeter(value: Double, range: ClosedRange<Double>, goodRange: ClosedRange<Double>, hasValue: Bool) -> some View {
        ZStack {
            ChemicalMeterBackground(range: range, goodRange: goodRange)
                .frame(height: 8)
            GeometryReader { proxy in
                let ratio = range.upperBound > range.lowerBound
                    ? (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    : 0
                let clamped = CGFloat(min(max(ratio, 0), 1))
                Capsule()
                    .fill(hasValue ? PoolColor.poolTeal : PoolColor.divider)
                    .frame(width: 16, height: 16)
                    .offset(x: clamped * (proxy.size.width - 16))
                    .opacity(hasValue ? 1 : 0.35)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
    }

    private func dropStepper(for parameter: String) -> some View {
        let binding = chlorineDrops(for: parameter)
        return HStack(spacing: 12) {
            Button {
                if let current = binding.wrappedValue {
                    binding.wrappedValue = max(0, current - 1)
                }
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(PoolColor.poolTeal)
            }
            .buttonStyle(.plain)
            .disabled(binding.wrappedValue == nil)
            .opacity(binding.wrappedValue == nil ? 0.35 : 1)
            .accessibilityLabel("Decrease \(displayName(for: parameter)) drops")

            Button {
                beginDropEntry(for: parameter)
            } label: {
                Text(binding.wrappedValue.map(String.init) ?? "—")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolColor.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 34)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(PoolColor.poolTeal.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(displayName(for: parameter)) drops")
            .accessibilityHint("Opens a numeric entry")

            Button {
                binding.wrappedValue = (binding.wrappedValue ?? 0) + 1
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(PoolColor.poolTeal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(displayName(for: parameter)) drops")
        }
    }

    private func dropEntrySheet(for target: FocusedCheckDropTarget) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter a whole number of drops.")
                    .font(.footnote)
                    .foregroundStyle(PoolColor.secondaryText)

                DirectNumericTextField(
                    placeholder: "0",
                    text: $dropEntryText,
                    keyboardType: .numberPad,
                    wantsFocus: $dropEntryWantsFocus
                )
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(PoolColor.poolTeal.opacity(0.25), lineWidth: 1))

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PoolColor.sand.ignoresSafeArea())
            .navigationTitle(displayName(for: target.rawValue) + " Drops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dropEntryTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { applyDropEntry(for: target) }
                        .fontWeight(.semibold)
                        .disabled(Int(dropEntryText.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
            .onAppear { dropEntryWantsFocus = true }
            .onDisappear { dropEntryWantsFocus = false }
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PoolColor.sand)
    }

    private func beginDropEntry(for parameter: String) {
        let target: FocusedCheckDropTarget = parameter == "freeChlorine" ? .freeChlorine : .combinedChlorine
        dropEntryText = chlorineDrops(for: parameter).wrappedValue.map(String.init) ?? "0"
        dropEntryWantsFocus = true
        dropEntryTarget = target
    }

    private func applyDropEntry(for target: FocusedCheckDropTarget) {
        if let parsed = Int(dropEntryText.trimmingCharacters(in: .whitespaces)) {
            chlorineDrops(for: target.rawValue).wrappedValue = max(0, parsed)
        }
        dropEntryTarget = nil
    }

    private func chlorineDrops(for parameter: String) -> Binding<Int?> {
        parameter == "freeChlorine" ? $fcDrops : $ccDrops
    }

    private func chlorineProfile(for parameter: String) -> (range: ClosedRange<Double>, good: ClosedRange<Double>) {
        if parameter == "freeChlorine" {
            return (0...20, ChemistryEngine().freeChlorineTargetRange(cyanuricAcid: sourceTest.cyanuricAcid))
        }
        return (0...3, 0...0.5)
    }

    // MARK: Generic direct entry (unchanged behavior for other methods / parameters)

    private func genericRow(_ parameter: String) -> some View {
        HStack {
            Text(displayName(for: parameter))
            Spacer()
            TextField("0", text: binding(for: parameter))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit(for: parameter))
                .foregroundStyle(PoolColor.secondaryText)
        }
    }

    private func binding(for parameter: String) -> Binding<String> {
        Binding(
            get: { values[parameter] ?? "" },
            set: { values[parameter] = $0 }
        )
    }

    // MARK: Seeding + save

    private func seedValues() {
        guard !didSeed else { return }
        didSeed = true
        // Default the sample size to the source test's, so Taylor resolution matches normal Add Test.
        if let existing = sourceTest.taylorSampleSize { sampleSize = existing }
        if parameters.contains("freeChlorine") { fcDrops = sourceTest.taylorFCDrops }
        if parameters.contains("combinedChlorine") { ccDrops = sourceTest.taylorCCDrops }
        for parameter in parameters where !isTaylorDropParameter(parameter) {
            values[parameter] = defaultValue(for: parameter)
        }
    }

    @MainActor
    private func save() async {
        var parsed: [String: Double] = [:]

        // Taylor chlorine parameters: drops → ppm via the canonical calculator.
        if usesTaylorChlorine {
            for parameter in parameters where isTaylorDropParameter(parameter) {
                guard let drops = chlorineDrops(for: parameter).wrappedValue else {
                    errorMessage = "Enter the \(displayName(for: parameter)) drop count."
                    return
                }
                parsed[parameter] = TaylorFASDPDReading.chlorinePPM(drops: drops, sampleSize: sampleSize)
            }
        }

        // Any remaining parameters use the direct numeric entry.
        for parameter in parameters where !isTaylorDropParameter(parameter) {
            let text = values[parameter, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(text), value >= 0 else {
                errorMessage = "Enter a valid \(displayName(for: parameter)) result."
                return
            }
            parsed[parameter] = value
        }

        // Record the Taylor evidence/resolution on the source test BEFORE saving so the regenerated plan and
        // outcome interpret the new FC/CC at the correct measurement resolution (chlorine resolution derives
        // from the recorded sample size). This mirrors how Add Test persists the same observation.
        if usesTaylorChlorine {
            sourceTest.taylorSampleSize = sampleSize
            if parameters.contains("freeChlorine") { sourceTest.taylorFCDrops = fcDrops }
            if parameters.contains("combinedChlorine") { sourceTest.taylorCCDrops = ccDrops }
        }

        isSaving = true
        do {
            // Present the explicit outcome instead of dismissing straight back to the plan.
            result = try await onSave(parsed)
        } catch {
            errorMessage = "Could not save this check."
        }
        isSaving = false
    }

    private func defaultValue(for parameter: String) -> String {
        let value: Double
        switch parameter {
        case "freeChlorine": value = sourceTest.freeChlorine
        case "combinedChlorine": value = sourceTest.combinedChlorine
        case "pH": value = sourceTest.pH
        case "totalAlkalinity": value = sourceTest.totalAlkalinity
        case "calciumHardness": value = sourceTest.calciumHardness
        case "cyanuricAcid": value = sourceTest.cyanuricAcid
        case "saltLevel": value = sourceTest.saltLevel ?? 0
        default: value = 0
        }
        return value.formattedTreatmentAmount
    }

    private func displayName(for parameter: String) -> String {
        switch parameter {
        case "freeChlorine": return "FC"
        case "combinedChlorine": return "CC"
        case "pH": return "pH"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        case "saltLevel": return "Salt"
        default: return parameter
        }
    }

    private func unit(for parameter: String) -> String {
        parameter == "pH" ? "" : "ppm"
    }
}

/// Explicit interpretation of a focused Check, shown immediately after Save so the user never has to
/// infer success from the absence of another treatment card.
private struct FocusedCheckResultView: View {
    let result: FocusedCheckResult
    let onContinue: () -> Void

    private var isSuccess: Bool { result.allResolved && !result.anyBlocksSwimming }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 34))
                        .foregroundStyle(accentColor)
                    Text(result.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(PoolColor.cloudWhite)
                }

                VStack(alignment: .leading, spacing: 10) {
                    resultRow(label: "Result", value: measuredSummary)
                    Divider().overlay(PoolColor.cloudWhite.opacity(0.08))
                    labeledParagraph(title: "What this means", text: result.interpretation)
                    Divider().overlay(PoolColor.cloudWhite.opacity(0.08))
                    labeledParagraph(title: "Next", text: result.nextAction)
                }
                .padding(16)
                .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 16))

                Button(action: onContinue) {
                    Text(result.hasFollowUpTreatment ? "View updated plan" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(PoolColor.cloudWhite)
                }
            }
            .padding(20)
        }
        .background(PoolColor.appBackground)
    }

    private var iconName: String {
        if result.anyBlocksSwimming { return "exclamationmark.triangle.fill" }
        if isSuccess { return "checkmark.seal.fill" }
        return "arrow.triangle.2.circlepath"
    }

    private var accentColor: Color {
        if result.anyBlocksSwimming { return PoolColor.statusCritical }
        if isSuccess { return PoolColor.statusIdeal }
        return PoolColor.sunshine
    }

    private var measuredSummary: String {
        result.parameterOutcomes
            .map { "\($0.displayName) \($0.measuredValue.formattedTreatmentAmount)" }
            .joined(separator: ", ")
    }

    private func resultRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolColor.cloudWhite)
        }
    }

    private func labeledParagraph(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .tracking(0.5)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.5))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ExternalReviewExportBuilder {
    /// Builds the routine "next tests" line for the export, consuming the canonical schedule satisfaction
    /// state via `firstUpcoming`. A satisfied/past FC & pH quick check (firstUpcoming advanced to the Full
    /// Test Panel) is omitted; the Full Test Panel is always reported; both are reported while the FC & pH
    /// check is still upcoming. `dateText` formats an optional date exactly as the plan UI does — no dates
    /// are re-derived here.
    static func routineTimingLine(schedule: NextTestSchedule?, dateText: (Date?) -> String) -> String {
        var lines: [String] = []
        if schedule?.firstUpcoming.source == .routineFCAndPH {
            lines.append("Test FC & pH: \(dateText(schedule?.fcAndPH.recommendedDate)).")
        }
        lines.append("Full Test Panel: \(dateText(schedule?.fullPanel.recommendedDate)).")
        return lines.joined(separator: " ")
    }

    static func treatmentAuditSection(
        config: PoolConfiguration,
        test: PoolTest,
        treatments: [Treatment],
        recentHistory: [PoolTest],
        routineNextTestTiming: String
    ) -> String {
        let saltBehavior = config.isSaltwater && config.chlorinePreference == .saltGenerator
            ? "Chlorine is expected primarily from the salt generator unless a treatment uses a supplemental product."
            : "Chlorine is expected from the selected supplemental product."
        let pHTrend = pHTrendReasoning(test: test, recentHistory: recentHistory)
        let acidTiming = timeSinceLastCompletedAcidTreatment(recentHistory: recentHistory)
        let suppressed = suppressedRecommendationReasons(treatments: treatments)

        // Focused Checks are verification steps, not chemical products — never model them here.
        let chemicalTreatments = treatments.filter { !$0.isFocusedCheckStep }
        let treatmentLines = chemicalTreatments.map { treatment in
            let selectedProduct = treatment.productIdentifier
                .flatMap(ChemicalProductID.init(rawValue:))
            let globalProduct = treatment.globalPreferenceIdentifier
                .flatMap(ChemicalProductID.init(rawValue:))
            let concentration = selectedProduct?.concentrationLabel ?? "not available"
            let substitution = selectedProduct != nil && globalProduct != nil && selectedProduct != globalProduct
            let preCapDose = treatment.calculatedDoseBeforeCap > 0
                ? "\(treatment.calculatedDoseBeforeCap.formattedTreatmentAmount) \(treatment.calculatedDoseBeforeCapUnit)"
                : "not applicable"
            let finalDose = treatment.amount > 0
                ? "\(treatment.amount.formattedTreatmentAmount) \(treatment.unit)"
                : "not applicable"

            return """
            - Treatment product: \(selectedProduct?.displayName ?? treatment.chemicalName)
              Global preference: \(globalProduct?.displayName ?? globalPreference(for: treatment, config: config))
              Product concentration: \(concentration)
              Differs from global preference: \(substitution ? "Yes" : "No")
              Calculated dose before safety cap: \(preCapDose)
              Final recommended dose: \(finalDose)
              Safety cap applied: \(treatment.wasDoseCapped ? "Yes" : "No")
              Salt-system behavior: \(saltBehavior)
              Why now: \(treatment.actionDescription)
              Treatment verification classification: \(verificationClassification(for: treatment, test: test))
              Treatment verification timing: \(verificationTiming(for: treatment, test: test))
            """
        }.joined(separator: "\n\n")

        let checkOutcomes = focusedCheckOutcomesSection(config: config, test: test, recentHistory: recentHistory)

        return """
        External Review Treatment Audit
        - Preferred chlorine: \(config.chlorinePreference.displayName) (\(config.chlorinePreference.productID.concentrationLabel))
        - Preferred pH decreaser: \(config.pHDecreaserPreference.displayName) (\(config.pHDecreaserPreference.productID.concentrationLabel))
        - Salt-system status: \(config.isSaltwater ? "On" : "Off")
        - Salt-system behavior: \(saltBehavior)
        - Historical pH trend used: \(pHTrend)
        - Time since last completed acid treatment: \(acidTiming)
        - Suppressed treatment reasons: \(suppressed)
        - Routine testing: \(routineNextTestTiming)

        \(treatmentLines.isEmpty ? "No active treatment products." : treatmentLines)
        \(checkOutcomes)
        """
    }

    /// Interpreted outcomes for completed focused Checks. Deterministically reconstructed from the Check's
    /// result test + the current (post-Check) plan; no historical outcome is fabricated when the result
    /// test cannot be resolved.
    private static func focusedCheckOutcomesSection(
        config: PoolConfiguration,
        test: PoolTest,
        recentHistory: [PoolTest]
    ) -> String {
        let completedChecks = test.treatments
            .filter { $0.isFocusedCheckStep && $0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !completedChecks.isEmpty else { return "" }

        let candidateTests = [test] + recentHistory
        let evaluator = FocusedCheckOutcomeEvaluator()

        let lines = completedChecks.compactMap { check -> String? in
            guard
                let resultTestID = check.checkResultTestID,
                let resultTest = candidateTests.first(where: { $0.id == resultTestID })
            else { return nil }

            let parameterLines = check.checkParameters.map { parameter -> String in
                let outcome = evaluator.outcome(
                    parameter: parameter,
                    priorValue: nil,
                    measuredValue: measuredValue(of: parameter, in: resultTest),
                    postCheckTest: resultTest,
                    postCheckTreatments: test.treatments,
                    config: config
                )
                let outcomeText: String
                switch outcome.kind {
                case .resolved:
                    outcomeText = "returned to operating range"
                case .noChemicalActionNeeded:
                    outcomeText = "outside ideal but no chemical correction warranted"
                default:
                    outcomeText = "still outside operating range"
                }
                let further = outcome.hasFollowUpTreatment ? "generated from the new measurement" : "none"
                return """
                  - \(outcome.displayName) result: \(outcome.measuredValue.formattedTreatmentAmount)
                    Outcome: \(outcomeText)
                    Further \(outcome.displayName) correction: \(further)
                """
            }.joined(separator: "\n")

            return "- \(check.chemicalName) (completed):\n\(parameterLines)"
        }

        guard !lines.isEmpty else { return "" }
        return "\nCompleted focused-check outcomes:\n" + lines.joined(separator: "\n")
    }

    private static func measuredValue(of parameter: String, in test: PoolTest) -> Double {
        switch parameter {
        case "freeChlorine": return test.freeChlorine
        case "combinedChlorine": return test.combinedChlorine
        case "pH": return test.pH
        case "totalAlkalinity": return test.totalAlkalinity
        case "calciumHardness": return test.calciumHardness
        case "cyanuricAcid": return test.cyanuricAcid
        case "saltLevel": return test.saltLevel ?? 0
        default: return 0
        }
    }

    private static func globalPreference(for treatment: Treatment, config: PoolConfiguration) -> String {
        switch treatment.targetParameter {
        case "freeChlorine":
            return config.chlorinePreference.displayName
        case "pH":
            return treatment.expectedDelta < 0
                ? config.pHDecreaserPreference.displayName
                : config.pHIncreaserPreference.displayName
        case "cyanuricAcid":
            return config.stabilizerPreference.displayName
        default:
            return "not applicable"
        }
    }

    private static func pHTrendReasoning(test: PoolTest, recentHistory: [PoolTest]) -> String {
        let ordered = Array(recentHistory.prefix(5).reversed()) + [test]
        guard ordered.count >= 3 else { return "not enough pH history" }
        let pHValues = ordered.map(\.pH)
        let taValues = ordered.map(\.totalAlkalinity)
        let pHChange = (pHValues.last ?? test.pH) - (pHValues.first ?? test.pH)
        let elevatedTACount = taValues.filter { $0 >= 140 }.count
        if pHChange >= 0.25 && elevatedTACount >= 3 {
            return "pH has gradually risen from \(format(pHValues.first ?? test.pH)) to \(format(pHValues.last ?? test.pH)) while TA remained elevated in \(elevatedTACount) logs."
        }
        return "pH history does not show enough upward movement to justify extra acid by trend alone."
    }

    private static func timeSinceLastCompletedAcidTreatment(recentHistory: [PoolTest]) -> String {
        let completed = recentHistory
            .flatMap(\.treatments)
            .filter { $0.isCompleted && $0.isAcidTreatment }
            .compactMap(\.completedAt)
            .max()
        guard let completed else { return "none found in recent history" }
        let days = max(0, Int(Date().timeIntervalSince(completed) / 86_400))
        return days == 0 ? "less than 1 day" : "\(days) day\(days == 1 ? "" : "s")"
    }

    private static func suppressedRecommendationReasons(treatments: [Treatment]) -> String {
        // Focused Checks are verification steps, never "suppressed treatments".
        let reasons = treatments
            .filter { !$0.isFocusedCheckStep && ($0.isWatchlistItem || $0.amount == 0) }
            .map(\.actionDescription)
        return reasons.isEmpty ? "none reported" : reasons.joined(separator: "; ")
    }

    private static func verificationClassification(for treatment: Treatment, test: PoolTest) -> String {
        switch ExportVerificationRequirement.resolve(for: treatment, test: test, config: .current) {
        case .required:      return "Required verification"
        case .discretionary: return "Discretionary verification"
        case .none:          return "No treatment-specific verification"
        }
    }

    private static func verificationTiming(for treatment: Treatment, test: PoolTest) -> String {
        guard treatment.amount > 0 && !treatment.isWatchlistItem && !treatment.isFocusedCheckStep else {
            return "No treatment-specific verification."
        }
        switch treatment.targetParameter {
        case "freeChlorine":
            return ExportVerificationRequirement.resolve(for: treatment, test: test, config: .current) == .required
                ? "Verify FC/CC after circulation before swimming or adding more chlorine."
                : "Discretionary FC verification after about 1 hour of circulation."
        case "pH", "totalAlkalinity":
            return "Verify pH after circulation, typically about 4 hours."
        case "cyanuricAcid":
            return "Verify based on product type; granular CYA can take several days to register reliably."
        default:
            return "Use the treatment wait timing."
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: - Swim Readiness V2 (§4)

    /// Sourced directly from the canonical Swimability V2 assessment. No thresholds are reproduced here.
    static func swimReadinessSection(_ assessment: SwimabilityV2Assessment) -> String {
        func gateLine(_ gate: SwimReadinessGateResult) -> String {
            "    - \(gate.identifier.rawValue): \(gate.state.rawValue)\(gate.reason.isEmpty ? "" : " — \(gate.reason)")"
        }
        let failed = assessment.failedGates
        let unknown = assessment.unknownGates
        let pending = assessment.treatmentAwareContext?.pendingVerificationGateIdentifiers ?? []
        let readyTime = assessment.earliestPredictedReadyTime.map { ISO8601DateFormatter().string(from: $0) } ?? "not predicted"

        var lines: [String] = [
            "- V2 state: \(assessment.state.rawValue)",
            "- Swimming blocked: \(assessment.swimmingBlocked ? "Yes" : "No")",
            "- Testing required: \(assessment.testingRequired ? "Yes" : "No")",
            "- Verification required before swimming: \((assessment.treatmentAwareContext?.verificationRequired ?? false) ? "Yes" : "No")",
            "- Evidence type: \(assessment.evidenceType.rawValue)",
            "- Confidence: \(assessment.confidence.rawValue)",
            "- Prediction confidence: \(assessment.predictionConfidence?.rawValue ?? "not applicable")",
            "- Earliest predicted ready time: \(readyTime)",
            "- Readiness explanation: \(assessment.summary)"
        ]
        lines.append("- Failed gates: \(failed.isEmpty ? "none" : failed.map { $0.identifier.rawValue }.joined(separator: ", "))")
        if !failed.isEmpty { lines.append(contentsOf: failed.map(gateLine)) }
        lines.append("- Unknown gates: \(unknown.isEmpty ? "none" : unknown.map { $0.identifier.rawValue }.joined(separator: ", "))")
        lines.append("- Pending verification gates: \(pending.isEmpty ? "none" : pending.map { $0.rawValue }.sorted().joined(separator: ", "))")
        if !assessment.invalidationReasons.isEmpty {
            lines.append("- Evidence invalidation: \(assessment.invalidationReasons.joined(separator: "; "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Treatment Actions (§1A, §3, §6, §7)

    /// Chemical / non-chemical action steps only (Focused Checks are handled separately). Uses canonical
    /// verification and staged/capped-aware expected response.
    static func treatmentActionsSection(chemicalActions: [Treatment], test: PoolTest, config: PoolConfiguration) -> String {
        let actions = chemicalActions.filter { !$0.isFocusedCheckStep && !$0.isWatchlistItem && $0.urgency != .advisory }
        guard !actions.isEmpty else { return "No actionable treatment steps." }
        return actions.map { treatmentActionExport($0, test: test, config: config) }.joined(separator: "\n\n")
    }

    private static func treatmentActionExport(_ treatment: Treatment, test: PoolTest, config: PoolConfiguration) -> String {
        var lines: [String] = ["- Title: \(treatment.chemicalName)",
                               "  Urgency: \(treatment.urgency.displayName)",
                               "  Target parameter: \(treatment.targetParameter.isEmpty ? "not specified" : treatment.targetParameter)"]
        if treatment.amount > 0 {
            lines.append("  Current application: \(treatment.amount.formattedTreatmentAmount)\(treatment.unit.isEmpty ? "" : " \(treatment.unit)")")
            if let product = treatment.productIdentifier.flatMap(ChemicalProductID.init(rawValue:)) {
                lines.append("  Selected product: \(product.displayName) — \(product.concentrationLabel)")
            }
            if treatment.calculatedDoseBeforeCap > 0 {
                let total = "\(treatment.calculatedDoseBeforeCap.formattedTreatmentAmount) \(treatment.calculatedDoseBeforeCapUnit)"
                lines.append("  Total calculated correction: \(treatment.wasDoseCapped ? total : "same as current application")")
            }
            lines.append("  Safety/application cap applied: \(treatment.wasDoseCapped ? "Yes" : "No")")
        } else {
            lines.append("  Current application: not a dosed addition")
        }
        lines.append("  Why recommended: \(treatment.actionDescription)")
        lines.append("  Expected response: \(expectedResponseText(for: treatment))")
        lines.append("  Verification requirement: \(ExportVerificationRequirement.resolve(for: treatment, test: test, config: config).label)")
        lines.append("  Status: \(statusText(treatment))")
        return lines.joined(separator: "\n")
    }

    /// §6 — staged/capped treatments never claim the full theoretical delta for the current application.
    static func expectedResponseText(for treatment: Treatment) -> String {
        guard treatment.amount > 0, !treatment.expectedEffectParameter.isEmpty else {
            return "no direct chemical addition"
        }
        let param = displayParameterName(treatment.expectedEffectParameter)
        let staged = treatment.wasDoseCapped
            || treatment.targetParameter == "pH"
            || treatment.targetParameter == "totalAlkalinity"
        if staged {
            // Copy must reflect the actual workflow: only reference a focused Check when one really exists
            // for this treatment. Otherwise verification is discretionary — instruct a plain retest.
            let hasFocusedCheck = treatment.poolTest?.treatments.contains {
                $0.isFocusedCheckStep && $0.parentTreatmentID == treatment.id
            } ?? false
            let verifyClause = hasFocusedCheck
                ? "Verify with the focused Check after circulation before adding more"
                : "Retest \(param) after circulation before adding more"
            return "This application begins moving \(param) toward the operating range; it is not expected to complete the full correction. \(verifyClause) — the next step is recalculated from the new measurement."
        }
        // Uncapped linear addition (e.g. liquid chlorine): a dose-derived estimate of THIS application.
        let sign = treatment.expectedDelta > 0 ? "+" : ""
        let delay = treatment.effectDelayHours > 0 ? " after about \(treatment.effectDelayHours)h" : ""
        return "Approximately \(param) \(sign)\(format(treatment.expectedDelta))\(delay) from this application"
    }

    // MARK: - Focused Checks (§1B)

    /// Pending and completed focused Checks in their own representation — never as chemical products.
    static func focusedChecksSection(
        allTreatments: [Treatment],
        test: PoolTest,
        recentHistory: [PoolTest],
        config: PoolConfiguration,
        evaluationDate: Date = Date()
    ) -> String {
        let checks = allTreatments.filter { $0.isFocusedCheckStep }.sorted { $0.sortOrder < $1.sortOrder }
        guard !checks.isEmpty else { return "No focused Checks in the active workflow." }

        let engine = TreatmentWorkflowEngine()
        let evaluator = FocusedCheckOutcomeEvaluator()
        let candidateTests = [test] + recentHistory

        return checks.map { check -> String in
            let params = check.checkParameters.isEmpty ? [check.targetParameter] : check.checkParameters
            let parent = check.parentTreatmentID.flatMap { pid in allTreatments.first { $0.id == pid } }
            let parentName = parent?.chemicalName ?? "not linked"

            if check.isCompleted, let resultID = check.checkResultTestID,
               let resultTest = candidateTests.first(where: { $0.id == resultID }) {
                let measured = params.map { p in
                    let o = evaluator.outcome(parameter: p, priorValue: nil,
                                              measuredValue: measuredValue(of: p, in: resultTest),
                                              postCheckTest: resultTest, postCheckTreatments: test.treatments, config: config)
                    let outcome: String
                    switch o.kind {
                    case .resolved: outcome = "returned to operating range"
                    case .noChemicalActionNeeded: outcome = "outside ideal but no chemical correction warranted"
                    default: outcome = "still outside operating range"
                    }
                    return "    - \(o.displayName): \(o.measuredValue.formattedTreatmentAmount) — \(outcome); further correction: \(o.hasFollowUpTreatment ? "generated from the new measurement" : "none")"
                }.joined(separator: "\n")
                let completedAt = check.completedAt.map { Self.promptDateFormatter.string(from: $0) } ?? "unknown"
                return "- \(check.chemicalName) (completed \(completedAt))\n  Parent treatment: \(parentName)\n  Measured result(s):\n\(measured)"
            }

            // Pending / skipped Check
            let state = engine.state(for: check, in: test.treatments, evaluationDate: evaluationDate)
            let stateText: String
            switch state {
            case .completed: stateText = "completed"
            case .skipped: stateText = "skipped/inapplicable"
            case .waiting(let at): stateText = "waiting (available \(Self.promptDateFormatter.string(from: at)))"
            case .current: stateText = "ready now"
            case .upcoming: stateText = "upcoming"
            }
            // Mirror the parent treatment's canonical verification requirement for consistency.
            let required: Bool = {
                if let parent { return ExportVerificationRequirement.resolve(for: parent, test: test, config: config) == .required }
                return check.urgency != .optional
            }()
            return """
            - \(check.chemicalName) (pending)
              Checked parameter(s): \(params.joined(separator: ", "))
              Parent treatment: \(parentName)
              Timing: \(check.actionDescription)
              Workflow state: \(stateText)
              Verification: \(required ? "required" : "discretionary")
              Instructions: \(check.instructions)
              Status: \(statusText(check))
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - Engine deferrals / avoided recommendations (§8)

    /// Engine-derived deferral/suppression signals, read from actual production state (never re-derived
    /// from raw chemistry in the View). Reports the engine's active repeat-suppression wait windows
    /// (`doNotRepeatBefore`). Monitoring/wait *advisories* the engine emitted are `.advisory` treatments
    /// and are reported in the Watchlist / Monitoring section. Focused Checks are never included.
    static func engineDeferralsSection(allTreatments: [Treatment], evaluationDate: Date = Date()) -> String {
        var lines: [String] = []
        // Watchlist (advisory) items are observations, not treatments — they never enter repeat-suppression.
        for treatment in allTreatments where !treatment.isFocusedCheckStep && !treatment.isWatchlistItem {
            if let until = treatment.doNotRepeatBefore, until > evaluationDate {
                let param = displayParameterName(treatment.expectedEffectParameter.isEmpty ? treatment.targetParameter : treatment.expectedEffectParameter)
                lines.append("- Repeat \(param) dosing is deferred until \(Self.promptDateFormatter.string(from: until)) — a recent \(treatment.chemicalName) dose is still in its wait/retest window (engine repeat-suppression active).")
            }
        }
        return lines.isEmpty
            ? "No active engine repeat-suppression windows. (Monitoring and wait advisories, if any, appear under Watchlist / Monitoring.)"
            : lines.joined(separator: "\n")
    }

    private static func statusText(_ treatment: Treatment) -> String {
        if treatment.isCompleted {
            let at = treatment.completedAt.map { " at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
            return "completed\(at)"
        }
        if treatment.isSkipped {
            let at = treatment.skippedAt.map { " at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
            return "skipped\(at)"
        }
        return "pending"
    }

    private static func displayParameterName(_ parameter: String) -> String {
        switch parameter {
        case "freeChlorine": return "FC"
        case "combinedChlorine": return "CC"
        case "pH": return "pH"
        case "totalAlkalinity": return "TA"
        case "calciumHardness": return "CH"
        case "cyanuricAcid": return "CYA"
        case "saltLevel": return "Salt"
        default: return parameter
        }
    }

    private static let promptDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f
    }()

    /// §10 — completed/skipped workflow steps attached to a *prior* test log. Checks are included with
    /// their kind so a historical completion is never mistaken for a current-preference product.
    static func completedOrSkippedStepsSummary(for test: PoolTest) -> String {
        let steps = test.treatments.filter { $0.isCompleted || $0.isSkipped }
        guard !steps.isEmpty else { return "none" }
        return steps.map { step in
            let kind = step.isFocusedCheckStep ? "check" : "treatment"
            return "\(step.chemicalName) (\(kind), \(step.isCompleted ? "completed" : "skipped"))"
        }.joined(separator: ", ")
    }
}

/// "Why This Plan" narrative. Reasons ONLY from real chemical/action treatment steps when discussing
/// treatments; focused Checks are referenced only in explicitly verification-related copy. A focused
/// Check can never become the first treatment, trigger acid/chlorine narrative, produce a chemical
/// expected outcome, or change treatment-empty decisions.
enum WhyThisPlanNarrative {
    static func summaryLines(
        treatmentActions: [Treatment],
        focusedChecks: [Treatment],
        test: PoolTest,
        chlorineDemandScore: Int,
        hasPoolConditions: Bool
    ) -> [String] {
        var lines: [String] = []
        let fcRange = ChemistryEngine().freeChlorineTargetRange(cyanuricAcid: test.cyanuricAcid)

        if treatmentActions.isEmpty {
            if focusedChecks.contains(where: { !$0.isCompleted && !$0.isSkipped }) {
                lines.append("No new chemical treatment is needed right now; a focused Check is pending to confirm the previous correction.")
            } else {
                lines.append("Based on the data logged, your pool does not need an added treatment step right now.")
            }
        } else if test.freeChlorine < fcRange.lowerBound {
            lines.append("Your pool is mostly stable, but free chlorine is below the operating target.")
        } else {
            lines.append("Based on the data logged, this plan prioritizes the items most likely to affect pool safety and comfort.")
        }

        if chlorineDemandScore >= 3 {
            lines.append("Recent logged pool conditions increased expected chlorine demand.")
        } else if !hasPoolConditions {
            lines.append("Pool conditions were not logged, so this plan is based mostly on chemistry and history.")
        }

        if let acid = treatmentActions.first(where: { $0.isAcidTreatment }) {
            lines.append(acid.actionDescription)
        } else if test.totalAlkalinity > 140 && (7.2...7.8).contains(test.pH) {
            lines.append("Your pH is safe, so elevated alkalinity is being monitored instead of treated.")
        }

        return Array(lines.prefix(3))
    }

    static func expectedOutcomes(
        treatmentActions: [Treatment],
        focusedChecks: [Treatment],
        test: PoolTest
    ) -> [String] {
        var outcomes: [String] = []

        if let chlorine = treatmentActions.first(where: { $0.targetParameter == "freeChlorine" && $0.amount > 0 }) {
            outcomes.append("Adding \(chlorine.amount.formattedTreatmentAmount) \(chlorine.unit) of \(chlorine.chemicalName) should raise FC toward the normal target range.")
        }
        if let acid = treatmentActions.first(where: { $0.isAcidTreatment }) {
            outcomes.append("Adding \(acid.amount.formattedTreatmentAmount) \(acid.unit) of \(acid.chemicalName) should move pH toward the conservative target without chasing alkalinity in the same step.")
        }
        if !treatmentActions.contains(where: { $0.isAcidTreatment }) && (7.2...7.8).contains(test.pH) {
            outcomes.append("No acid is recommended because pH is currently safe.")
        }
        // Verification-only narrative may reference a pending focused Check.
        if treatmentActions.isEmpty, focusedChecks.contains(where: { !$0.isCompleted && !$0.isSkipped }) {
            outcomes.append("A focused Check is pending to measure the response before any further correction is calculated.")
        }
        if outcomes.isEmpty {
            outcomes.append("Continue circulation and normal testing so Pool Side can confirm the pool remains stable.")
        }

        return Array(outcomes.prefix(4))
    }
}

/// Canonical verification requirement for a chemical treatment, derived from ChemistryPolicy swim gates
/// and the focused-Check workflow — never from an urgency/CC/visual heuristic (§3).
enum ExportVerificationRequirement {
    case required
    case discretionary
    case none

    var label: String {
        switch self {
        case .required:      return "Required"
        case .discretionary: return "Discretionary"
        case .none:          return "None"
        }
    }

    static func resolve(for treatment: Treatment, test: PoolTest, config: PoolConfiguration) -> ExportVerificationRequirement {
        guard treatment.amount > 0, treatment.urgency != .advisory,
              !treatment.isFocusedCheckStep, !treatment.isWatchlistItem else { return .none }

        // Verification is "required" exactly when the workflow engine would create a focused Check (swim
        // safety, a staged corrective dose, or surface/equipment protection). A recommended optimization on
        // an already-safe pool needs no Check, so its verification is discretionary.
        return TreatmentWorkflowEngine().requiresFocusedCheck(for: treatment, config: config) ? .required : .discretionary
    }
}

struct TreatmentPlanDeveloperRecalculateAction {
    static func canPresent(isRecalculating: Bool) -> Bool {
        #if DEBUG
        !isRecalculating
        #else
        false
        #endif
    }
}

enum TreatmentPlanDeveloperToolMode: String, CaseIterable, Identifiable {
    case recalculate = "Recalculate"
    case jumpAhead = "Jump Ahead"

    var id: String { rawValue }
}

enum TreatmentPlanDeveloperJumpAheadOffset: String, CaseIterable, Identifiable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fifteenMinutes: return "+15 min"
        case .thirtyMinutes: return "+30 min"
        case .oneHour: return "+1 hr"
        case .twoHours: return "+2 hr"
        case .fourHours: return "+4 hr"
        case .eightHours: return "+8 hr"
        }
    }

    var timeInterval: TimeInterval {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        }
    }
}

struct TreatmentPlanDeveloperToolsSheet: View {
    @Binding var selectedMode: TreatmentPlanDeveloperToolMode
    @Binding var selectedJumpAheadOffset: TreatmentPlanDeveloperJumpAheadOffset

    let isRecalculating: Bool
    let onRecalculate: () -> Void
    let onJumpAhead: (TreatmentPlanDeveloperJumpAheadOffset) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Developer tool", selection: $selectedMode) {
                    ForEach(TreatmentPlanDeveloperToolMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Developer tool")

                switch selectedMode {
                case .recalculate:
                    developerToolContent(
                        title: "Recalculate recommendations",
                        body: "Regenerates the score, status, treatment plan, watchlist, timing, and explanation using the latest engine logic. Logged test readings and pool conditions will not change."
                    ) {
                        Button {
                            onRecalculate()
                        } label: {
                            Text("Recalculate")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isRecalculating)
                    }
                case .jumpAhead:
                    developerToolContent(
                        title: "Simulate a later evaluation time",
                        body: "Runs Swimability v2 as though this amount of time has passed. It does not change the test, treatment completion time, phone clock, or saved data."
                    ) {
                        Picker("Jump ahead amount", selection: $selectedJumpAheadOffset) {
                            ForEach(TreatmentPlanDeveloperJumpAheadOffset.allCases) { offset in
                                Text(offset.displayName).tag(offset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Jump ahead amount")

                        Button {
                            onJumpAhead(selectedJumpAheadOffset)
                        } label: {
                            Text("Evaluate \(selectedJumpAheadOffset.displayName)")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Evaluate \(selectedJumpAheadOffset.displayName)")
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PoolColor.sand.ignoresSafeArea())
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
        .presentationDetents([.height(360), .medium])
        .presentationDragIndicator(.visible)
    }

    private func developerToolContent<Content: View>(
        title: String,
        body: String,
        @ViewBuilder controls: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)

                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            controls()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
