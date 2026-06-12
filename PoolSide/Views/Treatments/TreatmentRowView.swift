import SwiftUI

struct TreatmentRowView: View {

    let treatment: Treatment
    var showCheckbox: Bool = true
    var onComplete: (() -> Void)? = nil

    @State private var isExpanded: Bool = false

    var urgencyColor: Color {
        switch treatment.urgency {
        case .immediate:   return PoolColor.statusCritical
        case .recommended: return PoolColor.statusOffRange
        case .optional:    return PoolColor.statusSlight
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 14) {
                // Urgency stripe
                Rectangle()
                    .fill(urgencyColor)
                    .frame(width: 3)
                    .cornerRadius(1.5)

                // Checkbox or completion indicator
                if showCheckbox {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onComplete?()
                        }
                    } label: {
                        Image(systemName: treatment.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(treatment.isCompleted ? PoolColor.statusIdeal : PoolColor.cloudWhite.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: treatment.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(treatment.isCompleted ? PoolColor.statusIdeal : PoolColor.cloudWhite.opacity(0.3))
                }

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(treatment.chemicalName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(treatment.isCompleted ? PoolColor.cloudWhite.opacity(0.5) : PoolColor.cloudWhite)
                            .strikethrough(treatment.isCompleted, color: PoolColor.cloudWhite.opacity(0.3))
                        Spacer()
                        if treatment.amount > 0 {
                            Text("\(formattedAmount) \(treatment.unit)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(PoolColor.sunshine.opacity(treatment.isCompleted ? 0.4 : 1))
                        }
                    }

                    Text(treatment.actionDescription)
                        .font(.caption)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.55))
                        .lineLimit(isExpanded ? nil : 1)

                    if treatment.isCompleted, let date = treatment.completedAt {
                        Text("Completed \(date.relativeDisplay.lowercased())")
                            .font(.caption2)
                            .foregroundStyle(PoolColor.statusIdeal.opacity(0.7))
                    }
                }

                // Expand chevron
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            // Expanded instructions
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().overlay(PoolColor.cloudWhite.opacity(0.08))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.caption)
                            .foregroundStyle(PoolColor.poolTeal)
                            .padding(.top, 1)
                        Text(treatment.instructions)
                            .font(.caption)
                            .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        urgencyPill
                        if treatment.isAIGenerated {
                            aiPill
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.leading, 3) // align with urgency stripe
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var formattedAmount: String {
        treatment.amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", treatment.amount)
            : String(format: "%.1f", treatment.amount)
    }

    private var urgencyPill: some View {
        HStack(spacing: 4) {
            Image(systemName: treatment.urgency == .immediate ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.system(size: 8))
            Text(treatment.urgency.displayName)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(urgencyColor.opacity(0.15), in: Capsule())
        .foregroundStyle(urgencyColor)
    }

    private var aiPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8))
            Text("AI")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(PoolColor.poolTeal.opacity(0.15), in: Capsule())
        .foregroundStyle(PoolColor.poolTeal)
    }
}

// MARK: - Previews

#Preview("Pending — Immediate") {
    TreatmentRowView(
        treatment: Treatment(
            chemicalName: "pH Decreaser (Muriatic Acid)",
            actionDescription: "Lower pH to ideal range (7.2 – 7.6)",
            amount: 1.5,
            unit: "lbs",
            instructions: "Add slowly to deep end of pool while pump runs. Never pre-mix with other chemicals. Retest in 4 hours.",
            urgency: .immediate
        ),
        showCheckbox: true,
        onComplete: {}
    )
    .background(PoolColor.oceanBlue)
    .padding()
    .background(PoolColor.appBackground)
    .preferredColorScheme(.dark)
}

#Preview("Completed") {
    let treatment = Treatment(
        chemicalName: "Alkalinity Increaser (Sodium Bicarbonate)",
        actionDescription: "Raise total alkalinity to 80 – 120 ppm",
        amount: 2,
        unit: "lbs",
        instructions: "Add directly to pool with pump running.",
        urgency: .recommended,
        isCompleted: true,
        completedAt: Date().addingTimeInterval(-3600)
    )
    return TreatmentRowView(treatment: treatment, showCheckbox: false)
        .background(PoolColor.oceanBlue)
        .padding()
        .background(PoolColor.appBackground)
        .preferredColorScheme(.dark)
}
