import SwiftUI
import SwiftData

struct TreatmentCardView: View {

    enum Presentation {
        case card
        case row
    }

    var treatment: Treatment
    var nextActionableTreatment: Treatment? = nil
    var allowsActions: Bool = true
    var presentation: Presentation = .card
    var showsDivider: Bool = true
    /// Corner radius + optional border for the swipe row's content card. Set by the workflow so the card
    /// meets its Skip/Restore action flush when swiped.
    var rowCornerRadius: CGFloat = 16
    var rowBorderColor: Color? = nil
    var onComplete: @MainActor (Treatment) async -> Void
    var onMarkIncomplete: @MainActor (Treatment) async -> Void
    var onSkip: @MainActor (Treatment) async -> Void
    var onRestore: @MainActor (Treatment) async -> Void
    @Binding var openSwipeTreatmentID: UUID?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(PoolViewModel.self) private var viewModel

    @State private var expanded: Bool = false
    @State private var isCompleting: Bool = false
    @State private var showingProductPicker: Bool = false

    private var swappableCategory: ChemicalProductCategory? {
        guard allowsActions, !treatment.isCompleted, !treatment.isSkipped else { return nil }
        return treatment.productCategory
    }

    private var urgencyColor: Color {
        if treatment.isSkipped { return PoolColor.statusSlight }
        return PoolColor.urgencyStatusColor(treatment.urgency)
    }

    /// The test parameter this treatment affects, mapped to the Test Log's icon + color language.
    /// nil for non-chemical targets (e.g. visual indicators, cover), which use a neutral fallback glyph.
    private var parameterField: ChemicalField? {
        ChemicalField(rawValue: treatment.targetParameter)
    }

