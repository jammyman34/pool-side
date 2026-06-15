import SwiftUI
import CoreLocation
import Observation

struct SettingsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // Pool Settings
    @State private var poolName: String = ""
    @State private var volumeGallons: Double = 15000
    @State private var poolType: PoolType = .inground
    @State private var surfaceType: SurfaceType = .plaster
    @State private var testMethod: TestMethod = .testStrips
    @State private var isSaltwater: Bool = false
    @State private var hasCover: Bool = false
    @State private var chlorinePreference: ChlorinePreference = .calHypo
    @State private var pHIncreaserPreference: PHIncreaserPreference = .sodaAsh
    @State private var pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid
    @State private var alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate
    @State private var calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride
    @State private var stabilizerPreference: StabilizerPreference = .granularCYA
    @State private var location: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationService = PoolLocationService()

    @State private var showingVolumeHelp: Bool = false
    @State private var showingLocationExplanation: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // AI status banner
                        aiStatusBanner

                        // Pool Settings section
                        sectionCard(header: "Pool Settings") {
                            VStack(spacing: 0) {
                                volumeRow
                                rowDivider
                                pickerRow(label: "Pool Type", selection: $poolType)
                                rowDivider
                                pickerRow(label: "Surface", selection: $surfaceType)
                                rowDivider
                                testingMethodRow
                                rowDivider
                                locationRow
                                rowDivider
                                toggleRow(label: "Pool Cover", isOn: $hasCover)
                                rowDivider
                                toggleRow(label: "Salt-Chlorine System", isOn: $isSaltwater)
                            }
                        }

                        sectionCard(header: "Chemical Preferences") {
                            VStack(spacing: 0) {
                                preferencePickerRow(label: "Chlorine", selection: $chlorinePreference)
                                rowDivider
                                preferencePickerRow(label: "pH Increaser", selection: $pHIncreaserPreference)
                                rowDivider
                                preferencePickerRow(label: "pH Decreaser", selection: $pHDecreaserPreference)
                                rowDivider
                                preferencePickerRow(label: "Alkalinity Increaser", selection: $alkalinityIncreaserPreference)
                                rowDivider
                                preferencePickerRow(label: "Calcium Increaser", selection: $calciumIncreaserPreference)
                                rowDivider
                                preferencePickerRow(label: "Stabilizer", selection: $stabilizerPreference)
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
            .alert("Use Your Location?", isPresented: $showingLocationExplanation) {
                Button("Allow While Using App") {
                    locationService.requestWhenInUseLocation()
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("Pool Side uses your location only while the app is open so future treatment guidance can account for local weather, sun exposure, and pool-cover timing. You can keep typing your location manually instead.")
            }
            .alert("Location Unavailable", isPresented: locationErrorBinding) {
                Button("OK", role: .cancel) {
                    locationService.errorMessage = nil
                }
            } message: {
                Text(locationService.errorMessage ?? "")
            }
        }
        .onAppear(perform: loadCurrentConfig)
        .onChange(of: locationService.resolvedLocationText) { _, newValue in
            guard !newValue.isEmpty else { return }
            location = newValue
            latitude = locationService.latitude
            longitude = locationService.longitude
        }
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

    private func preferencePickerRow<T: CaseIterable & Identifiable & Hashable & CustomStringConvertible>(
        label: String,
        selection: Binding<T>
    ) -> some View where T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)

            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.description).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(PoolColor.poolTeal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(PoolColor.divider)
            .frame(height: 1)
            .padding(.leading, 18)
    }

    private var locationRow: some View {
        settingRow(label: "Location") {
            HStack(spacing: 8) {
                TextField("e.g. Phoenix, AZ", text: $location)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)

                Button {
                    showingLocationExplanation = true
                } label: {
                    Image(systemName: locationService.isLocating ? "location.circle" : "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(PoolColor.poolTeal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use Current Location")
            }
        }
    }

    private var testingMethodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Testing Method")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                Spacer()
                Picker("Testing Method", selection: $testMethod) {
                    ForEach(TestMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .tint(PoolColor.poolTeal)
            }

            if let note = testMethod.confidenceNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func toggleRow(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
            Spacer()
            Toggle("", isOn: isOn.animation())
                .labelsHidden()
                .tint(PoolColor.poolTeal)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
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

    private var locationErrorBinding: Binding<Bool> {
        Binding(
            get: { locationService.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    locationService.errorMessage = nil
                }
            }
        )
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
                    ? "Apple Intelligence can help explain validated plans."
                    : "Deterministic safety rules are creating treatment plans."
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
        testMethod = config.testMethod
        isSaltwater = config.isSaltwater
        hasCover = config.hasCover
        chlorinePreference = config.chlorinePreference
        pHIncreaserPreference = config.pHIncreaserPreference
        pHDecreaserPreference = config.pHDecreaserPreference
        alkalinityIncreaserPreference = config.alkalinityIncreaserPreference
        calciumIncreaserPreference = config.calciumIncreaserPreference
        stabilizerPreference = config.stabilizerPreference
        location = config.location
        latitude = config.latitude
        longitude = config.longitude
    }

    private func save() {
        let config = PoolConfiguration(
            name: poolName.isEmpty ? "My Pool" : poolName,
            volumeGallons: volumeGallons,
            poolType: poolType,
            surfaceType: surfaceType,
            testMethod: testMethod,
            isSaltwater: isSaltwater,
            hasCover: hasCover,
            chlorinePreference: chlorinePreference,
            pHIncreaserPreference: pHIncreaserPreference,
            pHDecreaserPreference: pHDecreaserPreference,
            alkalinityIncreaserPreference: alkalinityIncreaserPreference,
            calciumIncreaserPreference: calciumIncreaserPreference,
            stabilizerPreference: stabilizerPreference,
            location: location,
            latitude: latitude,
            longitude: longitude
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

extension TestMethod: CustomStringConvertible {
    public var description: String { displayName }
}

extension ChlorinePreference: CustomStringConvertible {
    public var description: String { displayName }
}

extension PHIncreaserPreference: CustomStringConvertible {
    public var description: String { displayName }
}

extension PHDecreaserPreference: CustomStringConvertible {
    public var description: String { displayName }
}

extension AlkalinityIncreaserPreference: CustomStringConvertible {
    public var description: String { displayName }
}

extension CalciumIncreaserPreference: CustomStringConvertible {
    public var description: String { displayName }
}

extension StabilizerPreference: CustomStringConvertible {
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

// MARK: - Location Service

@Observable
final class PoolLocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var resolvedLocationText: String = ""
    var latitude: Double?
    var longitude: Double?
    var errorMessage: String?
    var isLocating: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseLocation() {
        errorMessage = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Location access is off for Pool Side. You can still type your location manually."
        @unknown default:
            isLocating = false
            errorMessage = "Location is unavailable right now."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            isLocating = false
            errorMessage = "Location access is off for Pool Side. You can still type your location manually."
        case .notDetermined:
            break
        @unknown default:
            isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLocating = false
            return
        }

        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let service = self else { return }

            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
                    let state = placemark.administrativeArea ?? ""
                    let resolved = [city, state]
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")

                    service.resolvedLocationText = resolved.isEmpty
                        ? String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
                        : resolved
                } else {
                    service.resolvedLocationText = String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
                    if error != nil {
                        service.errorMessage = "Could not name this location, so coordinates were saved instead."
                    }
                }

                service.isLocating = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        errorMessage = "Could not get your current location. You can still type it manually."
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
