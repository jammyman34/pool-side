import SwiftUI
import SwiftData
import UserNotifications

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

    private var allTreatments: [Treatment] {
        test.treatments.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var pendingTreatments: [Treatment] {
        allTreatments.filter { !$0.isCompleted }
    }

    private var completedTreatments: [Treatment] {
        allTreatments.filter { $0.isCompleted }
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

                    VStack(alignment: .leading, spacing: 24) {
                        if allTreatments.isEmpty {
                            emptyState
                        } else {
                            if !pendingTreatments.isEmpty {
                                sectionHeader("To Do", count: pendingTreatments.count)
                                VStack(spacing: 12) {
                                    ForEach(pendingTreatments, id: \.id) { treatment in
                                        TreatmentCardView(treatment: treatment) { t in
                                            await completeTreatment(t)
                                        }
                                    }
                                }
                            }

                            if !completedTreatments.isEmpty {
                                sectionHeader("Completed", count: completedTreatments.count)
                                VStack(spacing: 12) {
                                    ForEach(completedTreatments, id: \.id) { treatment in
                                        TreatmentCardView(treatment: treatment) { _ in }
                                    }
                                }
                            }
                        }

                        if let assessment = test.aiAssessment, !assessment.isEmpty {
                            assessmentCard(assessment)
                        }
                    }
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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
        .background(PoolColor.poolTeal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(PoolColor.poolTeal.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Complete Treatment

    @MainActor
    private func completeTreatment(_ treatment: Treatment) async {
        let minutesToWait = treatment.minutesBeforeNext

        // Request permission before scheduling the first timed notification
        if minutesToWait > 0 && !NotificationService.shared.isAuthorized {
            showingPermissionAlert = true
            // Still mark complete even if they deny — we just won't schedule
        }

        // Mark complete
        viewModel.completeTreatment(treatment)
        do {
            try modelContext.save()
        } catch {
            viewModel.lastError = error.localizedDescription
        }

        // Find next pending step
        let nextPending = test.treatments
            .filter { !$0.isCompleted }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first

        if minutesToWait > 0, let next = nextPending {
            if NotificationService.shared.isAuthorized {
                await NotificationService.shared.scheduleNextStepReminder(
                    nextTreatmentName: next.chemicalName,
                    afterMinutes: minutesToWait
                )
            }
            let label = NotificationService.waitLabel(minutes: minutesToWait)
            toastMessage = ToastMessage.notificationSet(label: label)
        } else {
            toastMessage = ToastMessage.treatmentComplete()
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
