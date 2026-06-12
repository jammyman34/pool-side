import SwiftUI

struct SettingsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // Profile
    @State private var profileName: String = ""
    @State private var profileEmail: String = ""
    @State private var profilePhone: String = ""

    // Pool Settings
    @State private var poolName: String = ""
    @State private var volumeGallons: Double = 15000
    @State private var poolType: PoolType = .inground
    @State private var surfaceType: SurfaceType = .plaster
    @State private var isSaltwater: Bool = false
    @State private var location: String = ""

    @State private var showingVolumeHelp: Bool = false
    @State private var showingSignOutConfirm: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // AI status banner
                        aiStatusBanner

                        // Profile section
                        sectionCard(header: "Profile") {
                            VStack(spacing: 0) {
                                settingRow(label: "Name") {
                                    TextField("Your name", text: $profileName)
                                        .font(.subheadline)
                                        .foregroundStyle(PoolColor.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                }
                                rowDivider
                                settingRow(label: "Email") {
                                    TextField("your@email.com", text: $profileEmail)
                                        .font(.subheadline)
                                        .foregroundStyle(PoolColor.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                }
                                rowDivider
                                settingRow(label: "Phone") {
                                    TextField("Optional", text: $profilePhone)
                                        .font(.subheadline)
                                        .foregroundStyle(PoolColor.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                        .keyboardType(.phonePad)
                                }
                            }
                        }

                        // Pool Settings section
                        sectionCard(header: "Pool Settings") {
                            VStack(spacing: 0) {
                                volumeRow
                                rowDivider
                                pickerRow(label: "Pool Type", selection: $poolType)
                                rowDivider
                                pickerRow(label: "Surface", selection: $surfaceType)
                                rowDivider
                                settingRow(label: "Location") {
                                    TextField("e.g. Phoenix, AZ", text: $location)
                                        .font(.subheadline)
                                        .foregroundStyle(PoolColor.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.words)
                                }
                                rowDivider
                                HStack {
                                    Text("Salt-Chlorine System")
                                        .font(.subheadline)
                                        .foregroundStyle(PoolColor.primaryText)
                                    Spacer()
                                    Toggle("", isOn: $isSaltwater.animation())
                                        .labelsHidden()
                                        .tint(PoolColor.poolTeal)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                            }
                        }

                        // Save button
                        Button(action: save) {
                            Text("Save Settings")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 17)
                                .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 16))
                        }

                        // Sign Out
                        Button {
                            showingSignOutConfirm = true
                        } label: {
                            Text("Sign Out")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(PoolColor.statusCritical)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(PoolColor.statusCritical.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(PoolColor.poolTeal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if PoolConfiguration.isConfigured {
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingVolumeHelp) {
                PoolVolumeHelpView()
            }
            .confirmationDialog(
                "Sign Out",
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    // Sign-out logic: clear config and dismiss
                    PoolConfiguration.clearCurrent()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
        .onAppear(perform: loadCurrentConfig)
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)
                .tracking(0.5)
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private func settingRow<Content: View>(label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func pickerRow<T: CaseIterable & Identifiable & Hashable & CustomStringConvertible>(
        label: String,
        selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .tint(PoolColor.poolTeal)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(PoolColor.divider)
            .frame(height: 1)
            .padding(.leading, 18)
    }

    private var volumeRow: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Pool Volume")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                Button {
                    showingVolumeHelp = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(PoolColor.poolTeal)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("\(Int(volumeGallons).formatted()) gal")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Button { volumeGallons = max(1000, volumeGallons - 1000) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PoolColor.poolTeal)
                }
                ZStack {
                    Capsule()
                        .fill(PoolColor.divider)
                        .frame(height: 8)
                        .padding(.horizontal, 2)

                    Slider(value: $volumeGallons, in: 1000...100000, step: 500)
                        .tint(PoolColor.poolTeal)
                }
                Button { volumeGallons = min(100000, volumeGallons + 1000) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
            Text("Small: ~10K • Medium: 15–20K • Large: 30K+")
                .font(.caption2)
                .foregroundStyle(PoolColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - AI Status Banner

    private var aiStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.aiServiceAvailable ? "sparkles" : "wand.and.stars")
                .font(.title3)
                .foregroundStyle(viewModel.aiServiceAvailable ? PoolColor.poolTeal : PoolColor.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.aiServiceAvailable ? "On-Device AI Active" : "Rule-Based Mode")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)
                Text(viewModel.aiServiceAvailable
                    ? "Apple Intelligence is powering your recommendations."
                    : "Requires iPhone 15 Pro+ for AI recommendations."
                )
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
            }

            Spacer()

            Circle()
                .fill(viewModel.aiServiceAvailable ? PoolColor.statusIdeal : PoolColor.statusSlight)
                .frame(width: 9, height: 9)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Actions

    private func loadCurrentConfig() {
        let config = viewModel.poolConfig
        poolName = config.name
        volumeGallons = config.volumeGallons
        poolType = config.poolType
        surfaceType = config.surfaceType
        isSaltwater = config.isSaltwater
        location = config.location
    }

    private func save() {
        let config = PoolConfiguration(
            name: poolName.isEmpty ? "My Pool" : poolName,
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

// MARK: - Pool Volume Help Sheet

struct PoolVolumeHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: PoolType = .inground

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Pool Type", selection: $selectedType) {
                        ForEach(PoolType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    TabView(selection: $selectedType) {
                        ForEach(PoolType.allCases) { type in
                            ScrollView {
                                volumeContent(for: type)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 24)
                            }
                            .tag(type)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Measuring Pool Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.poolTeal)
                }
            }
        }
    }

    @ViewBuilder
    private func volumeContent(for type: PoolType) -> some View {
        VStack(spacing: 16) {
            // Formula card
            VStack(alignment: .leading, spacing: 8) {
                Label("Formula", systemImage: "function")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)
                Text(formula(for: type))
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(PoolColor.primaryText)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                Label("How to measure", systemImage: "ruler")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.poolTeal)

                ForEach(Array(steps(for: type).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.white)
                            .frame(width: 22, height: 22)
                            .background(PoolColor.poolTeal, in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(PoolColor.primaryText)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

            // Tip
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(PoolColor.sunshine)
                Text(tip(for: type))
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PoolColor.sunshine.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PoolColor.sunshine.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func formula(for type: PoolType) -> String {
        switch type {
        case .inground:    return "Length × Width × Avg Depth × 7.5"
        case .aboveGround: return "Ø² × Depth × 5.9  (round)\nL × W × D × 7.5   (oval/rect)"
        case .spa:         return "Length × Width × Depth × 7.5"
        }
    }

    private func steps(for type: PoolType) -> [String] {
        switch type {
        case .inground:
            return [
                "Measure length and width at the widest points in feet.",
                "Measure depth at shallow and deep ends, then average them.",
                "Multiply length × width × average depth.",
                "Multiply by 7.5 to convert cubic feet to gallons."
            ]
        case .aboveGround:
            return [
                "For round pools, measure the inside diameter in feet.",
                "Measure the actual water depth (not wall height).",
                "Round: diameter × diameter × depth × 5.9.",
                "Oval or rectangular: length × width × depth × 7.5."
            ]
        case .spa:
            return [
                "Measure interior length, width, and depth in feet.",
                "For contoured seats, estimate an average depth.",
                "Multiply L × W × D × 7.5.",
                "Typical spas hold 250–600 gallons."
            ]
        }
    }

    private func tip(for type: PoolType) -> String {
        switch type {
        case .inground:    return "Check your pool's original blueprint for an exact volume — often more accurate than measuring."
        case .aboveGround: return "The pool's spec card or owner's manual usually lists the exact gallon capacity."
        case .spa:         return "Most spa manuals list capacity precisely. Check the door panel or manufacturer's site."
        }
    }
}

// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(PoolViewModel())
}

#Preview("Volume Help") {
    PoolVolumeHelpView()
}
