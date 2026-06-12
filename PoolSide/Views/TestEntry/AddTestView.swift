import SwiftUI
import SwiftData
import UIKit

struct AddTestView: View {

    /// When non-nil, the view is in "edit" mode for an existing test
    var editingTest: PoolTest? = nil

    init(editingTest: PoolTest? = nil) {
        self.editingTest = editingTest
        _chemicalOrder = State(initialValue: ChemicalField.savedDisplayOrder)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PoolViewModel.self) private var viewModel
    @Query(sort: \PoolTest.date, order: .reverse) private var tests: [PoolTest]

    // MARK: - Form State
    @State private var date: Date = Date()
    @State private var pH: Double = 7.4
    @State private var freeChlorine: Double = 2.0
    @State private var totalChlorine: Double = 2.0
    @State private var totalAlkalinity: Double = 100
    @State private var calciumHardness: Double = 300
    @State private var cyanuricAcid: Double = 40
    @State private var temperature: Double = 78
    @State private var saltLevel: Double = 3000
    @State private var notes: String = ""
    @State private var includeTemperature: Bool = false
    @State private var includeSalt: Bool = false
    @State private var selectedVisualIndicators: Set<String> = []
    @State private var chemicalOrder: [ChemicalField] = ChemicalField.defaultDisplayOrder
    @State private var draggedChemical: ChemicalField? = nil
    @State private var chemicalRowFrames: [ChemicalField: CGRect] = [:]
    @State private var dragStartFrame: CGRect = .zero
    @State private var dragTranslation: CGSize = .zero

    // Post-save
    @State private var savedTest: PoolTest? = nil
    @State private var showingTreatmentPlan: Bool = false
    @State private var isSaving: Bool = false

    private var isEditing: Bool { editingTest != nil }

    private var navTitle: String {
        if editingTest != nil {
            return "Edit Test Log"
        }
        return "Log New Test"
    }

    private var heroTitle: String {
        if let test = editingTest {
            return "\(shortDate(test.date)), \(timeString(test.date)) test results"
        }
        return "test results"
    }

