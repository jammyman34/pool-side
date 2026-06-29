import SwiftUI
import SwiftData
import UIKit

extension LiquidDropKitBrand {
    var icon: Image {
        switch self {
        case .taylorK2006FASDPD:
            return Image(systemName: "drop.fill")
        case .taylorK2005:
            return Image(systemName: "drop")
        case .otherLiquidDropKit:
            return Image(systemName: "ellipsis.circle")
        case .hachColorQ:
            return Image(systemName: "drop.triangle")
        case .jblProColorimeter:
            return Image(systemName: "drop.circle")
        case .hannaChecker:
            return Image(systemName: "checkmark.square")
        case .poolLab:
            return Image(systemName: "testtube.2")
        case .otherDigitalMeter:
            return Image(systemName: "ellipsis.circle")
        }
    }
}

private struct ChemicalFieldProfile {
    let range: ClosedRange<Double>
    let step: Double
    let idealRange: String
    let goodRange: ClosedRange<Double>
    let format: String
    let unitSuffix: String
}

private enum TaylorDropEntryField: String, Identifiable {
    case freeChlorine
    case combinedChlorine
    case totalAlkalinity
    case calciumHardness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeChlorine: return "Free Chlorine Drops"
        case .combinedChlorine: return "Combined Chlorine Drops"
        case .totalAlkalinity: return "Total Alkalinity Drops"
        case .calciumHardness: return "Calcium Hardness Drops"
        }
    }
}

struct AddTestView: View {

    private static let taylorSampleSizeDefaultsKey = "AddTestView.taylorSampleSize"

    /// When non-nil, the view is in "edit" mode for an existing test
    var editingTest: PoolTest? = nil
    var startsOnTreatmentPlan: Bool = false

