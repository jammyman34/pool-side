import SwiftUI
import SwiftData

struct TreatmentCardView: View {

    var treatment: Treatment
    var onComplete: @MainActor (Treatment) async -> Void
    var onSkip: @MainActor (Treatment) async -> Void
    var onRestore: @MainActor (Treatment) async -> Void
    @Binding var openSwipeTreatmentID: UUID?

    @State private var expanded: Bool = false
    @State private var isCompleting: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isSkipOpen: Bool = false
    @State private var isRestoreOpen: Bool = false

    private let actionWidth: CGFloat = 92

    private var urgencyColor: Color {
        if treatment.isSkipped { return PoolColor.statusSlight }
        switch treatment.urgency {
        case .immediate:   return PoolColor.statusCritical
        case .recommended: return PoolColor.statusOffRange
        case .optional:    return PoolColor.statusSlight
        }
    }

    private var urgencyLabel: String {
        treatment.isSkipped ? "Skipped" : treatment.urgency.displayName
    }

    private var cardOffset: CGFloat {
        if dragOffset < 0 { return max(dragOffset, -actionWidth) }
        if dragOffset > 0 { return min(dragOffset, actionWidth) }
        if isSkipOpen { return -actionWidth }
        return isRestoreOpen ? actionWidth : 0
    }

