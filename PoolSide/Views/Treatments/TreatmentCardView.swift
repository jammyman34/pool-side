import SwiftUI
import SwiftData

struct TreatmentCardView: View {

    var treatment: Treatment
    var onComplete: @MainActor (Treatment) async -> Void

    @State private var expanded: Bool = false
    @State private var isCompleting: Bool = false

    private var urgencyColor: Color {
        switch treatment.urgency {
        case .immediate:   return PoolColor.statusCritical
        case .recommended: return PoolColor.statusOffRange
        case .optional:    return PoolColor.statusSlight
        }
    }

    private var urgencyLabel: String { treatment.urgency.displayName }

    /// e.g. "2.5 lbs" — suppresses "0 " when amount is zero
    private var amountString: String {
        let amt = treatment.amount
        let unit = treatment.unit
        guard amt > 0 else { return "" }
        let formatted = amt == amt.rounded() ? "\(Int(amt))" : String(format: "%.2g", amt)
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    var body: some View {
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
                        .foregroundStyle(treatment.isCompleted ? PoolColor.secondaryText : PoolColor.primaryText)
                        .strikethrough(treatment.isCompleted, color: PoolColor.secondaryText)

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
                    guard !treatment.isCompleted, !isCompleting else { return }
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
                .disabled(treatment.isCompleted)
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
        .shadow(color: .black.opacity(treatment.isCompleted ? 0.02 : 0.06), radius: 8, y: 2)
        .opacity(treatment.isCompleted ? 0.65 : 1)
    }

    private var waitLabel: String? {
        guard treatment.minutesBeforeNext > 0, !treatment.isCompleted else { return nil }
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
        onComplete: { _ in }
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
    return TreatmentCardView(treatment: treatment, onComplete: { _ in })
        .padding()
        .background(PoolColor.appBackground)
}
