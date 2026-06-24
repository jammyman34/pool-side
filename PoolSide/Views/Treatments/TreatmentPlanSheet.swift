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

    @State private var toastMessage: ToastMessage? = nil
    @State private var showingPermissionAlert: Bool = false
    @State private var openSwipeTreatmentID: UUID? = nil

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

                        if let assessment = test.aiAssessment, !assessment.isEmpty {
                            assessmentCard(assessment)
                        }

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

    // MARK: - AI Assessment

    private func assessmentCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Assessment", systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.poolTeal)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
                .lineSpacing(3)
        }
        .padding(18)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                RoundedRectangle(cornerRadius: 16)
                    .fill(PoolColor.poolTeal.opacity(0.06))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PoolColor.poolTeal.opacity(0.15), lineWidth: 1)
        )
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

    private var validationPrompt: String {
        let config = viewModel.poolConfig
        let treatmentLines = allTreatments.isEmpty
            ? "No treatments recommended."
            : allTreatments.map { treatment in
                let status = treatment.isCompleted ? "completed" : treatment.isSkipped ? "skipped" : "pending"
                let completed = treatment.completedAt.map { ", completed at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
                let skipped = treatment.skippedAt.map { ", skipped at \(Self.promptDateFormatter.string(from: $0))" } ?? ""
                return "- \(treatment.chemicalName): \(treatment.amount.formatted()) \(treatment.unit), \(status)\(completed)\(skipped). Instructions: \(treatment.instructions)"
            }.joined(separator: "\n")

        return """
        Please review this pool treatment plan for safety and accuracy. Validate the math against the pool volume, check whether recent completed treatments should affect this plan, and flag anything that seems unsafe or unnecessary. Do not assume missing product concentrations.

        Pool Profile:
        - Name: \(config.name)
        - Volume: \(Int(config.volumeGallons).formatted()) gallons
        - Type: \(config.poolType.displayName)
        - Surface: \(config.surfaceType.displayName)
        - Default Testing Method: \(config.testMethod.displayName)
        - Saltwater: \(config.isSaltwater ? "Yes" : "No")
        - Has cover: \(config.hasCover ? "Yes" : "No")
        - Location: \(config.location.isEmpty ? "Not provided" : config.location)

        Current Test:
        - Date: \(Self.promptDateFormatter.string(from: test.date))
        - Testing Method: \(test.testMethod.displayName)
        - Free Chlorine: \(test.freeChlorine.formatted()) ppm
        - Total Chlorine: \(test.totalChlorine.formatted()) ppm
        - pH: \(test.pH.formatted())
        - Total Alkalinity: \(test.totalAlkalinity.formatted()) ppm
        - Cyanuric Acid: \(test.cyanuricAcid.formatted()) ppm
        - Calcium Hardness: \(test.calciumHardness.formatted()) ppm
        - Notes: \(test.notes.isEmpty ? "None" : test.notes)
        - Positive signs: \(positiveIndicatorList(for: test))
        - Issues noted: \(issueIndicatorList(for: test))

        Proposed Plan:
        \(treatmentLines)

        App Assessment:
        \(test.aiAssessment ?? "None")
        """
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
