import SwiftUI
import SwiftData

struct TreatmentCardView: View {

    enum Presentation {
        case card
        case row
    }

    var treatment: Treatment
    var allowsActions: Bool = true
    var presentation: Presentation = .card
    var showsDivider: Bool = true
    var onComplete: @MainActor (Treatment) async -> Void
    var onMarkIncomplete: @MainActor (Treatment) async -> Void
    var onSkip: @MainActor (Treatment) async -> Void
    var onRestore: @MainActor (Treatment) async -> Void
    @Binding var openSwipeTreatmentID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(PoolViewModel.self) private var viewModel

    @State private var expanded: Bool = false
    @State private var isCompleting: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var isSkipOpen: Bool = false
    @State private var isRestoreOpen: Bool = false
    @State private var showingProductPicker: Bool = false

    private let actionWidth: CGFloat = 92

    private var swappableCategory: ChemicalProductCategory? {
        guard allowsActions, !treatment.isCompleted, !treatment.isSkipped else { return nil }
        return treatment.productCategory
    }

    private var urgencyColor: Color {
        if treatment.isSkipped { return PoolColor.statusSlight }
        switch treatment.urgency {
        case .immediate:   return PoolColor.statusCritical
        case .recommended: return PoolColor.statusOffRange
        case .optional:    return PoolColor.statusSlight
        case .advisory:    return PoolColor.secondaryText
        }
    }

    private var urgencyLabel: String {
        treatment.isSkipped ? "Skipped" : treatment.urgency.displayName
    }