    /// Leading icon showing which parameter the treatment moves. Intentionally NOT colored by status —
    /// it uses the same fixed per-parameter color as the Test Log page so the visual vocabulary matches.
    @ViewBuilder
    private var parameterIcon: some View {
        let size: CGFloat = 30
        if let field = parameterField {
            ChemicalIcon(field: field, size: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(PoolColor.appBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(PoolColor.divider, lineWidth: 1)
                    )
                Image(systemName: fallbackParameterSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(PoolColor.secondaryText)
            }
            .frame(width: size, height: size)
        }
    }

    private var fallbackParameterSymbol: String {
        switch treatment.targetParameter {
        case "visualIndicators": return "eye"
        case "cover": return "sun.max"
        default: return "sparkles"
        }
    }

    private var urgencyLabel: String {
        treatment.isSkipped ? "Skipped" : treatment.urgency.displayName
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
        SwipeableSkipRow(
            itemID: treatment.id,
            isSkipped: treatment.isSkipped,
            gestureEnabled: allowsActions && !treatment.isCompleted,
            cornerRadius: rowCornerRadius,
            contentBorderColor: rowBorderColor,
            openSwipeID: $openSwipeTreatmentID,
            onSkip: { await onSkip(treatment) },
            onRestore: { await onRestore(treatment) }
        ) {
            cardContent
        }
        .sheet(isPresented: $showingProductPicker) {
            if let category = swappableCategory {
                ChemicalProductPickerSheet(
                    category: category,
                    initialSelection: treatment.productIdentifier.flatMap(ChemicalProductID.init(rawValue:)) ?? category.currentSelection(from: viewModel.poolConfig),
                    isSaltwater: viewModel.poolConfig.isSaltwater,
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
                openSwipeTreatmentID = nil   // close any open swipe row
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
        selection: ChemicalProductID,
        saveAsDefault: Bool
    ) {
        // Don't propose a recomputed template against the saved config if the user only
        // wants this swap one-time — derive against an updated copy for the recompute math,
        // and only persist if saveAsDefault is on.
        let updatedConfig = category.configApplying(selection: selection, to: viewModel.poolConfig)
        guard let test = treatment.poolTest else { return }

        let engine = ChemistryEngine()
        let proposedTemplate = engine.proposedTreatmentTemplate(
            forTargetParameter: treatment.targetParameter,
            test: test,
            config: updatedConfig
        )
        let repricedTemplate = engine.repricedTreatmentTemplate(
            from: treatment,
            test: test,
            productID: selection,
            config: updatedConfig
        )
        guard let newTemplate = repricedTemplate ?? proposedTemplate else { return }

        let previousProductIdentifier = treatment.productIdentifier
        let previousChemicalName = treatment.chemicalName
        treatment.chemicalName = newTemplate.chemicalName
        treatment.amount = newTemplate.amount
        treatment.unit = newTemplate.unit
        treatment.instructions = newTemplate.instructions
        treatment.actionDescription = newTemplate.actionDescription
        treatment.expectedDelta = newTemplate.expectedDelta
        treatment.expectedEffectParameter = newTemplate.expectedEffectParameter
        treatment.effectDelayHours = newTemplate.effectDelayHours
        treatment.effectDurationHours = newTemplate.effectDurationHours
        treatment.productIdentifier = newTemplate.productID?.rawValue
        treatment.globalPreferenceIdentifier = newTemplate.globalPreferenceProductID?.rawValue
        treatment.calculatedDoseBeforeCap = newTemplate.calculatedDoseBeforeCap
        treatment.calculatedDoseBeforeCapUnit = newTemplate.calculatedDoseBeforeCapUnit
        treatment.wasDoseCapped = newTemplate.wasDoseCapped

        try? modelContext.save()

        if previousProductIdentifier != treatment.productIdentifier || previousChemicalName != treatment.chemicalName {
            Task { @MainActor in
                _ = await viewModel.refreshTreatmentNotificationsAfterProductChange(
                    treatment,
                    in: [test],
                    modelContext: modelContext
                )
            }
        }

        if saveAsDefault {
            viewModel.updateConfig { config in
                config = category.configApplying(selection: selection, to: config)
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 14) {
                // Parameter icon — shows which test reading this treatment affects.
                parameterIcon
                    .padding(.top, 1)

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
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.9)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(PoolColor.poolTeal.opacity(0.08), in: Capsule())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
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

    private var waitLabel: String? {
        guard allowsActions, !treatment.isCompleted, !treatment.isSkipped else { return nil }
        return TreatmentTimingGuidance.cardTip(
            for: treatment,
            nextActionableTreatment: nextActionableTreatment,
            requiresVerificationBeforeSwimming: requiresVerificationBeforeSwimming
        )
    }

    private var requiresVerificationBeforeSwimming: Bool {
        TreatmentTimingGuidance.requiresVerificationBeforeSwimming(for: treatment)
    }
}

// MARK: - Shared swipe-to-skip / swipe-to-restore container

/// The single swipe interaction used by both treatment cards and focused-Check cards:
/// right-to-left reveals Skip; left-to-right on a skipped row reveals Restore. VoiceOver users get
/// equivalent accessibility actions. Only one row's actions are open at a time via `openSwipeID`.
struct SwipeableSkipRow<Content: View>: View {
    let itemID: UUID
    let isSkipped: Bool
    /// Enable the gesture (typically `allowsActions && !isCompleted`).
    let gestureEnabled: Bool
    let cornerRadius: CGFloat
    let skipAccessibilityLabel: String
    let restoreAccessibilityLabel: String
    /// Optional stroke drawn around the content card only (not the revealed action). When swiped, the edge
    /// facing the action becomes square so the card and the action button meet flush.
    let contentBorderColor: Color?
    let contentBorderWidth: CGFloat
    let onSkip: @MainActor () async -> Void
    let onRestore: @MainActor () async -> Void
    @Binding var openSwipeID: UUID?
    private let content: Content

    @State private var dragOffset: CGFloat = 0
    @State private var isSkipOpen = false
    @State private var isRestoreOpen = false
    @State private var rowWidth: CGFloat = 0
    private let actionWidth: CGFloat = 92

    init(
        itemID: UUID,
        isSkipped: Bool,
        gestureEnabled: Bool,
        cornerRadius: CGFloat = 16,
        skipAccessibilityLabel: String = "Skip",
        restoreAccessibilityLabel: String = "Restore",
        contentBorderColor: Color? = nil,
        contentBorderWidth: CGFloat = 1,
        initiallyOpen: Bool = false,
        openSwipeID: Binding<UUID?>,
        onSkip: @escaping @MainActor () async -> Void,
        onRestore: @escaping @MainActor () async -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.itemID = itemID
        self.isSkipped = isSkipped
        self.gestureEnabled = gestureEnabled
        self.cornerRadius = cornerRadius
        self.skipAccessibilityLabel = skipAccessibilityLabel
        self.restoreAccessibilityLabel = restoreAccessibilityLabel
        self.contentBorderColor = contentBorderColor
        self.contentBorderWidth = contentBorderWidth
        self._openSwipeID = openSwipeID
        self._isSkipOpen = State(initialValue: initiallyOpen && !isSkipped)
        self._isRestoreOpen = State(initialValue: initiallyOpen && isSkipped)
        self.onSkip = onSkip
        self.onRestore = onRestore
        self.content = content()
    }

    private var cardOffset: CGFloat {
        guard gestureEnabled else { return 0 }
        if dragOffset < 0 { return max(dragOffset, -actionWidth) }
        if dragOffset > 0 { return min(dragOffset, actionWidth) }
        if isSkipOpen { return -actionWidth }
        return isRestoreOpen ? actionWidth : 0
    }

    /// The action is revealed on the trailing side (Skip) when the card slides left, and on the leading side
    /// (Restore) when it slides right. Drives the content card's per-corner rounding so the edge meeting the
    /// action goes square while the outer edge stays rounded.
    private enum RevealSide { case none, trailing, leading }
    private var revealSide: RevealSide {
        if cardOffset < 0 { return .trailing }
        if cardOffset > 0 { return .leading }
        return .none
    }
    /// How much of the action is currently exposed (0…actionWidth).
    private var revealAmount: CGFloat { min(abs(cardOffset), actionWidth) }

    /// The content card's shape: rounded on its outer edge, a hard square on the edge that meets the
    /// revealed action.
    private var contentShape: UnevenRoundedRectangle {
        let leading: CGFloat = revealSide == .leading ? 0 : cornerRadius
        let trailing: CGFloat = revealSide == .trailing ? 0 : cornerRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing
        )
    }

    /// A single view carrying the caller's content, its fill, its border, and its clip. Its visible width is
    /// driven by `revealAmount` (it shrinks from the action side), so the card, its border, and its rounded
    /// corners are always one unit and can never drift apart from each other while swiping.
    private var contentCard: some View {
        content
            .frame(width: rowWidth > 0 ? rowWidth : nil, alignment: .leading)
            .frame(
                width: rowWidth > 0 ? max(rowWidth - revealAmount, 0) : nil,
                alignment: revealSide == .leading ? .trailing : .leading
            )
            .clipShape(contentShape)
            .overlay {
                if let contentBorderColor {
                    contentShape.stroke(contentBorderColor, lineWidth: contentBorderWidth)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSkipOpen || isRestoreOpen { close(clear: true) }
            }
            .conditionalSimultaneousGesture(gesture, enabled: gestureEnabled)
    }

    var body: some View {
        ZStack(alignment: revealSide == .leading ? .trailing : .leading) {
            if gestureEnabled && isSkipped && cardOffset > 0 {
                restoreAction
            } else if gestureEnabled && !isSkipped && cardOffset < 0 {
                skipAction
            }

            contentCard
        }
        .frame(maxWidth: .infinity)
        // Size the row to the content's height. Without this, the action's `maxHeight: .infinity` is greedy
        // and, in an unconstrained vertical context (a ScrollView), lets the row grow taller than the card —
        // making the action button extend past the card's top and bottom.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SwipeRowWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SwipeRowWidthKey.self) { rowWidth = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isSkipOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isRestoreOpen)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: dragOffset)
        .onChange(of: openSwipeID) { _, newValue in
            if newValue != itemID { close(clear: false) }
        }
        .accessibilityActions {
            if gestureEnabled && !isSkipped {
                Button(skipAccessibilityLabel) { Task { await performSkip() } }
            }
            if gestureEnabled && isSkipped {
                Button(restoreAccessibilityLabel) { Task { await performRestore() } }
            }
        }
    }

    @MainActor private func performSkip() async {
        await onSkip(); isSkipOpen = false; openSwipeID = nil; dragOffset = 0
    }

    @MainActor private func performRestore() async {
        await onRestore(); isRestoreOpen = false; openSwipeID = nil; dragOffset = 0
    }

    // The action's outer corners are rounded and the corner meeting the card content is a hard square, so
    // the button and card abut flush (independent of the outer clip).
    private var skipAction: some View {
        HStack(spacing: 0) {
            Spacer()
            Button { Task { await performSkip() } } label: {
                VStack(spacing: 4) {
                    Image(systemName: "slash.circle").font(.headline)
                    Text("Skip").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(
                    PoolColor.statusSlight,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: cornerRadius,
                        topTrailingRadius: cornerRadius
                    )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var restoreAction: some View {
        HStack(spacing: 0) {
            Button { Task { await performRestore() } } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left.circle").font(.headline)
                    Text("Restore").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(
                    PoolColor.poolTeal,
                    in: UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius,
                        bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                )
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard gestureEnabled, isHorizontalSwipe(value.translation) else { return }
                if isSkipped {
                    let baseOffset = isRestoreOpen ? actionWidth : 0
                    dragOffset = max(0, min(actionWidth, baseOffset + value.translation.width))
                } else {
                    let baseOffset = isSkipOpen ? -actionWidth : 0
                    dragOffset = min(0, max(-actionWidth, baseOffset + value.translation.width))
                }
            }
            .onEnded { value in
                guard gestureEnabled, isHorizontalSwipe(value.translation) else { dragOffset = 0; return }
                if isSkipped {
                    isRestoreOpen = cardOffset > actionWidth * 0.45
                    openSwipeID = isRestoreOpen ? itemID : nil
                } else {
                    isSkipOpen = cardOffset < -(actionWidth * 0.45)
                    openSwipeID = isSkipOpen ? itemID : nil
                }
                dragOffset = 0
            }
    }

    private func isHorizontalSwipe(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.35
    }

    private func close(clear: Bool) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            isSkipOpen = false
            isRestoreOpen = false
            if clear { openSwipeID = nil }
            dragOffset = 0
        }
    }
}

private struct SwipeRowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Product Picker Sheet

struct ChemicalProductPickerSheet: View {

    let category: ChemicalProductCategory
    let initialSelection: ChemicalProductID
    let isSaltwater: Bool
    let onApply: (ChemicalProductID, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ChemicalProductID
    @State private var saveAsDefault: Bool = false
    @State private var sheetHeight: CGFloat = 320

    init(
        category: ChemicalProductCategory,
        initialSelection: ChemicalProductID,
        isSaltwater: Bool,
        onApply: @escaping (ChemicalProductID, Bool) -> Void
    ) {
        self.category = category
        self.initialSelection = initialSelection
        self.isSaltwater = isSaltwater
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
                            ForEach(category.options(isSaltwater: isSaltwater), id: \.self) { productID in
                                Text(productID.displayName)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .tag(productID)
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

#Preview("Swipe open — Skip") {
    let content = VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "testtube.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PoolColor.statusTesting)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 5) {
                Text("Check FC & CC").font(.subheadline.weight(.semibold))
                Text("1 hour after adding chlorine").font(.caption).foregroundStyle(.secondary)
                Text("Ready to check")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(PoolColor.statusTesting.opacity(0.20), in: Capsule())
            }
            Spacer()
            Text("Enter")
                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(PoolColor.poolTeal, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)

        Text("Test FC and CC to confirm chlorine is safe before swimming.")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 58).padding(.bottom, 14)
    }
    .frame(maxWidth: .infinity)
    .background(PoolColor.statusTesting.opacity(0.20))

    return VStack {
        SwipeableSkipRow(
            itemID: UUID(),
            isSkipped: false,
            gestureEnabled: true,
            cornerRadius: 14,
            contentBorderColor: PoolColor.statusTesting,
            initiallyOpen: true,
            openSwipeID: .constant(nil),
            onSkip: {},
            onRestore: {}
        ) {
            content
        }
        Spacer()
    }
    .padding()
    .background(PoolColor.appBackground)
}

#Preview("Swipe open — Restore") {
    let content = VStack(alignment: .leading, spacing: 8) {
        Text("Check FC & CC").font(.subheadline.weight(.semibold))
        Text("1 hour after adding chlorine").font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .frame(maxWidth: .infinity)
    .background(PoolColor.statusTesting.opacity(0.20))

    return VStack {
        SwipeableSkipRow(
            itemID: UUID(),
            isSkipped: true,
            gestureEnabled: true,
            cornerRadius: 14,
            contentBorderColor: PoolColor.statusTesting,
            initiallyOpen: true,
            openSwipeID: .constant(nil),
            onSkip: {},
            onRestore: {}
        ) {
            content
        }
        Spacer()
    }
    .padding()
    .background(PoolColor.appBackground)
}
