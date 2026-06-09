import SwiftUI

struct SettingsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var volumeGallons: Double = 15000
    @State private var poolType: PoolType = .inground
    @State private var surfaceType: SurfaceType = .plaster
    @State private var isSaltwater: Bool = false
    @State private var location: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // AI status card
                        aiStatusCard

                        // Pool info
                        VStack(spacing: 16) {
                            SectionHeader(title: "Pool Details")

                            formField(label: "Pool Name") {
                                TextField("e.g. Backyard Pool", text: $name)
                                    .textInputAutocapitalization(.words)
                            }

                            Divider().overlay(PoolColor.cloudWhite.opacity(0.1))

                            volumeField

                            Divider().overlay(PoolColor.cloudWhite.opacity(0.1))

                            formPicker(label: "Pool Type", selection: $poolType)
                            formPicker(label: "Surface Type", selection: $surfaceType)

                            Divider().overlay(PoolColor.cloudWhite.opacity(0.1))

                            Toggle(isOn: $isSaltwater.animation()) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Salt-Chlorine System")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(PoolColor.cloudWhite)
                                    Text("Enables salt level tracking")
                                        .font(.caption)
                                        .foregroundStyle(PoolColor.cloudWhite.opacity(0.4))
                                }
                            }
                            .tint(PoolColor.poolTeal)

                            Divider().overlay(PoolColor.cloudWhite.opacity(0.1))

                            formField(label: "Location (optional)") {
                                TextField("e.g. Phoenix, AZ", text: $location)
                                    .textInputAutocapitalization(.words)
                            }
                        }
                        .padding(16)
                        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))

                        // Chemistry reference
                        chemistryReferenceCard

                        // Save button
                        Button(action: save) {
                            Text("Save Pool Settings")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(PoolColor.deepWater)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(PoolColor.sunshine, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PoolColor.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if PoolConfiguration.isConfigured {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                    }
                }
            }
        }
        .onAppear(perform: loadCurrentConfig)
    }

    // MARK: - Form Helpers

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(PoolColor.cloudWhite)
            Spacer()
            content()
                .font(.subheadline)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.7))
                .multilineTextAlignment(.trailing)
        }
    }

    private func formPicker<T: CaseIterable & Identifiable & Hashable & CustomStringConvertible>(
        label: String,
        selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(PoolColor.cloudWhite)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .tint(PoolColor.poolTeal)
        }
    }

    private var volumeField: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Pool Volume")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(PoolColor.cloudWhite)
                Spacer()
                Text("\(Int(volumeGallons).formatted()) gal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.cloudWhite)
                    .monospacedDigit()
            }
            HStack(spacing: 12) {
                Button { volumeGallons = max(1000, volumeGallons - 1000) } label: {
                    Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(PoolColor.poolTeal)
                }
                Slider(value: $volumeGallons, in: 1000...100000, step: 500)
                    .tint(PoolColor.poolTeal)
                Button { volumeGallons = min(100000, volumeGallons + 1000) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(PoolColor.poolTeal)
                }
            }
            Text("Common sizes: 10,000 (small) · 15,000–20,000 (medium) · 30,000+ (large)")
                .font(.caption2)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.35))
        }
    }

    // MARK: - Cards

    private var aiStatusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: viewModel.aiServiceAvailable ? "sparkles" : "wand.and.stars")
                .font(.title2)
                .foregroundStyle(viewModel.aiServiceAvailable ? PoolColor.poolTeal : PoolColor.cloudWhite.opacity(0.4))

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.aiServiceAvailable ? "On-Device AI Active" : "Rule-Based Mode")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.cloudWhite)

                Text(viewModel.aiServiceAvailable
                    ? "Apple Intelligence is powering your recommendations."
                    : "Recommendations use chemistry rules. Requires iPhone 15 Pro+ for AI."
                )
                .font(.caption)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Circle()
                .fill(viewModel.aiServiceAvailable ? PoolColor.statusIdeal : PoolColor.statusSlight)
                .frame(width: 10, height: 10)
        }
        .padding(16)
        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chemistryReferenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ideal Ranges Reference")

            VStack(spacing: 6) {
                referenceRow(label: "pH", value: "7.2 – 7.6")
                referenceRow(label: "Free Chlorine", value: "1 – 3 ppm")
                referenceRow(label: "Total Alkalinity", value: "80 – 120 ppm")
                referenceRow(label: "Calcium Hardness", value: "200 – 400 ppm")
                referenceRow(label: "Cyanuric Acid", value: "30 – 50 ppm")
                if isSaltwater {
                    referenceRow(label: "Salt Level", value: "2700 – 3400 ppm")
                }
            }
        }
        .padding(16)
        .background(PoolColor.oceanBlue, in: RoundedRectangle(cornerRadius: 20))
    }

    private func referenceRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(PoolColor.cloudWhite.opacity(0.6))
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.statusIdeal)
        }
    }

    // MARK: - Actions

    private func loadCurrentConfig() {
        let config = viewModel.poolConfig
        name = config.name
        volumeGallons = config.volumeGallons
        poolType = config.poolType
        surfaceType = config.surfaceType
        isSaltwater = config.isSaltwater
        location = config.location
    }

    private func save() {
        let config = PoolConfiguration(
            name: name.isEmpty ? "My Pool" : name,
            volumeGallons: volumeGallons,
            poolType: poolType,
            surfaceType: surfaceType,
            isSaltwater: isSaltwater,
            location: location
        )
        viewModel.saveConfig(config)
        dismiss()
    }
}

// MARK: - CustomStringConvertible for Pickers

extension PoolType: CustomStringConvertible {
    public var description: String { displayName }
}

extension SurfaceType: CustomStringConvertible {
    public var description: String { displayName }
}