    init(editingTest: PoolTest? = nil, startsOnTreatmentPlan: Bool = false) {
        self.editingTest = editingTest
        self.startsOnTreatmentPlan = startsOnTreatmentPlan
        _chemicalOrder = State(initialValue: ChemicalField.savedDisplayOrder)
        _taylorSampleSize = State(initialValue: Self.savedTaylorSampleSize)
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
    @State private var testMethod: TestMethod = .testStrips
    @State private var saveTestMethodAsDefault: Bool = false
    @State private var notes: String = ""
    @State private var includeTemperature: Bool = false
    @State private var includeSalt: Bool = false
    @State private var selectedVisualIndicators: Set<String> = []
    @State private var originalSnapshot: TestFormSnapshot? = nil
    @State private var chemicalOrder: [ChemicalField] = ChemicalField.defaultDisplayOrder
    @State private var draggedChemical: ChemicalField? = nil
    @State private var chemicalRowFrames: [ChemicalField: CGRect] = [:]
    @State private var dragStartFrame: CGRect = .zero
    @State private var dragTranslation: CGSize = .zero
    @State private var directEntryField: ChemicalField? = nil
    @State private var directEntryText: String = ""
    @State private var directEntryWantsFocus: Bool = false
    @State private var directDropEntryField: TaylorDropEntryField? = nil
    @State private var directDropEntryText: String = ""
    @State private var directDropEntryWantsFocus: Bool = false

    // Post-save
    @State private var savedTest: PoolTest? = nil
    @State private var showingTreatmentPlan: Bool = false
    @State private var didAutoShowInitialTreatmentPlan: Bool = false
    @State private var isSaving: Bool = false

    // New states for TestingMethodCard integration
    @State private var showTestingMethodEditor: Bool = false
    @State private var liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD
    @State private var testingMethodSheetHeight: CGFloat = 320

    // Taylor K-2006 FAS-DPD inputs
    @State private var taylorSampleSize: TaylorSampleSize = .twentyFiveMl
    @State private var taylorFCDrops: Int? = nil
    @State private var taylorCCDrops: Int? = nil
    @State private var taylorTADrops: Int? = nil
    @State private var taylorCHDrops: Int? = nil

    private static var savedTaylorSampleSize: TaylorSampleSize {
        guard let rawValue = UserDefaults.standard.string(forKey: taylorSampleSizeDefaultsKey),
              let sampleSize = TaylorSampleSize(rawValue: rawValue)
        else {
            return .twentyFiveMl
        }
        return sampleSize
    }

    private var activeSavedTest: PoolTest? { editingTest ?? savedTest }

    private var isEditing: Bool { editingTest != nil || savedTest != nil }

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

    private var hasExistingTreatmentPlan: Bool {
        !(activeSavedTest?.treatments.isEmpty ?? true)
    }

    private var hasFormChanges: Bool {
        guard isEditing, let originalSnapshot else { return !isEditing }
        return currentSnapshot != originalSnapshot
    }

    private var treatmentButtonTitle: String {
        if isEditing {
            if hasFormChanges { return "Update Treatment" }
            if hasExistingTreatmentPlan { return "View Treatment" }
        }
        return "Show Treatment"
    }

    private var currentSnapshot: TestFormSnapshot {
        TestFormSnapshot(
            date: date,
            pH: pH,
            freeChlorine: usesDropChlorine ? taylorFCPpm : freeChlorine,
            totalChlorine: usesDropChlorine ? (taylorTCAvailable ? taylorTCPpm : taylorFCPpm) : totalChlorine,
            totalAlkalinity: usesDropAlkalinity ? taylorTAPpm : totalAlkalinity,
            calciumHardness: usesDropHardness ? taylorCHPpm : calciumHardness,
            cyanuricAcid: cyanuricAcid,
            temperatureFahrenheit: includeTemperature ? temperature : nil,
            saltLevel: includeSalt ? saltLevel : nil,
            testMethod: testMethod,
            liquidDropKitBrand: testMethod.usesBrandPicker ? liquidDropKitBrand : nil,
            taylorSampleSize: usesDropChlorine ? taylorSampleSize : nil,
            taylorFCDrops: usesDropChlorine ? taylorFCDrops : nil,
            taylorCCDrops: usesDropChlorine ? taylorCCDrops : nil,
            taylorTADrops: usesDropAlkalinity ? taylorTADrops : nil,
            taylorCHDrops: usesDropHardness ? taylorCHDrops : nil,
            notes: notes,
            visualIndicators: orderedVisualIndicators
        )
    }

    private var isTaylorMode: Bool {
        isTaylorK2006Mode
    }

    private var isTaylorK2006Mode: Bool {
        testMethod == .liquidDropKit && liquidDropKitBrand == .taylorK2006FASDPD
    }

    private var isTaylorK2005Mode: Bool {
        testMethod == .liquidDropKit && liquidDropKitBrand == .taylorK2005
    }

    private var usesDropChlorine: Bool {
        isTaylorK2006Mode
    }

    private var usesDropAlkalinity: Bool {
        isTaylorK2006Mode || isTaylorK2005Mode
    }

    private var usesDropHardness: Bool {
        isTaylorK2006Mode || isTaylorK2005Mode
    }

    private var visibleChemicalFields: [ChemicalField] {
        let baseOrder = fixedChemicalOrderForSelectedTest ?? (isTaylorMode ? ChemicalField.taylorDisplayOrder : chemicalOrder)
        return baseOrder.filter { field in
            switch field {
            case .temperature:
                return includeTemperature
            case .saltLevel:
                return includeSalt && supportsSaltInputForSelectedTest
            case .combinedChlorine:
                return isTaylorMode
            default:
                return true
            }
        }
    }

    private var fixedChemicalOrderForSelectedTest: [ChemicalField]? {
        if isTaylorK2005Mode || isOtherLiquidKitMode || testMethod == .digitalTester || testMethod == .poolStore {
            return ChemicalField.listedFormDisplayOrder
        }
        return nil
    }

    private var isOtherLiquidKitMode: Bool {
        testMethod == .liquidDropKit && liquidDropKitBrand == .otherLiquidDropKit
    }

    private var supportsSaltInputForSelectedTest: Bool {
        switch testMethod {
        case .digitalTester:
            return liquidDropKitBrand == .hannaChecker
                || liquidDropKitBrand == .poolLab
                || liquidDropKitBrand == .otherDigitalMeter
        case .poolStore:
            return true
        case .liquidDropKit:
            return !isTaylorK2005Mode && !isOtherLiquidKitMode
        case .testStrips:
            return true
        }
    }

    private func totalChlorineGoodRange(upperBound: Double) -> ClosedRange<Double> {
        let lower = min(freeChlorine, upperBound)
        let upper = max(lower, min(upperBound, freeChlorine + 0.5))
        return lower...upper
    }

    private func fieldProfile(for field: ChemicalField) -> ChemicalFieldProfile {
        let engine = ChemistryEngine()
        let chlorineRange = engine.freeChlorineTargetRange(cyanuricAcid: cyanuricAcid)
        let chlorineLabel = engine.freeChlorineIdealRangeLabel(cyanuricAcid: cyanuricAcid)

        let testStripProfiles: [ChemicalField: ChemicalFieldProfile] = [
            .pH: .init(range: 6.2...8.4, step: 0.1, idealRange: "7.4 – 7.6", goodRange: 7.2...7.8, format: "%.1f", unitSuffix: ""),
            .freeChlorine: .init(range: 0...20, step: 0.5, idealRange: chlorineLabel, goodRange: chlorineRange, format: "%.1f", unitSuffix: " ppm"),
            .combinedChlorine: .init(range: 0...3, step: 0.5, idealRange: "0 – 0.5 ppm", goodRange: 0...0.5, format: "%.1f", unitSuffix: " ppm"),
            .totalChlorine: .init(range: 0...10, step: 0.5, idealRange: "equal to Free Cl", goodRange: totalChlorineGoodRange(upperBound: 10), format: "%.1f", unitSuffix: " ppm"),
            .totalAlkalinity: .init(range: 0...240, step: 5, idealRange: "80 – 100 ppm", goodRange: 80...120, format: "%.0f", unitSuffix: " ppm"),
            .calciumHardness: .init(range: 0...1000, step: 10, idealRange: "250 – 400 ppm", goodRange: 200...500, format: "%.0f", unitSuffix: " ppm"),
            .cyanuricAcid: .init(range: 0...300, step: 5, idealRange: "30 – 50 ppm", goodRange: 30...50, format: "%.0f", unitSuffix: " ppm"),
            .temperature: .init(range: 50...105, step: 1, idealRange: "78 – 88°F", goodRange: 78...88, format: "%.0f", unitSuffix: "°F"),
            .saltLevel: .init(range: 1000...5000, step: 100, idealRange: "2700 – 3400 ppm", goodRange: 2700...3400, format: "%.0f", unitSuffix: " ppm")
        ]

        let taylorK2005Profiles: [ChemicalField: ChemicalFieldProfile] = [
            .pH: .init(range: 6.8...8.2, step: 0.1, idealRange: "7.4 – 7.6", goodRange: 7.2...7.8, format: "%.1f", unitSuffix: ""),
            .freeChlorine: .init(range: 0...5, step: 0.5, idealRange: chlorineLabel, goodRange: chlorineRange, format: "%.1f", unitSuffix: " ppm"),
            .combinedChlorine: testStripProfiles[.combinedChlorine]!,
            .totalChlorine: .init(range: 0...5, step: 0.5, idealRange: "equal to Free Cl", goodRange: totalChlorineGoodRange(upperBound: 5), format: "%.1f", unitSuffix: " ppm"),
            .totalAlkalinity: .init(range: 0...300, step: 10, idealRange: "80 – 100 ppm", goodRange: 80...120, format: "%.0f", unitSuffix: " ppm"),
            .calciumHardness: testStripProfiles[.calciumHardness]!,
            .cyanuricAcid: .init(range: 20...100, step: 5, idealRange: "30 – 50 ppm", goodRange: 30...50, format: "%.0f", unitSuffix: " ppm"),
            .temperature: testStripProfiles[.temperature]!,
            .saltLevel: testStripProfiles[.saltLevel]!
        ]

        let digitalProfiles: [ChemicalField: ChemicalFieldProfile] = [
            .pH: .init(range: 6.5...8.5, step: 0.1, idealRange: "7.4 – 7.6", goodRange: 7.2...7.8, format: "%.1f", unitSuffix: ""),
            .freeChlorine: .init(range: 0...20, step: 0.5, idealRange: chlorineLabel, goodRange: chlorineRange, format: "%.1f", unitSuffix: " ppm"),
            .combinedChlorine: testStripProfiles[.combinedChlorine]!,
            .totalChlorine: .init(range: 0...20, step: 0.5, idealRange: "equal to Free Cl", goodRange: totalChlorineGoodRange(upperBound: 20), format: "%.1f", unitSuffix: " ppm"),
            .totalAlkalinity: .init(range: 0...300, step: 5, idealRange: "80 – 100 ppm", goodRange: 80...120, format: "%.0f", unitSuffix: " ppm"),
            .calciumHardness: testStripProfiles[.calciumHardness]!,
            .cyanuricAcid: .init(range: 0...150, step: 5, idealRange: "30 – 50 ppm", goodRange: 30...50, format: "%.0f", unitSuffix: " ppm"),
            .temperature: testStripProfiles[.temperature]!,
            .saltLevel: .init(range: 0...6000, step: 100, idealRange: "2700 – 3400 ppm", goodRange: 2700...3400, format: "%.0f", unitSuffix: " ppm")
        ]

        let otherLiquidProfiles: [ChemicalField: ChemicalFieldProfile] = [
            .pH: .init(range: 6.8...8.4, step: 0.1, idealRange: "7.4 – 7.6", goodRange: 7.2...7.8, format: "%.1f", unitSuffix: ""),
            .freeChlorine: .init(range: 0...10, step: 0.5, idealRange: chlorineLabel, goodRange: chlorineRange, format: "%.1f", unitSuffix: " ppm"),
            .combinedChlorine: testStripProfiles[.combinedChlorine]!,
            .totalChlorine: .init(range: 0...10, step: 0.5, idealRange: "equal to Free Cl", goodRange: totalChlorineGoodRange(upperBound: 10), format: "%.1f", unitSuffix: " ppm"),
            .totalAlkalinity: .init(range: 0...300, step: 5, idealRange: "80 – 100 ppm", goodRange: 80...120, format: "%.0f", unitSuffix: " ppm"),
            .calciumHardness: testStripProfiles[.calciumHardness]!,
            .cyanuricAcid: .init(range: 0...150, step: 5, idealRange: "30 – 50 ppm", goodRange: 30...50, format: "%.0f", unitSuffix: " ppm"),
            .temperature: testStripProfiles[.temperature]!,
            .saltLevel: testStripProfiles[.saltLevel]!
        ]

        let activeProfiles: [ChemicalField: ChemicalFieldProfile]
        switch testMethod {
        case .liquidDropKit where isTaylorK2005Mode:
            activeProfiles = taylorK2005Profiles
        case .liquidDropKit where liquidDropKitBrand == .otherLiquidDropKit:
            activeProfiles = otherLiquidProfiles
        case .digitalTester, .poolStore:
            activeProfiles = digitalProfiles
        default:
            activeProfiles = testStripProfiles
        }

        return activeProfiles[field] ?? testStripProfiles[field]!
    }

    private var taylorFCPpm: Double {
        Double(taylorFCDrops ?? 0) * taylorSampleSize.ppmPerDrop
    }

    private var taylorCCPpm: Double {
        Double(taylorCCDrops ?? 0) * taylorSampleSize.ppmPerDrop
    }

    private var taylorTCPpm: Double {
        taylorFCPpm + taylorCCPpm
    }

    private var taylorTAPpm: Double {
        Double(taylorTADrops ?? 0) * 10
    }

    private var taylorCHPpm: Double {
        Double(taylorCHDrops ?? 0) * 10
    }

    private var taylorTCAvailable: Bool {
        taylorFCDrops != nil && taylorCCDrops != nil
    }

    /// Combined chlorine ppm used by the drag preview & status badges.
    /// In Taylor mode this is the user-entered CC; otherwise derive from FC/TC.
    private var combinedChlorineValue: Double {
        max(0, totalChlorine - freeChlorine)
    }

    private var testMethodDiffersFromDefault: Bool {
        testMethod != viewModel.poolConfig.testMethod
    }

    private var matchesConfigDefaults: Bool {
        let config = viewModel.poolConfig
        guard testMethod == config.testMethod else { return false }
        if testMethod.usesBrandPicker {
            return liquidDropKitBrand == config.liquidDropKitBrand
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Teal hero banner
                        heroBanner

                        // Place TestingMethodCard immediately after heroBanner
                        TestingMethodCard(
                            mode: .summary(onTap: { showTestingMethodEditor = true }),
                            testMethod: testMethod,
                            saveAsDefault: saveTestMethodAsDefault,
                            liquidDropKitBrand: liquidDropKitBrand
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, -16)

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

//                                divider
//                                resetChemicalOrderButton
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
                        .padding(.top, 16) // overlap with banner bottom

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
                            Text(treatmentButtonTitle)
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
                        showsCloseButton: true,
                        showsDoneButton: false,
                        onClose: { dismiss() }
                    )
                }
            }
            .sheet(isPresented: $showTestingMethodEditor) {
                NavigationStack {
                    TestingMethodCard(
                        mode: .editor(onDone: { showTestingMethodEditor = false }),
                        testMethod: $testMethod,
                        saveAsDefault: $saveTestMethodAsDefault,
                        liquidDropKitBrand: $liquidDropKitBrand
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TestingMethodSheetHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text("Testing Method")
                                .font(.headline)
                                .foregroundStyle(PoolColor.primaryText)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showTestingMethodEditor = false
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(PoolColor.poolTeal)
                        }
                    }
                }
                .onPreferenceChange(TestingMethodSheetHeightKey.self) { value in
                    // Include nav bar (~56pt) when sizing the sheet.
                    testingMethodSheetHeight = value + 56
                }
                .presentationDetents([.height(testingMethodSheetHeight)])
                .presentationDragIndicator(.visible)
                .presentationBackground(PoolColor.sand)
            }
            .sheet(item: $directEntryField) { field in
                directNumericEntrySheet(for: field)
            }
            .sheet(item: $directDropEntryField) { field in
                directDropEntrySheet(for: field)
            }
        }
        .onAppear(perform: prefill)
        .onChange(of: testMethod) { _, _ in
            if !liquidDropKitBrand.isAvailable(for: testMethod) {
                liquidDropKitBrand = LiquidDropKitBrand.defaultBrand(for: testMethod)
            }
            if matchesConfigDefaults {
                saveTestMethodAsDefault = false
            }
        }
        .onChange(of: liquidDropKitBrand) { _, _ in
            if matchesConfigDefaults {
                saveTestMethodAsDefault = false
            }
        }
        .onChange(of: taylorSampleSize) { _, newValue in
            saveTaylorSampleSize(newValue)
        }
        .task {
            await showInitialTreatmentPlanIfNeeded()
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
        .padding(.top, topPadding)
        .frame(height: headerHeight + topPadding)
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
                    if !isTaylorMode {
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
                }
                .accessibilityLabel(isTaylorMode ? label : "Reorder \(label)")
                .accessibilityHint(isTaylorMode ? "" : "Touch and hold, then drag up or down to reorder this chemical")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Button {
                        beginDirectEntry(for: field, value: value.wrappedValue, format: format)
                    } label: {
                        Text(String(format: format, value.wrappedValue))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(PoolColor.primaryText)
                            .monospacedDigit()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PoolColor.poolTeal.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(label) value")
                    .accessibilityHint("Opens a numeric entry sheet")
                    .disabled(!allowsDirectEntry(for: field))
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

    private func beginDirectEntry(for field: ChemicalField, value: Double, format: String) {
        guard allowsDirectEntry(for: field) else { return }
        directEntryText = String(format: format, value)
        directEntryWantsFocus = true
        directEntryField = field
    }

    private func allowsDirectEntry(for field: ChemicalField) -> Bool {
        !isTaylorMode || field == .pH
    }

    private func directNumericEntrySheet(for field: ChemicalField) -> some View {
        let config = directEntryConfig(for: field)

        return NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(config.title)
                        .font(.headline)
                        .foregroundStyle(PoolColor.primaryText)

                    Text("Enter a value from \(formatRangeValue(config.range.lowerBound, format: config.format)) to \(formatRangeValue(config.range.upperBound, format: config.format))\(config.unitSuffix).")
                        .font(.footnote)
                        .foregroundStyle(PoolColor.secondaryText)
                }

                DirectNumericTextField(
                    placeholder: config.placeholder,
                    text: $directEntryText,
                    keyboardType: config.keyboardType,
                    wantsFocus: $directEntryWantsFocus
                )
                    .frame(height: 62)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(PoolColor.poolTeal.opacity(0.25), lineWidth: 1)
                    )

                HStack {
                    Text("Good \(config.idealRange)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(hex: "57B881"))

                    Spacer()

                    Text("Slider step: \(formatRangeValue(config.step, format: config.format))")
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PoolColor.sand.ignoresSafeArea())
            .navigationTitle("Enter Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        directEntryField = nil
                    }
                    .foregroundStyle(PoolColor.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyDirectEntry(for: field)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                    .disabled(parsedDirectEntryValue(for: field) == nil)
                }
            }
        }
        .onAppear {
            directEntryWantsFocus = true
        }
        .onDisappear {
            directEntryWantsFocus = false
        }
        .presentationDetents([.height(310)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PoolColor.sand)
    }

    private func beginDropEntry(for field: TaylorDropEntryField, currentDrops: Int?) {
        directDropEntryText = currentDrops.map(String.init) ?? "0"
        directDropEntryWantsFocus = true
        directDropEntryField = field
    }

    private func directDropEntrySheet(for field: TaylorDropEntryField) -> some View {
        let maxDrops = maxDrops(for: field)

        return NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.title)
                        .font(.headline)
                        .foregroundStyle(PoolColor.primaryText)

                    Text("Enter a whole number from 0 to \(maxDrops).")
                        .font(.footnote)
                        .foregroundStyle(PoolColor.secondaryText)
                }

                DirectNumericTextField(
                    placeholder: "0",
                    text: $directDropEntryText,
                    keyboardType: .numberPad,
                    wantsFocus: $directDropEntryWantsFocus
                )
                    .frame(height: 62)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(PoolColor.poolTeal.opacity(0.25), lineWidth: 1)
                    )

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(PoolColor.sand.ignoresSafeArea())
            .navigationTitle("Enter Drops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        directDropEntryField = nil
                    }
                    .foregroundStyle(PoolColor.secondaryText)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyDropEntry(for: field)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                    .disabled(parsedDropEntryValue(for: field) == nil)
                }
            }
        }
        .onAppear {
            directDropEntryWantsFocus = true
        }
        .onDisappear {
            directDropEntryWantsFocus = false
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationBackground(PoolColor.sand)
    }

    private func applyDropEntry(for field: TaylorDropEntryField) {
        guard let drops = parsedDropEntryValue(for: field) else { return }

        switch field {
        case .freeChlorine:
            taylorFCDrops = drops
        case .combinedChlorine:
            taylorCCDrops = drops
        case .totalAlkalinity:
            taylorTADrops = drops
        case .calciumHardness:
            taylorCHDrops = drops
        }

        directDropEntryField = nil
    }

    private func parsedDropEntryValue(for field: TaylorDropEntryField) -> Int? {
        let sanitized = directDropEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(sanitized) else { return nil }
        return value.clamped(to: 0...maxDrops(for: field))
    }

    private func maxDrops(for field: TaylorDropEntryField) -> Int {
        switch field {
        case .freeChlorine:
            return Int((fieldProfile(for: .freeChlorine).range.upperBound / taylorSampleSize.ppmPerDrop).rounded(.down))
        case .combinedChlorine:
            return Int((3.0 / taylorSampleSize.ppmPerDrop).rounded(.down))
        case .totalAlkalinity:
            return Int((fieldProfile(for: .totalAlkalinity).range.upperBound / 10.0).rounded(.down))
        case .calciumHardness:
            return Int((fieldProfile(for: .calciumHardness).range.upperBound / 10.0).rounded(.down))
        }
    }

    private func applyDirectEntry(for field: ChemicalField) {
        guard let value = parsedDirectEntryValue(for: field) else { return }
        chemicalBinding(for: field).wrappedValue = value
        directEntryField = nil
    }

    private func parsedDirectEntryValue(for field: ChemicalField) -> Double? {
        let sanitized = directEntryText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard let value = Double(sanitized) else { return nil }
        let config = directEntryConfig(for: field)
        let clamped = value.clamped(to: config.range)
        return ((clamped / config.step).rounded() * config.step).rounded(toPlaces: config.decimalPlaces)
    }

    private func chemicalBinding(for field: ChemicalField) -> Binding<Double> {
        switch field {
        case .pH:
            return $pH
        case .freeChlorine:
            return $freeChlorine
        case .totalChlorine:
            return $totalChlorine
        case .totalAlkalinity:
            return $totalAlkalinity
        case .calciumHardness:
            return $calciumHardness
        case .cyanuricAcid:
            return $cyanuricAcid
        case .temperature:
            return $temperature
        case .saltLevel:
            return $saltLevel
        case .combinedChlorine:
            return Binding(
                get: { combinedChlorineValue },
                set: { _ in }
            )
        }
    }

    private func directEntryConfig(for field: ChemicalField) -> DirectNumericEntryConfig {
        let profile = fieldProfile(for: field)
        return DirectNumericEntryConfig(
            title: field.label,
            range: profile.range,
            step: profile.step,
            format: profile.format,
            idealRange: profile.idealRange,
            unitSuffix: profile.unitSuffix
        )
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

    // MARK: - Taylor K-2006 Row Builder

    /// Drop-titration row used when the Taylor K-2006 FAS-DPD kit is selected.
    /// `valuePpm == nil` displays a placeholder (used by Total Chlorine until FC+CC are entered).
    /// `drops` omitted produces a read-only row (Total Chlorine).
    private func taylorChemRow(
        field: ChemicalField,
        label: String,
        valuePpm: Double?,
        range: ClosedRange<Double>,
        idealRange: String,
        goodRange: ClosedRange<Double>,
        format: String = "%.1f",
        sampleSizePicker: Bool = false,
        dropsPrompt: String? = nil,
        drops: Binding<Int?>? = nil,
        dropEntryField: TaylorDropEntryField? = nil
    ) -> some View {
        let displayValue = valuePpm ?? range.lowerBound
        let status = chemicalStatus(for: field, value: displayValue, goodRange: goodRange, fullRange: range)
        let resolvedMeterColor = meterColor(for: status)
        let valueText: String = {
            guard let v = valuePpm else { return "—" }
            return String(format: format, v)
        }()

        return HStack(alignment: .top, spacing: 16) {
            ChemicalIcon(field: field, size: 54)
                .accessibilityLabel(label)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(PoolColor.primaryText)
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(valuePpm == nil ? PoolColor.secondaryText : PoolColor.primaryText)
                        .monospacedDigit()
                }

                if sampleSizePicker {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sample Size")
                            .font(.caption)
                            .foregroundStyle(PoolColor.secondaryText)
                        taylorSampleSizeSelector
                    }
                    .padding(.bottom, 2)
                }

                VStack(spacing: 5) {
                    ZStack {
                        ChemicalMeterBackground(range: range, goodRange: goodRange)
                            .frame(height: 8)
                            .padding(.horizontal, 2)

                        Capsule()
                            .fill(valuePpm == nil ? PoolColor.divider : resolvedMeterColor)
                            .frame(width: 18, height: 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .offset(x: previewThumbOffset(value: displayValue, range: range))
                            .opacity(valuePpm == nil ? 0.35 : 1)
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

                if let dropsPrompt, let drops, let dropEntryField {
                    taylorDropsStepper(prompt: dropsPrompt, drops: drops, entryField: dropEntryField)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var taylorSampleSizeSelector: some View {
        Picker("Sample Size", selection: $taylorSampleSize) {
            ForEach(TaylorSampleSize.allCases) { size in
                Text(size.displayLabel).tag(size)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func taylorDropsStepper(
        prompt: String,
        drops: Binding<Int?>,
        entryField: TaylorDropEntryField
    ) -> some View {
        HStack(spacing: 12) {
            Text(prompt)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(PoolColor.secondaryText)
            Spacer(minLength: 8)

            Button {
                if let current = drops.wrappedValue {
                    drops.wrappedValue = max(0, current - 1)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(PoolColor.poolTeal)
            }
            .buttonStyle(.plain)
            .disabled(drops.wrappedValue == nil)
            .opacity(drops.wrappedValue == nil ? 0.35 : 1)
            .accessibilityLabel("Decrease \(prompt)")

            Button {
                beginDropEntry(for: entryField, currentDrops: drops.wrappedValue)
            } label: {
                Text(drops.wrappedValue.map(String.init) ?? "—")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolColor.primaryText)
                    .monospacedDigit()
                    .frame(minWidth: 34)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(PoolColor.poolTeal.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(prompt)")
            .accessibilityHint("Opens a numeric entry sheet")

            Button {
                drops.wrappedValue = (drops.wrappedValue ?? 0) + 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(PoolColor.poolTeal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(prompt)")
        }
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
        let profile = fieldProfile(for: field)
        let value: Double = {
            switch field {
            case .pH:
                return pH
            case .freeChlorine:
                return usesDropChlorine ? taylorFCPpm : freeChlorine
            case .combinedChlorine:
                return usesDropChlorine ? taylorCCPpm : combinedChlorineValue
            case .totalChlorine:
                return usesDropChlorine ? taylorTCPpm : totalChlorine
            case .totalAlkalinity:
                return usesDropAlkalinity ? taylorTAPpm : totalAlkalinity
            case .calciumHardness:
                return usesDropHardness ? taylorCHPpm : calciumHardness
            case .cyanuricAcid:
                return cyanuricAcid
            case .temperature:
                return temperature
            case .saltLevel:
                return saltLevel
            }
        }()

        switch field {
        case .pH, .freeChlorine, .combinedChlorine, .totalChlorine, .totalAlkalinity, .calciumHardness, .cyanuricAcid, .temperature, .saltLevel:
            chemicalDragPreview(
                field: field,
                label: field == .pH ? "pH" : "\(field.label) \(field == .temperature ? "(°F)" : "(ppm)")",
                value: value,
                range: profile.range,
                idealRange: profile.idealRange,
                goodRange: profile.goodRange,
                format: profile.format,
                meterColor: meterColor(for: chemicalStatus(for: field, value: value, goodRange: profile.goodRange, fullRange: profile.range)),
                width: width
            )
        }
    }

    @ViewBuilder
    private func chemicalRow(for field: ChemicalField) -> some View {
        let profile = fieldProfile(for: field)
        switch field {
        case .pH:
            chemRow(
                field: field,
                icon: field.icon,
                label: "pH",
                value: $pH,
                range: profile.range,
                step: profile.step,
                idealRange: profile.idealRange,
                goodRange: profile.goodRange,
                format: profile.format,
                showUnit: false
            )
        case .freeChlorine:
            if usesDropChlorine {
                taylorChemRow(
                    field: field,
                    label: "Free Chlorine (ppm)",
                    valuePpm: taylorFCDrops == nil ? nil : taylorFCPpm,
                    range: profile.range,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    sampleSizePicker: true,
                    dropsPrompt: "Pink to Clear Drops",
                    drops: $taylorFCDrops,
                    dropEntryField: .freeChlorine
                )
            } else {
                chemRow(
                    field: field,
                    icon: field.icon,
                    label: "Free Chlorine (ppm)",
                    value: $freeChlorine,
                    range: profile.range,
                    step: profile.step,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format
                )
            }
        case .combinedChlorine:
            taylorChemRow(
                field: field,
                label: "Combined Chlorine (ppm)",
                valuePpm: taylorCCDrops == nil ? nil : taylorCCPpm,
                range: 0...3,
                idealRange: "0 – 0.5 ppm",
                goodRange: 0...0.5,
                dropsPrompt: "Pink to Clear Drops",
                drops: $taylorCCDrops,
                dropEntryField: .combinedChlorine
            )
        case .totalChlorine:
            if usesDropChlorine {
                taylorChemRow(
                    field: field,
                    label: "Total Chlorine (ppm)",
                    valuePpm: taylorTCAvailable ? taylorTCPpm : nil,
                    range: profile.range,
                    idealRange: "FC + CC",
                    goodRange: {
                        let lower = min(taylorFCPpm, profile.range.upperBound)
                        let upper = max(lower, min(profile.range.upperBound, taylorFCPpm + 0.5))
                        return lower...upper
                    }()
                )
            } else {
                chemRow(
                    field: field,
                    icon: field.icon,
                    label: "Total Chlorine (ppm)",
                    value: $totalChlorine,
                    range: profile.range,
                    step: profile.step,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format
                )
            }
        case .totalAlkalinity:
            if usesDropAlkalinity {
                taylorChemRow(
                    field: field,
                    label: "Total Alkalinity (ppm)",
                    valuePpm: taylorTADrops == nil ? nil : taylorTAPpm,
                    range: profile.range,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format,
                    dropsPrompt: "Green to Red Drops",
                    drops: $taylorTADrops,
                    dropEntryField: .totalAlkalinity
                )
            } else {
                chemRow(
                    field: field,
                    icon: field.icon,
                    label: "Total Alkalinity (ppm)",
                    value: $totalAlkalinity,
                    range: profile.range,
                    step: profile.step,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format
                )
            }
        case .calciumHardness:
            if usesDropHardness {
                taylorChemRow(
                    field: field,
                    label: "Total Hardness (ppm)",
                    valuePpm: taylorCHDrops == nil ? nil : taylorCHPpm,
                    range: profile.range,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format,
                    dropsPrompt: "Red to Blue Drops",
                    drops: $taylorCHDrops,
                    dropEntryField: .calciumHardness
                )
            } else {
                chemRow(
                    field: field,
                    icon: field.icon,
                    label: "Total Hardness (ppm)",
                    value: $calciumHardness,
                    range: profile.range,
                    step: profile.step,
                    idealRange: profile.idealRange,
                    goodRange: profile.goodRange,
                    format: profile.format
                )
            }
        case .cyanuricAcid:
            chemRow(
                field: field,
                icon: field.icon,
                label: "Cyanuric Acid (ppm)",
                value: $cyanuricAcid,
                range: profile.range,
                step: profile.step,
                idealRange: profile.idealRange,
                goodRange: profile.goodRange,
                format: profile.format
            )
        case .temperature:
            chemRow(
                field: field,
                icon: field.icon,
                label: "Temperature (°F)",
                value: $temperature,
                range: profile.range,
                step: profile.step,
                idealRange: profile.idealRange,
                goodRange: profile.goodRange,
                format: profile.format,
                showUnit: false
            )
        case .saltLevel:
            chemRow(
                field: field,
                icon: field.icon,
                label: "Salt Level (ppm)",
                value: $saltLevel,
                range: profile.range,
                step: profile.step,
                idealRange: profile.idealRange,
                goodRange: profile.goodRange,
                format: profile.format
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
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)

        case .freeChlorine:
            // Keep dynamic by CYA, but color is still driven by engine which already adapts.
            return engine.freeChlorineStatus(value, cyanuricAcid: cyanuricAcid)

        case .combinedChlorine:
            // Combined chlorine ideal is 0 – 0.5 ppm; above that signals chloramines.
            return rangedStatus(value: value, goodRange: 0...0.5, fullRange: 0...3)

        case .totalChlorine:
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)

        case .totalAlkalinity:
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)

        case .calciumHardness:
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)

        case .cyanuricAcid:
            return rangedStatus(value: value, goodRange: goodRange, fullRange: fullRange)

        case .saltLevel:
            // Keep existing engine-based status
            return engine.saltStatus(value)

        case .temperature:
            // Keep existing ranged behavior (78-88 good within 50-105 full)
            return rangedStatus(value: value, goodRange: 78...88, fullRange: 50...105)
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

            let gridIndicators = VisualIndicator.allCases.filter { !$0.requiresFullWidthBadge }
            let fullWidthIndicators = VisualIndicator.allCases.filter { $0.requiresFullWidthBadge }

            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(gridIndicators) { indicator in
                        visualIndicatorBadge(indicator)
                    }
                }

                ForEach(fullWidthIndicators) { indicator in
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
            testMethod = test.testMethod
            liquidDropKitBrand = test.liquidDropKitBrand ?? viewModel.poolConfig.liquidDropKitBrand
            taylorSampleSize = test.taylorSampleSize ?? .twentyFiveMl
            taylorFCDrops = test.taylorFCDrops
            taylorCCDrops = test.taylorCCDrops
            taylorTADrops = test.taylorTADrops
            taylorCHDrops = test.taylorCHDrops
            saveTestMethodAsDefault = false
            notes = test.notes
            selectedVisualIndicators = Set(test.visualIndicators)
            originalSnapshot = currentSnapshot
        } else if let last = tests.first {
            testMethod = viewModel.poolConfig.testMethod
            liquidDropKitBrand = viewModel.poolConfig.liquidDropKitBrand
            saveTestMethodAsDefault = false
            taylorSampleSize = Self.savedTaylorSampleSize
            pH = last.pH
            freeChlorine = last.freeChlorine
            totalChlorine = last.totalChlorine
            totalAlkalinity = last.totalAlkalinity
            calciumHardness = last.calciumHardness
            cyanuricAcid = last.cyanuricAcid
            if let t = last.temperatureFahrenheit { temperature = t; includeTemperature = true }
            if let s = last.saltLevel { saltLevel = s; includeSalt = true }
        } else {
            testMethod = viewModel.poolConfig.testMethod
            liquidDropKitBrand = viewModel.poolConfig.liquidDropKitBrand
            saveTestMethodAsDefault = false
            taylorSampleSize = Self.savedTaylorSampleSize
        }
        normalizeBrandForCurrentMethod()
    }

    private func normalizeBrandForCurrentMethod() {
        if !liquidDropKitBrand.isAvailable(for: testMethod) {
            liquidDropKitBrand = LiquidDropKitBrand.defaultBrand(for: testMethod)
        }
    }

    private func saveTaylorSampleSize(_ sampleSize: TaylorSampleSize) {
        UserDefaults.standard.set(sampleSize.rawValue, forKey: Self.taylorSampleSizeDefaultsKey)
    }

    @MainActor
    private func showInitialTreatmentPlanIfNeeded() async {
        guard startsOnTreatmentPlan,
              !didAutoShowInitialTreatmentPlan,
              let editingTest
        else { return }

        didAutoShowInitialTreatmentPlan = true
        savedTest = editingTest
        await Task.yield()
        showingTreatmentPlan = true
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        if let existing = activeSavedTest, !hasFormChanges, hasExistingTreatmentPlan {
            savedTest = existing
            showingTreatmentPlan = true
            return
        }

        let shouldReplaceCompletedPlan = activeSavedTest != nil && hasFormChanges
        let test: PoolTest

        normalizeBrandForCurrentMethod()
        let persistedBrand: LiquidDropKitBrand? = testMethod.usesBrandPicker ? liquidDropKitBrand : nil

        // In drop-test rows, the user's drops are the source of truth — derive ppm from them.
        let resolvedFC = usesDropChlorine ? taylorFCPpm : freeChlorine
        let resolvedTC: Double = {
            guard usesDropChlorine else { return totalChlorine }
            return taylorTCAvailable ? taylorTCPpm : taylorFCPpm
        }()
        let resolvedTA = usesDropAlkalinity ? taylorTAPpm : totalAlkalinity
        let resolvedCH = usesDropHardness ? taylorCHPpm : calciumHardness

        if let existing = activeSavedTest {
            // Update existing
            existing.date = date
            existing.pH = pH
            existing.freeChlorine = resolvedFC
            existing.totalChlorine = resolvedTC
            existing.totalAlkalinity = resolvedTA
            existing.calciumHardness = resolvedCH
            existing.cyanuricAcid = cyanuricAcid
            existing.temperatureFahrenheit = includeTemperature ? temperature : nil
            existing.saltLevel = includeSalt ? saltLevel : nil
            existing.testMethod = testMethod
            existing.liquidDropKitBrand = persistedBrand
            existing.taylorSampleSize = usesDropChlorine ? taylorSampleSize : nil
            existing.taylorFCDrops = usesDropChlorine ? taylorFCDrops : nil
            existing.taylorCCDrops = usesDropChlorine ? taylorCCDrops : nil
            existing.taylorTADrops = usesDropAlkalinity ? taylorTADrops : nil
            existing.taylorCHDrops = usesDropHardness ? taylorCHDrops : nil
            existing.notes = notes
            existing.visualIndicators = orderedVisualIndicators
            test = existing
        } else {
            test = PoolTest(
                date: date,
                pH: pH,
                freeChlorine: resolvedFC,
                totalChlorine: resolvedTC,
                totalAlkalinity: resolvedTA,
                calciumHardness: resolvedCH,
                cyanuricAcid: cyanuricAcid,
                temperatureFahrenheit: includeTemperature ? temperature : nil,
                saltLevel: includeSalt ? saltLevel : nil,
                testMethod: testMethod,
                liquidDropKitBrand: persistedBrand,
                notes: notes,
                visualIndicators: orderedVisualIndicators
            )
            if usesDropChlorine || usesDropAlkalinity || usesDropHardness {
                test.taylorSampleSize = taylorSampleSize
                test.taylorFCDrops = usesDropChlorine ? taylorFCDrops : nil
                test.taylorCCDrops = usesDropChlorine ? taylorCCDrops : nil
                test.taylorTADrops = usesDropAlkalinity ? taylorTADrops : nil
                test.taylorCHDrops = usesDropHardness ? taylorCHDrops : nil
            }
            modelContext.insert(test)
        }

        if saveTestMethodAsDefault {
            var updatedConfig = viewModel.poolConfig
            var changed = false
            if updatedConfig.testMethod != testMethod {
                updatedConfig.testMethod = testMethod
                changed = true
            }
            if testMethod.usesBrandPicker, updatedConfig.liquidDropKitBrand != liquidDropKitBrand {
                updatedConfig.liquidDropKitBrand = liquidDropKitBrand
                changed = true
            }
            if changed {
                viewModel.saveConfig(updatedConfig)
            }
        }

        // Generate recommendations
        let recent = Array(tests.prefix(13))
        await viewModel.generateRecommendations(
            for: test,
            recentTests: recent,
            modelContext: modelContext,
            replacingCompletedPlan: shouldReplaceCompletedPlan
        )

        do {
            try modelContext.save()
        } catch {
            viewModel.lastError = error.localizedDescription
        }

        originalSnapshot = currentSnapshot
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

private struct TestFormSnapshot: Equatable {
    let date: Date
    let pH: Double
    let freeChlorine: Double
    let totalChlorine: Double
    let totalAlkalinity: Double
    let calciumHardness: Double
    let cyanuricAcid: Double
    let temperatureFahrenheit: Double?
    let saltLevel: Double?
    let testMethod: TestMethod
    let liquidDropKitBrand: LiquidDropKitBrand?
    let taylorSampleSize: TaylorSampleSize?
    let taylorFCDrops: Int?
    let taylorCCDrops: Int?
    let taylorTADrops: Int?
    let taylorCHDrops: Int?
    let notes: String
    let visualIndicators: [String]
}

private struct DirectNumericEntryConfig {
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let idealRange: String
    var unitSuffix: String = ""

    var placeholder: String {
        format == "%.0f" ? "300" : "7.4"
    }

    var decimalPlaces: Int {
        format == "%.0f" ? 0 : 1
    }

    var keyboardType: UIKeyboardType {
        decimalPlaces == 0 ? .numberPad : .decimalPad
    }
}

private struct DirectNumericTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    @Binding var wantsFocus: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.textAlignment = .left
        textField.font = UIFont.systemFont(ofSize: 34, weight: .bold)
        textField.textColor = UIColor(PoolColor.primaryText)
        textField.tintColor = UIColor(PoolColor.poolTeal)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.placeholder = placeholder
        uiView.keyboardType = keyboardType

        guard wantsFocus, !context.coordinator.didSelectInitialText else { return }
        context.coordinator.didSelectInitialText = true
        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
            uiView.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var text: String
        var didSelectInitialText = false

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textDidChange(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

private enum ChemicalField: String, CaseIterable, Identifiable, Equatable {
    case pH
    case freeChlorine
    case combinedChlorine
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
        .combinedChlorine,
        .freeChlorine,
        .pH,
        .totalAlkalinity,
        .cyanuricAcid,
        .temperature,
        .saltLevel
    ]

    /// Fixed order used when the Taylor K-2006 FAS-DPD kit is selected; matches the sketch.
    static let taylorDisplayOrder: [ChemicalField] = [
        .freeChlorine,
        .combinedChlorine,
        .totalChlorine,
        .pH,
        .totalAlkalinity,
        .calciumHardness,
        .cyanuricAcid,
        .temperature,
        .saltLevel
    ]

    static let listedFormDisplayOrder: [ChemicalField] = [
        .freeChlorine,
        .totalChlorine,
        .pH,
        .totalAlkalinity,
        .calciumHardness,
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
        case .combinedChlorine:
            return "Combined Chlorine"
        case .totalChlorine:
            return "Total Chlorine"
        case .totalAlkalinity:
            return "Total Alkalinity"
        case .calciumHardness:
            return "Total Hardness"
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
        case .combinedChlorine, .totalChlorine:
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
        case .freeChlorine, .combinedChlorine, .totalChlorine, .totalAlkalinity, .saltLevel:
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
        case .freeChlorine, .combinedChlorine, .totalChlorine, .totalAlkalinity, .saltLevel:
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

// MARK: - TestingMethodCard

struct TestingMethodCard: View {
    /// Mode now clearly separates summary (with onTap) and editor (with onDone)
    enum Mode {
        case summary(onTap: () -> Void)
        case editor(onDone: () -> Void)

        var isSummary: Bool {
            switch self {
            case .summary: return true
            case .editor: return false
            }
        }
    }

    let mode: Mode

    // Bindings for editor mode
    @Binding var testMethod: TestMethod
    @Binding var saveAsDefault: Bool
    @Binding var liquidDropKitBrand: LiquidDropKitBrand

    // For summary mode only
    var onTap: (() -> Void)? {
        if case let .summary(action) = mode {
            return action
        }
        return nil
    }

    // For editor mode only
    var onDone: (() -> Void)? {
        if case let .editor(action) = mode {
            return action
        }
        return nil
    }

    /// Primary initializer takes all bindings and mode
    init(
        mode: Mode,
        testMethod: Binding<TestMethod>,
        saveAsDefault: Binding<Bool>,
        liquidDropKitBrand: Binding<LiquidDropKitBrand>
    ) {
        self.mode = mode
        self._testMethod = testMethod
        self._saveAsDefault = saveAsDefault
        self._liquidDropKitBrand = liquidDropKitBrand
    }

    /// Convenience initializer for summary mode with constant values
    init(
        mode: Mode,
        testMethod: TestMethod,
        saveAsDefault: Bool = false,
        liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD
    ) {
        self.mode = mode
        self._testMethod = .constant(testMethod)
        self._saveAsDefault = .constant(saveAsDefault)
        self._liquidDropKitBrand = .constant(liquidDropKitBrand)
    }

    var body: some View {
        Group {
            if mode.isSummary {
                summaryView
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            } else {
                editorView
            }
        }
    }

    private var summaryView: some View {
        HStack {
            Image(systemName: testMethod.systemImageName)
                .font(.title3)
                .foregroundStyle(PoolColor.poolTeal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(summaryTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)

                Text(summarySubtitle)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(PoolColor.primaryText)
            }
            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PoolColor.poolTeal)
        }
    }

    private var summaryTitle: String {
        if testMethod.usesBrandPicker {
            return "Testing Method: \(testMethod.displayName)"
        }
        return "Testing Method"
    }

    private var summarySubtitle: String {
        if testMethod.usesBrandPicker {
            return liquidDropKitBrand.displayName
        }
        return testMethod.displayName
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Method")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)

                HStack {
                    Picker("Testing Method", selection: $testMethod) {
                        ForEach(TestMethod.allCases) { method in
                            Label(method.displayName, systemImage: method.systemImageName)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PoolColor.poolTeal)
                    .labelsHidden()

                    Spacer(minLength: 0)
                }

                if let note = testMethod.confidenceNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(PoolColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }

            if testMethod == .liquidDropKit || testMethod == .digitalTester {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brand")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.primaryText)

                    HStack {
                        Picker("\(testMethod.displayName) Brand", selection: $liquidDropKitBrand) {
                            ForEach(LiquidDropKitBrand.options(for: testMethod)) { brand in
                                Label {
                                    Text(brand.displayName)
                                } icon: {
                                    brand.icon
                                }
                                .tag(brand)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PoolColor.poolTeal)
                        .labelsHidden()

                        Spacer(minLength: 0)
                    }
                }
            }

            Toggle("Use this as my default for future logs", isOn: $saveAsDefault.animation())
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
                .tint(PoolColor.poolTeal)
        }
        .onChange(of: testMethod) { _, newValue in
            if !liquidDropKitBrand.isAvailable(for: newValue) {
                liquidDropKitBrand = LiquidDropKitBrand.defaultBrand(for: newValue)
            }
        }
    }
}

private struct TestingMethodSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Preview

#Preview {
    AddTestView()
        .environment(PoolViewModel())
        .modelContainer(for: [PoolTest.self, Treatment.self], inMemory: true)
}