    /// e.g. "2.5 lbs" — suppresses "0 " when amount is zero
    private var amountString: String {
        let amt = treatment.amount
        let unit = treatment.unit
        guard amt > 0 else { return "" }
        let formatted = amt == amt.rounded() ? "\(Int(amt))" : String(format: "%.2g", amt)
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    var body: some View {
        ZStack {
            if treatment.isSkipped && cardOffset > 0 {
                restoreAction
                    .zIndex(1)
            } else if !treatment.isCompleted && cardOffset < 0 {
                skipAction
                    .zIndex(1)
            }

            cardContent
                .offset(x: cardOffset)
                .zIndex(0)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSkipOpen || isRestoreOpen {
                        closeSwipeActions(clearOpenTreatment: true)
                    }
                }
                .gesture(skipGesture)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSkipOpen)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isRestoreOpen)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: dragOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: openSwipeTreatmentID) { _, newValue in
            if newValue != treatment.id {
                closeSwipeActions(clearOpenTreatment: false)
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 14) {
                // Urgency dot
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)

                // Name + amount + urgency badge
                VStack(alignment: .leading, spacing: 4) {
                    Text(treatment.chemicalName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(treatment.isCompleted || treatment.isSkipped ? PoolColor.secondaryText : PoolColor.primaryText)
                        .strikethrough(treatment.isCompleted || treatment.isSkipped, color: PoolColor.secondaryText)

                    if !amountString.isEmpty {
                        Text(amountString)
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                    }

                    Text(urgencyLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(urgencyColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(urgencyColor.opacity(0.12), in: Capsule())

                    if let waitLabel {
                        Label(waitLabel, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(PoolColor.secondaryText)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                // Checkbox — top-right
                Button {
                    guard !treatment.isCompleted, !treatment.isSkipped, !isCompleting else { return }
                    isCompleting = true
                    Task {
                        await onComplete(treatment)
                        isCompleting = false
                    }
                } label: {
                    ZStack {
                        if isCompleting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 26, height: 26)
                        } else if treatment.isCompleted {
                            Circle()
                                .fill(PoolColor.statusIdeal)
                                .frame(width: 26, height: 26)
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .stroke(PoolColor.divider, lineWidth: 2)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
                .disabled(treatment.isCompleted || treatment.isSkipped)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, treatment.instructions.isEmpty ? 16 : 10)

            // Action description
            if !treatment.actionDescription.isEmpty {
                Text(treatment.actionDescription)
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                    .padding(.horizontal, 42) // align with name (after dot + spacing)
                    .padding(.bottom, 10)
            }

            // "How to apply" expandable
            if !treatment.instructions.isEmpty {
                Divider()
                    .overlay(PoolColor.divider)
                    .padding(.horizontal, 18)

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("How to apply")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(PoolColor.poolTeal)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(PoolColor.poolTeal)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                }

                if expanded {
                    Text(treatment.instructions)
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(treatment.isCompleted || treatment.isSkipped ? 0.02 : 0.06), radius: 8, y: 2)
        .opacity(treatment.isCompleted ? 0.65 : 1)
    }

    private var skipAction: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                Task {
                    await onSkip(treatment)
                    isSkipOpen = false
                    openSwipeTreatmentID = nil
                    dragOffset = 0
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "slash.circle")
                        .font(.headline)
                    Text("Skip")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(PoolColor.statusSlight)
            }
        }
    }

    private var restoreAction: some View {
        HStack(spacing: 0) {
            Button {
                Task {
                    await onRestore(treatment)
                    isRestoreOpen = false
                    openSwipeTreatmentID = nil
                    dragOffset = 0
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left.circle")
                        .font(.headline)
                    Text("Restore")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(PoolColor.poolTeal)
            }
            Spacer()
        }
    }

    private var skipGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !treatment.isCompleted else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                if treatment.isSkipped {
                    let baseOffset = isRestoreOpen ? actionWidth : 0
                    dragOffset = max(0, min(actionWidth, baseOffset + value.translation.width))
                } else {
                    let baseOffset = isSkipOpen ? -actionWidth : 0
                    dragOffset = min(0, max(-actionWidth, baseOffset + value.translation.width))
                }
            }
            .onEnded { value in
                guard !treatment.isCompleted else {
                    dragOffset = 0
                    return
                }
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    dragOffset = 0
                    return
                }

                if treatment.isSkipped {
                    isRestoreOpen = cardOffset > actionWidth * 0.45
                    openSwipeTreatmentID = isRestoreOpen ? treatment.id : nil
                } else {
                    isSkipOpen = cardOffset < -(actionWidth * 0.45)
                    openSwipeTreatmentID = isSkipOpen ? treatment.id : nil
                }
                dragOffset = 0
            }
    }

    private func closeSwipeActions(clearOpenTreatment: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isSkipOpen = false
            isRestoreOpen = false
            if clearOpenTreatment {
                openSwipeTreatmentID = nil
            }
            dragOffset = 0
        }
    }

    private var waitLabel: String? {
        guard treatment.minutesBeforeNext > 0, !treatment.isCompleted, !treatment.isSkipped else { return nil }
        return "Wait \(NotificationService.waitLabel(minutes: treatment.minutesBeforeNext)) before next step"
    }
}

// MARK: - Previews

#Preview("Pending — Immediate") {
    TreatmentCardView(
        treatment: Treatment(
            chemicalName: "pH Decreaser (Muriatic Acid)",
            actionDescription: "Lower pH to ideal range (7.2 – 7.6)",
            amount: 1.5,
            unit: "lbs",
            instructions: "Add slowly to the deep end of the pool while pump runs. Never pre-mix with other chemicals. Retest in 4 hours.",
            urgency: .immediate
        ),
        onComplete: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        openSwipeTreatmentID: .constant(nil)
    )
    .padding()
    .background(PoolColor.appBackground)
}

#Preview("Completed") {
    let treatment = Treatment(
        chemicalName: "Alkalinity Increaser",
        actionDescription: "Raise total alkalinity to 80 – 120 ppm",
        amount: 2,
        unit: "lbs",
        instructions: "Add directly to pool with pump running.",
        urgency: .recommended,
        isCompleted: true,
        completedAt: Date().addingTimeInterval(-3600)
    )
    TreatmentCardView(
        treatment: treatment,
        onComplete: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        openSwipeTreatmentID: .constant(nil)
    )
        .padding()
        .background(PoolColor.appBackground)
}