    private var cardOffset: CGFloat {
        guard allowsActions else { return 0 }
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
        let formatted = amt.formattedTreatmentAmount
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    var body: some View {
        ZStack {
            if allowsActions && treatment.isSkipped && cardOffset > 0 {
                restoreAction
                    .zIndex(1)
            } else if allowsActions && !treatment.isCompleted && cardOffset < 0 {
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
                .conditionalSimultaneousGesture(skipGesture, enabled: allowsActions && !treatment.isCompleted)
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
        .sheet(isPresented: $showingProductPicker) {
            if let category = swappableCategory {
                ChemicalProductPickerSheet(
                    category: category,
                    initialSelection: treatment.chemicalName,
                    onApply: { newSelection, saveAsDefault in
                        applyProductSwap(category: category, selection: newSelection, saveAsDefault: saveAsDefault)
                    }
                )
            }
        }
    }

    private var usesCardChrome: Bool {
        presentation == .card
    }

    @ViewBuilder
    private var chemicalNameView: some View {
        if let category = swappableCategory {
            Button {
                if isSkipOpen || isRestoreOpen {
                    closeSwipeActions(clearOpenTreatment: true)
                }
                showingProductPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(treatment.chemicalName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.primaryText)
                        .multilineTextAlignment(.leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Switch to a different \(category.sheetTitle.lowercased()) product")
        } else {
            Text(treatment.chemicalName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(treatment.isCompleted || treatment.isSkipped ? PoolColor.secondaryText : PoolColor.primaryText)
                .strikethrough(treatment.isSkipped, color: PoolColor.secondaryText)
        }
    }

    private func applyProductSwap(
        category: ChemicalProductCategory,
        selection: String,
        saveAsDefault: Bool
    ) {
        // Don't propose a recomputed template against the saved config if the user only
        // wants this swap one-time — derive against an updated copy for the recompute math,
        // and only persist if saveAsDefault is on.
        let updatedConfig = category.configApplying(selection: selection, to: viewModel.poolConfig)
        guard let test = treatment.poolTest else { return }

        let engine = ChemistryEngine()
        guard let newTemplate = engine.proposedTreatmentTemplate(
            forTargetParameter: treatment.targetParameter,
            test: test,
            config: updatedConfig
        ) else { return }

        treatment.chemicalName = newTemplate.chemicalName
        treatment.amount = newTemplate.amount
        treatment.unit = newTemplate.unit
        treatment.instructions = newTemplate.instructions
        treatment.actionDescription = newTemplate.actionDescription

        try? modelContext.save()

        if saveAsDefault {
            viewModel.saveConfig(updatedConfig)
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
                    chemicalNameView

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
                        Label(waitLabel, systemImage: "clock.badge.exclamationmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PoolColor.poolTeal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(PoolColor.poolTeal.opacity(0.08), in: Capsule())
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Checkbox — top-right
                Button {
                    guard allowsActions, !treatment.isSkipped, !isCompleting else { return }
                    isCompleting = true
                    Task {
                        if treatment.isCompleted {
                            await onMarkIncomplete(treatment)
                        } else {
                            await onComplete(treatment)
                        }
                        isCompleting = false
                    }
                } label: {
                    if allowsActions {
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
                }
                .disabled(treatment.isSkipped)
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
                    .padding(.horizontal, 42)
                    .padding(.vertical, 10)
                }

                if expanded {
                    Text(treatment.instructions)
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                        .padding(.horizontal, 42)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showsDivider {
                    Rectangle()
                        .fill(PoolColor.poolTeal.opacity(0.3))
                        .frame(height: 1)
                        .padding(.horizontal, 18)
                }
            }
        }
        .background(usesCardChrome ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(usesCardChrome && !allowsActions ? PoolColor.poolTeal.opacity(0.18) : Color.clear, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(usesCardChrome ? (treatment.isCompleted || treatment.isSkipped ? 0.02 : 0.06) : 0),
            radius: usesCardChrome ? 8 : 0,
            y: usesCardChrome ? 2 : 0
        )
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
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard allowsActions else { return }
                guard !treatment.isCompleted else { return }
                guard isHorizontalSwipe(value.translation) else { return }

                if treatment.isSkipped {
                    let baseOffset = isRestoreOpen ? actionWidth : 0
                    dragOffset = max(0, min(actionWidth, baseOffset + value.translation.width))
                } else {
                    let baseOffset = isSkipOpen ? -actionWidth : 0
                    dragOffset = min(0, max(-actionWidth, baseOffset + value.translation.width))
                }
            }
            .onEnded { value in
                guard allowsActions else {
                    dragOffset = 0
                    return
                }
                guard !treatment.isCompleted else {
                    dragOffset = 0
                    return
                }
                guard isHorizontalSwipe(value.translation) else {
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

    private func isHorizontalSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.35
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
        guard allowsActions, treatment.minutesBeforeNext > 0, !treatment.isCompleted, !treatment.isSkipped else { return nil }
        return "Retest in \(NotificationService.waitLabel(minutes: treatment.minutesBeforeNext)) before next step"
    }
}

// MARK: - Product Picker Sheet

struct ChemicalProductPickerSheet: View {

    let category: ChemicalProductCategory
    let initialSelection: String
    let onApply: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var saveAsDefault: Bool = false
    @State private var sheetHeight: CGFloat = 320

    init(
        category: ChemicalProductCategory,
        initialSelection: String,
        onApply: @escaping (String, Bool) -> Void
    ) {
        self.category = category
        self.initialSelection = initialSelection
        self.onApply = onApply
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Product")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.primaryText)

                    HStack {
                        Picker("Product", selection: $selection) {
                            ForEach(category.optionDisplayNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PoolColor.poolTeal)
                        .labelsHidden()

                        Spacer(minLength: 0)
                    }
                }

                Toggle("Use this as my default for future logs", isOn: $saveAsDefault.animation())
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                    .tint(PoolColor.poolTeal)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChemicalProductSheetHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(category.sheetTitle)
                        .font(.headline)
                        .foregroundStyle(PoolColor.primaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onApply(selection, saveAsDefault)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
        .onPreferenceChange(ChemicalProductSheetHeightKey.self) { value in
            // Include nav bar (~56pt) when sizing the sheet.
            sheetHeight = value + 56
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PoolColor.sand)
    }
}

private struct ChemicalProductSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    @ViewBuilder
    func conditionalSimultaneousGesture<G: Gesture>(_ gesture: G, enabled: Bool) -> some View {
        if enabled {
            simultaneousGesture(gesture)
        } else {
            self
        }
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
        onMarkIncomplete: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        openSwipeTreatmentID: .constant(nil)
    )
    .padding()
    .background(PoolColor.appBackground)
    .environment(PoolViewModel())
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
        onMarkIncomplete: { _ in },
        onSkip: { _ in },
        onRestore: { _ in },
        openSwipeTreatmentID: .constant(nil)
    )
        .padding()
        .background(PoolColor.appBackground)
        .environment(PoolViewModel())
}
