import SwiftUI
import SwiftData

struct AddTestView: View {

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
    @State private var isSaving: Bool = false

    // Pre-fill from most recent test
    var lastTest: PoolTest? { tests.first }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Date picker
                        dateSection

                        // Core chemicals
                        VStack(spacing: 16) {
                            SectionHeader(title: "Core Chemicals")
                            chemicalSlider(label: "pH", value: $pH, range: 6.4...8.4, step: 0.1, idealRange: "7.2 – 7.6", format: "%.1f")
                            chemicalSlider(label: "Free Chlorine", value: $freeChlorine, range: 0...10, step: 0.5, idealRange: "1 – 3 ppm", unit: "ppm")
                            chemicalSlider(label: "Total Chlorine", value: $totalChlorine, range: 0...10, step: 0.5, idealRange: "≥ Free Cl", unit: "ppm")
                        }
                        .padding(16)
                        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))

                        // Balancers
                        VStack(spacing: 16) {
                            SectionHeader(title: "Balancers")
                            chemicalSlider(label: "Total Alkalinity", value: $totalAlkalinity, range: 30...250, step: 5, idealRange: "80 – 120 ppm", unit: "ppm")
                            chemicalSlider(label: "Calcium Hardness", value: $calciumHardness, range: 50...800, step: 10, idealRange: "200 – 400 ppm", unit: "ppm")
                            chemicalSlider(label: "Cyanuric Acid", value: $cyanuricAcid, range: 0...150, step: 5, idealRange: "30 – 50 ppm", unit: "ppm")
                        }
                        .padding(16)
                        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))

                        // Optional readings
                        VStack(spacing: 16) {
                            SectionHeader(title: "Optional")

                            Toggle(isOn: $includeTemperature) {
                                Label("Water Temperature", systemImage: "thermometer")
                                    .font(.subheadline)
                                    .foregroundStyle(PoolColor.cloudWhite)
                            }
                            .tint(PoolColor.poolTeal)

                            if includeTemperature {
                                chemicalSlider(label: "Temperature", value: $temperature, range: 50...105, step: 1, idealRange: "78 – 88°F", unit: "°F", format: "%.0f")
                            }

                            Divider().overlay(PoolColor.cloudWhite.opacity(0.1))

                            Toggle(isOn: $includeSalt.animation()) {
                                Label("Salt Level", systemImage: "drop.halffull")
                                    .font(.subheadline)
                                    .foregroundStyle(PoolColor.cloudWhite)
                            }
                            .tint(PoolColor.poolTeal)

                            if includeSalt {
                                chemicalSlider(label: "Salt", value: $saltLevel, range: 1000...5000, step: 100, idealRange: "2700 – 3400 ppm", unit: "ppm", format: "%.0f")
                            }
                        }
                        .padding(16)
                        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))

                        // Notes
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Notes")
                            TextField("Anything to note? (weather, bather load, etc.)", text: $notes, axis: .vertical)
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.cloudWhite)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(PoolColor.deepWater, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(16)
                        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Log Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(PoolColor.sunshine)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                                .foregroundStyle(PoolColor.sunshine)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear(perform: prefillFromLastTest)
    }

    // MARK: - Sections

    private var dateSection: some View {
        DatePicker("Test Date & Time", selection: $date)
            .datePickerStyle(.compact)
            .padding(16)
            .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))
            .foregroundStyle(PoolColor.cloudWhite)
            .tint(PoolColor.poolTeal)
    }

    private func chemicalSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        idealRange: String,
        unit: String = "",
        format: String = "%.1f"
    ) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PoolColor.cloudWhite)
                Spacer()
                HStack(spacing: 2) {
                    Text(String(format: format, value.wrappedValue))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.cloudWhite)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(PoolColor.cloudWhite.opacity(0.5))
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PoolColor.poolTeal)
                }

                Slider(value: value, in: range, step: step)
                    .tint(PoolColor.poolTeal)

                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }

            Text("Ideal: \(idealRange)")
                .font(.caption2)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Actions

    private func prefillFromLastTest() {
        guard let last = lastTest else { return }
        pH = last.pH
        freeChlorine = last.freeChlorine
        totalChlorine = last.totalChlorine
        totalAlkalinity = last.totalAlkalinity
        calciumHardness = last.calciumHardness
        cyanuricAcid = last.cyanuricAcid
        if let temp = last.temperatureFahrenheit {
            temperature = temp
            includeTemperature = true
        }
        if let salt = last.saltLevel {
            saltLevel = salt
            includeSalt = true
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let test = PoolTest(
            date: date,
            pH: pH,
            freeChlorine: freeChlorine,
            totalChlorine: totalChlorine,
            totalAlkalinity: totalAlkalinity,
            calciumHardness: calciumHardness,
            cyanuricAcid: cyanuricAcid,
            temperatureFahrenheit: includeTemperature ? temperature : nil,
            saltLevel: includeSalt ? saltLevel : nil,
            notes: notes
        )
        modelContext.insert(test)

        // Generate recommendations immediately after saving
        let recent = Array(tests.prefix(13))
        await viewModel.generateRecommendations(
            for: test,
            recentTests: recent,
            modelContext: modelContext
        )

        dismiss()
    }
}