    private var visibleChemicalFields: [ChemicalField] {
        chemicalOrder.filter { field in
            switch field {
            case .temperature:
                return includeTemperature
            case .saltLevel:
                return includeSalt
            default:
                return true
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Teal hero banner
                        heroBanner

                        // Form rows on white card
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(Array(visibleChemicalFields.enumerated()), id: \.element.id) { index, chemical in
                                    chemicalRow(for: chemical)
                                        .opacity(draggedChemical == chemical ? 0.12 : 1)
                                        .background(rowFrameReader(for: chemical))

                                    if index < visibleChemicalFields.count - 1 {
                                        divider
                                    }
                                }

                                divider
                                resetChemicalOrderButton
                            }
                            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: chemicalOrder)

                            if let draggedChemical {
                                chemicalDragPreview(for: draggedChemical, width: dragStartFrame.width)
                                    .offset(
                                        x: dragStartFrame.minX,
                                        y: dragStartFrame.minY + dragTranslation.height
                                    )
                                    .zIndex(10)
                                    .allowsHitTesting(false)
                            }
                        }
                        .coordinateSpace(name: "chemicalList")
                        .onPreferenceChange(ChemicalRowFramePreferenceKey.self) { frames in
                            chemicalRowFrames = frames
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
                        .padding(.horizontal, 16)
                        .padding(.top, -20) // overlap with banner bottom

                        visualIndicatorsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        notesCard
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 100)
                }
                .scrollDisabled(draggedChemical != nil)
                .ignoresSafeArea(edges: .top)

                // Treatment button pinned at bottom
                Button {
                    Task { await save() }
                } label: {
                    ZStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Show Treatment")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
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
                .disabled(isSaving)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Cancel")
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
            .navigationDestination(isPresented: $showingTreatmentPlan) {
                if let test = savedTest {
                    TreatmentPlanSheet(
                        test: test,
                        embedsInNavigationStack: false,
                        showsCloseButton: false,
                        showsDoneButton: false
                    )
                }
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        let headerHeight: CGFloat = 250
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
                    Text("Enter your")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(heroTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.leading, 20)
                .padding(.trailing, 210)
                .padding(.bottom, contentBottomPadding)
            }
            .overlay(alignment: .bottomTrailing) {
                Image("Test Data Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)
                    .padding(.trailing, 20)
                    .padding(.bottom, -40)
            }
        }
        .frame(height: headerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 0)) // full width
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Chemical Row

    private func chemRow(
        field: ChemicalField,
        icon: String,
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        idealRange: String,
        goodRange: ClosedRange<Double>,
        format: String = "%.1f",
        showUnit: Bool = true
    ) -> some View {
        let status = chemicalStatus(for: field, value: value.wrappedValue, goodRange: goodRange, fullRange: range)
        let meterColor = meterColor(for: status)

        return HStack(alignment: .top, spacing: 16) {
            ChemicalIcon(field: field, size: 54)
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    ReorderLongPressOverlay(
                        onBegan: {
                            beginChemicalDrag(for: field)
                        },
                        onChanged: { translation in
                            dragTranslation = translation
                            updateChemicalOrder(for: field, with: translation)
                        },
                        onEnded: {
                            endChemicalDrag()
                        }
                    )
                }
                .accessibilityLabel("Reorder \(label)")
                .accessibilityHint("Touch and hold, then drag up or down to reorder this chemical")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Text(String(format: format, value.wrappedValue))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PoolColor.primaryText)
                        .monospacedDigit()
                }

                VStack(spacing: 5) {
                    ZStack {
                        ChemicalMeterBackground(range: range, goodRange: goodRange)
                            .frame(height: 8)
                            .padding(.horizontal, 2)

                        Slider(value: value, in: range, step: step)
                            .tint(meterColor)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text(formatRangeValue(range.lowerBound, format: format))
                            .frame(width: 42, alignment: .leading)

                        Spacer(minLength: 8)

                        Text("Good \(idealRange)")
                            .fontWeight(.medium)
                            .foregroundStyle(Color(hex: "57B881"))

                        Spacer(minLength: 8)

                        Text(formatRangeValue(range.upperBound, format: format))
                            .frame(width: 42, alignment: .trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func chemicalDragPreview(
        field: ChemicalField,
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        idealRange: String,
        goodRange: ClosedRange<Double>,
        format: String = "%.1f",
        meterColor: Color,
        width: CGFloat
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ChemicalIcon(field: field, size: 54)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Text(String(format: format, value))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PoolColor.primaryText)
                        .monospacedDigit()
                }

                VStack(spacing: 5) {
                    ZStack {
                        ChemicalMeterBackground(range: range, goodRange: goodRange)
                            .frame(height: 8)
                            .padding(.horizontal, 2)

                        Capsule()
                            .fill(meterColor)
                            .frame(width: 18, height: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: previewThumbOffset(value: value, range: range))
                    }
                    .frame(height: 24)

                    HStack(alignment: .firstTextBaseline) {
                        Text(formatRangeValue(range.lowerBound, format: format))
                            .frame(width: 42, alignment: .leading)

                        Spacer(minLength: 8)

                        Text("Good \(idealRange)")
                            .fontWeight(.medium)
                            .foregroundStyle(Color(hex: "57B881"))

                        Spacer(minLength: 8)

                        Text(formatRangeValue(range.upperBound, format: format))
                            .frame(width: 42, alignment: .trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: width)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
        .opacity(0.9)
    }

    private func previewThumbOffset(value: Double, range: ClosedRange<Double>) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(ratio.clamped(to: 0...1)) * 214
    }

    private func rowFrameReader(for field: ChemicalField) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ChemicalRowFramePreferenceKey.self,
                value: [field: proxy.frame(in: .named("chemicalList"))]
            )
        }
    }

    private var resetChemicalOrderButton: some View {
        Button {
            resetChemicalOrder()
        } label: {
            Text("Reset to defaults")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.poolTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func beginChemicalDrag(for field: ChemicalField) {
        guard draggedChemical == nil else { return }

        dragStartFrame = chemicalRowFrames[field] ?? .zero
        dragTranslation = .zero
        draggedChemical = field
    }

    private func updateChemicalOrder(for field: ChemicalField, with translation: CGSize) {
        let visibleFields = visibleChemicalFields
        guard visibleFields.contains(field), dragStartFrame != .zero else { return }

        var reorderedVisibleFields = visibleFields.filter { $0 != field }
        let draggedCenterY = dragStartFrame.midY + translation.height
        let insertionIndex = reorderedVisibleFields.firstIndex { candidate in
            guard let frame = chemicalRowFrames[candidate] else { return false }
            return draggedCenterY < frame.midY
        } ?? reorderedVisibleFields.count

        reorderedVisibleFields.insert(field, at: insertionIndex)
        guard reorderedVisibleFields != visibleFields else { return }

        let hiddenFields = chemicalOrder.filter { !visibleFields.contains($0) }
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
            chemicalOrder = reorderedVisibleFields + hiddenFields
        }
    }

    private func endChemicalDrag() {
        if draggedChemical != nil {
            ChemicalField.saveDisplayOrder(chemicalOrder)
        }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            draggedChemical = nil
            dragTranslation = .zero
            dragStartFrame = .zero
        }
    }

    private func resetChemicalOrder() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            chemicalOrder = ChemicalField.defaultDisplayOrder
        }
        ChemicalField.saveDisplayOrder(ChemicalField.defaultDisplayOrder)
    }

    @ViewBuilder
    private func chemicalDragPreview(for field: ChemicalField, width: CGFloat) -> some View {
        switch field {
        case .pH:
            chemicalDragPreview(
                field: field,
                label: "pH",
                value: pH,
                range: 6.8...8.4,
                idealRange: "7.2 – 7.6",
                goodRange: 7.2...7.6,
                format: "%.1f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: pH, goodRange: 7.2...7.6, fullRange: 6.8...8.4)),
                width: width
            )
        case .freeChlorine:
            chemicalDragPreview(
                field: field,
                label: "Free Chlorine (ppm)",
                value: freeChlorine,
                range: 0...10,
                idealRange: "1 – 3 ppm",
                goodRange: 1...3,
                meterColor: meterColor(for: chemicalStatus(for: field, value: freeChlorine, goodRange: 1...3, fullRange: 0...10)),
                width: width
            )
        case .totalChlorine:
            let goodRange = max(0, freeChlorine - 0.5)...min(10, freeChlorine + 0.5)
            chemicalDragPreview(
                field: field,
                label: "Total Chlorine (ppm)",
                value: totalChlorine,
                range: 0...10,
                idealRange: "within 0.5 ppm of Free Cl",
                goodRange: goodRange,
                meterColor: meterColor(for: chemicalStatus(for: field, value: totalChlorine, goodRange: goodRange, fullRange: 0...10)),
                width: width
            )
        case .totalAlkalinity:
            chemicalDragPreview(
                field: field,
                label: "Total Alkalinity (ppm)",
                value: totalAlkalinity,
                range: 40...240,
                idealRange: "80 – 120 ppm",
                goodRange: 80...120,
                format: "%.0f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: totalAlkalinity, goodRange: 80...120, fullRange: 40...240)),
                width: width
            )
        case .calciumHardness:
            chemicalDragPreview(
                field: field,
                label: "Calcium Hardness (ppm)",
                value: calciumHardness,
                range: 100...500,
                idealRange: "200 – 400 ppm",
                goodRange: 200...400,
                format: "%.0f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: calciumHardness, goodRange: 200...400, fullRange: 100...500)),
                width: width
            )
        case .cyanuricAcid:
            chemicalDragPreview(
                field: field,
                label: "Cyanuric Acid (ppm)",
                value: cyanuricAcid,
                range: 0...100,
                idealRange: "30 – 50 ppm",
                goodRange: 30...50,
                format: "%.0f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: cyanuricAcid, goodRange: 30...50, fullRange: 0...100)),
                width: width
            )
        case .temperature:
            chemicalDragPreview(
                field: field,
                label: "Temperature (°F)",
                value: temperature,
                range: 50...105,
                idealRange: "78 – 88°F",
                goodRange: 78...88,
                format: "%.0f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: temperature, goodRange: 78...88, fullRange: 50...105)),
                width: width
            )
        case .saltLevel:
            chemicalDragPreview(
                field: field,
                label: "Salt Level (ppm)",
                value: saltLevel,
                range: 1000...5000,
                idealRange: "2700 – 3400 ppm",
                goodRange: 2700...3400,
                format: "%.0f",
                meterColor: meterColor(for: chemicalStatus(for: field, value: saltLevel, goodRange: 2700...3400, fullRange: 1000...5000)),
                width: width
            )
        }
    }

    @ViewBuilder
    private func chemicalRow(for field: ChemicalField) -> some View {
        switch field {
        case .pH:
            chemRow(
                field: field,
                icon: "pH",
                label: "pH",
                value: $pH,
                range: 6.8...8.4,
                step: 0.1,
                idealRange: "7.2 – 7.6",
                goodRange: 7.2...7.6,
                format: "%.1f",
                showUnit: false
            )
        case .freeChlorine:
            chemRow(
                field: field,
                icon: "Free Chlorine",
                label: "Free Chlorine (ppm)",
                value: $freeChlorine,
                range: 0...10,
                step: 0.5,
                idealRange: "1 – 3 ppm",
                goodRange: 1...3
            )
        case .totalChlorine:
            chemRow(
                field: field,
                icon: "Total Chlorine",
                label: "Total Chlorine (ppm)",
                value: $totalChlorine,
                range: 0...10,
                step: 0.5,
                idealRange: "within 0.5 ppm of Free Cl",
                goodRange: max(0, freeChlorine - 0.5)...min(10, freeChlorine + 0.5)
            )
        case .totalAlkalinity:
            chemRow(
                field: field,
                icon: "Alkalinity",
                label: "Total Alkalinity (ppm)",
                value: $totalAlkalinity,
                range: 40...240,
                step: 5,
                idealRange: "80 – 120 ppm",
                goodRange: 80...120,
                format: "%.0f"
            )
        case .calciumHardness:
            chemRow(
                field: field,
                icon: "Hardness",
                label: "Calcium Hardness (ppm)",
                value: $calciumHardness,
                range: 100...500,
                step: 10,
                idealRange: "200 – 400 ppm",
                goodRange: 200...400,
                format: "%.0f"
            )
        case .cyanuricAcid:
            chemRow(
                field: field,
                icon: "CYA",
                label: "Cyanuric Acid (ppm)",
                value: $cyanuricAcid,
                range: 0...100,
                step: 5,
                idealRange: "30 – 50 ppm",
                goodRange: 30...50,
                format: "%.0f"
            )
        case .temperature:
            chemRow(
                field: field,
                icon: "pH",
                label: "Temperature (°F)",
                value: $temperature,
                range: 50...105,
                step: 1,
                idealRange: "78 – 88°F",
                goodRange: 78...88,
                format: "%.0f",
                showUnit: false
            )
        case .saltLevel:
            chemRow(
                field: field,
                icon: "Free Chlorine",
                label: "Salt Level (ppm)",
                value: $saltLevel,
                range: 1000...5000,
                step: 100,
                idealRange: "2700 – 3400 ppm",
                goodRange: 2700...3400,
                format: "%.0f"
            )
        }
    }

    private func formatRangeValue(_ value: Double, format: String) -> String {
        String(format: format == "%.0f" ? "%.0f" : "%.1f", value)
    }

    private func chemicalStatus(
        for field: ChemicalField,
        value: Double,
        goodRange: ClosedRange<Double>,
        fullRange: ClosedRange<Double>
    ) -> ChemicalStatus {
        let engine = ChemistryEngine()

        switch field {
        case .pH:
            return engine.pHStatus(value)
        case .freeChlorine:
            return engine.freeChlorineStatus(value)
        case .totalAlkalinity:
            return engine.totalAlkalinityStatus(value)
        case .calciumHardness:
            return engine.calciumHardnessStatus(value, surface: viewModel.poolConfig.surfaceType)
        case .cyanuricAcid:
            return engine.cyanuricAcidStatus(value)
        case .saltLevel:
            return engine.saltStatus(value)
        case .totalChlorine, .temperature:
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)
        }
    }

    private func rangedStatus(
        value: Double,
        goodRange: ClosedRange<Double>,
        fullRange: ClosedRange<Double>
    ) -> ChemicalStatus {
        if goodRange.contains(value) {
            return .ideal
        }

        let span = fullRange.upperBound - fullRange.lowerBound
        let slightBand = max(span * 0.08, 0.1)
        let offRangeBand = max(span * 0.2, slightBand)

        if value < goodRange.lowerBound {
            let distance = goodRange.lowerBound - value
            if distance <= slightBand { return .slightlyLow }
            if distance <= offRangeBand { return .low }
            return .critical
        }

        let distance = value - goodRange.upperBound
        if distance <= slightBand { return .slightlyHigh }
        if distance <= offRangeBand { return .high }
        return .critical
    }

    private func meterColor(for status: ChemicalStatus) -> Color {
        switch status {
        case .ideal:
            return Color(hex: "57B881")
        case .slightlyLow, .slightlyHigh:
            return Color(hex: "FFC657")
        case .low, .high:
            return Color(hex: "FF9E4D")
        case .critical:
            return Color(hex: "FF686B")
        case .testing:
            return PoolColor.statusTesting
        }
    }

    private var orderedVisualIndicators: [String] {
        VisualIndicator.allCases
            .map(\.rawValue)
            .filter { selectedVisualIndicators.contains($0) }
    }

    private var divider: some View {
        Rectangle()
            .fill(PoolColor.divider)
            .frame(height: 1)
            .padding(.leading, 60)
    }

    private var visualIndicatorsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Visual Indicators (optional)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)
                Text("Visual signs you want considered when generating treatment.")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(VisualIndicator.allCases) { indicator in
                    visualIndicatorBadge(indicator)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    private func visualIndicatorBadge(_ indicator: VisualIndicator) -> some View {
        let isSelected = selectedVisualIndicators.contains(indicator.rawValue)

        return Button {
            if isSelected {
                selectedVisualIndicators.remove(indicator.rawValue)
            } else {
                selectedVisualIndicators.insert(indicator.rawValue)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: indicator.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(indicator.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : PoolColor.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                isSelected ? PoolColor.poolTeal : PoolColor.appBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? PoolColor.poolTeal : PoolColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes (optional)")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(PoolColor.primaryText)

            TextField("Add any details about your test…", text: $notes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
                .lineLimit(4...8)
                .padding(14)
                .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Actions

    private func prefill() {
        if let test = editingTest {
            date = test.date
            pH = test.pH
            freeChlorine = test.freeChlorine
            totalChlorine = test.totalChlorine
            totalAlkalinity = test.totalAlkalinity
            calciumHardness = test.calciumHardness
            cyanuricAcid = test.cyanuricAcid
            if let t = test.temperatureFahrenheit { temperature = t; includeTemperature = true }
            if let s = test.saltLevel { saltLevel = s; includeSalt = true }
            notes = test.notes
            selectedVisualIndicators = Set(test.visualIndicators)
        } else if let last = tests.first {
            pH = last.pH
            freeChlorine = last.freeChlorine
            totalChlorine = last.totalChlorine
            totalAlkalinity = last.totalAlkalinity
            calciumHardness = last.calciumHardness
            cyanuricAcid = last.cyanuricAcid
            if let t = last.temperatureFahrenheit { temperature = t; includeTemperature = true }
            if let s = last.saltLevel { saltLevel = s; includeSalt = true }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let test: PoolTest

        if let existing = editingTest {
            // Update existing
            existing.date = date
            existing.pH = pH
            existing.freeChlorine = freeChlorine
            existing.totalChlorine = totalChlorine
            existing.totalAlkalinity = totalAlkalinity
            existing.calciumHardness = calciumHardness
            existing.cyanuricAcid = cyanuricAcid
            existing.temperatureFahrenheit = includeTemperature ? temperature : nil
            existing.saltLevel = includeSalt ? saltLevel : nil
            existing.notes = notes
            existing.visualIndicators = orderedVisualIndicators
            test = existing
        } else {
            test = PoolTest(
                date: date,
                pH: pH,
                freeChlorine: freeChlorine,
                totalChlorine: totalChlorine,
                totalAlkalinity: totalAlkalinity,
                calciumHardness: calciumHardness,
                cyanuricAcid: cyanuricAcid,
                temperatureFahrenheit: includeTemperature ? temperature : nil,
                saltLevel: includeSalt ? saltLevel : nil,
                notes: notes,
                visualIndicators: orderedVisualIndicators
            )
            modelContext.insert(test)
        }

        // Generate recommendations
        let recent = Array(tests.prefix(13))
        await viewModel.generateRecommendations(
            for: test,
            recentTests: recent,
            modelContext: modelContext
        )

        savedTest = test
        showingTreatmentPlan = true
    }

    // MARK: - Date Helpers

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }
    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }
}

private enum ChemicalField: String, CaseIterable, Identifiable, Equatable {
    case pH
    case freeChlorine
    case totalChlorine
    case totalAlkalinity
    case calciumHardness
    case cyanuricAcid
    case temperature
    case saltLevel

    var id: String { rawValue }

    static let defaultDisplayOrder: [ChemicalField] = [
        .calciumHardness,
        .totalChlorine,
        .freeChlorine,
        .pH,
        .totalAlkalinity,
        .cyanuricAcid,
        .temperature,
        .saltLevel
    ]

    private static let displayOrderDefaultsKey = "AddTestView.chemicalDisplayOrder"

    static var savedDisplayOrder: [ChemicalField] {
        guard let savedValues = UserDefaults.standard.stringArray(forKey: displayOrderDefaultsKey) else {
            return defaultDisplayOrder
        }

        let savedFields = savedValues.compactMap(ChemicalField.init(rawValue:))
        let missingFields = defaultDisplayOrder.filter { !savedFields.contains($0) }
        let validSavedFields = savedFields.filter { defaultDisplayOrder.contains($0) }
        let orderedFields = validSavedFields + missingFields

        return orderedFields.isEmpty ? defaultDisplayOrder : orderedFields
    }

    static func saveDisplayOrder(_ order: [ChemicalField]) {
        UserDefaults.standard.set(order.map(\.rawValue), forKey: displayOrderDefaultsKey)
    }

    var label: String {
        switch self {
        case .pH:
            return "pH"
        case .freeChlorine:
            return "Free Chlorine"
        case .totalChlorine:
            return "Total Chlorine"
        case .totalAlkalinity:
            return "Total Alkalinity"
        case .calciumHardness:
            return "Calcium Hardness"
        case .cyanuricAcid:
            return "Cyanuric Acid"
        case .temperature:
            return "Temperature"
        case .saltLevel:
            return "Salt Level"
        }
    }

    var icon: String {
        switch self {
        case .pH, .temperature:
            return "pH"
        case .freeChlorine, .saltLevel:
            return "Free Chlorine"
        case .totalChlorine:
            return "Total Chlorine"
        case .totalAlkalinity:
            return "Alkalinity"
        case .calciumHardness:
            return "Hardness"
        case .cyanuricAcid:
            return "CYA"
        }
    }

    var accentColor: Color {
        switch self {
        case .pH, .calciumHardness:
            return Color(hex: "126CFF")
        case .freeChlorine, .totalChlorine, .totalAlkalinity, .saltLevel:
            return PoolColor.poolTeal
        case .cyanuricAcid:
            return PoolColor.sunshine
        case .temperature:
            return PoolColor.coral
        }
    }

    var iconBackground: Color {
        switch self {
        case .pH, .calciumHardness:
            return Color(hex: "EFF6FF")
        case .freeChlorine, .totalChlorine, .totalAlkalinity, .saltLevel:
            return Color(hex: "EAF8F6")
        case .cyanuricAcid:
            return Color(hex: "FFF8E6")
        case .temperature:
            return Color(hex: "FFF1EA")
        }
    }
}

private struct ChemicalRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [ChemicalField: CGRect] = [:]

    static func reduce(value: inout [ChemicalField: CGRect], nextValue: () -> [ChemicalField: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct ReorderLongPressOverlay: UIViewRepresentable {
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.5
        recognizer.allowableMovement = 8
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onBegan: () -> Void
        private let onChanged: (CGSize) -> Void
        private let onEnded: () -> Void
        private var startLocation: CGPoint?

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view.window)

            switch recognizer.state {
            case .began:
                startLocation = location
                onBegan()
            case .changed:
                guard let startLocation else { return }
                onChanged(CGSize(
                    width: location.x - startLocation.x,
                    height: location.y - startLocation.y
                ))
            case .ended, .cancelled, .failed:
                startLocation = nil
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private struct ChemicalIcon: View {
    let size: CGFloat
    let field: ChemicalField

    init(field: ChemicalField, size: CGFloat) {
        self.field = field
        self.size = size
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(field.iconBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(field.accentColor.opacity(0.12), lineWidth: 1)
                )

            Image(field.icon)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(field.accentColor)
                .frame(width: size * 0.46 + 8, height: size * 0.46 + 8)
                .scaleEffect(2.8)
                .frame(width: size * 0.46 + 8, height: size * 0.46 + 8)
                .clipped()
        }
        .frame(width: size, height: size)
    }
}

private struct ChemicalMeterBackground: View {
    let range: ClosedRange<Double>
    let goodRange: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let start = normalized(goodRange.lowerBound)
            let end = normalized(goodRange.upperBound)
            let segmentWidth = max(6, width * (end - start))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PoolColor.divider)

                Capsule()
                    .fill(Color(hex: "57B881").opacity(0.28))
                    .frame(width: segmentWidth)
                    .offset(x: width * start)
            }
        }
    }

    private func normalized(_ value: Double) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(ratio).clamped(to: 0...1)
    }
}

// MARK: - Preview

#Preview {
    AddTestView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
