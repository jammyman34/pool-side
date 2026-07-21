import SwiftUI

struct FirstUseWelcomeView: View {
    let onStartSetup: () -> Void

    var body: some View {
        ZStack {
            PoolColor.appBackground.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer(minLength: 28)

                Text("Welcome to Pool Side")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PoolColor.deepWater)
                    .multilineTextAlignment(.center)

                Image("Test Data Hero")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Text("Know when your pool is ready to swim.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(PoolColor.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Pool Side tells you what your pool needs, what to do next, and when it’s ready for you and your family.")
                        .font(.body)
                        .foregroundStyle(PoolColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                Button(action: onStartSetup) {
                    Text("Set Up My Pool")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PoolColor.poolTeal, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 34)
            }
        }
    }
}

struct FirstUsePoolSetupView: View {
    @Environment(PoolViewModel.self) private var viewModel

    let onComplete: () -> Void

    @State private var poolName: String = "My Pool"
    @State private var volumeGallons: Double = 15000
    @State private var poolType: PoolType = .inground
    @State private var surfaceType: SurfaceType = .plaster
    @State private var testMethod: TestMethod = .testStrips
    @State private var liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD
    @State private var isSaltwater: Bool = false
    @State private var hasCover: Bool = false
    @State private var petsRegularlySwim: Bool = false
    @State private var usesRoboticCleaner: Bool = false
    @State private var enableNextPoolTestReminders: Bool = false
    @State private var enableTreatmentStepReminders: Bool = false
    @State private var chlorinePreference: ChlorinePreference = .liquidChlorine10
    @State private var lastNonSaltChlorinePreference: ChlorinePreference = .liquidChlorine10
    @State private var pHIncreaserPreference: PHIncreaserPreference = .sodaAsh
    @State private var pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid
    @State private var alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate
    @State private var calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride
    @State private var stabilizerPreference: StabilizerPreference = .granularCYA
    @State private var location: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationService = PoolLocationService()
    @State private var showingVolumeHelp = false

    private var canContinue: Bool {
        volumeGallons > 0
    }

    private var currentConfig: PoolConfiguration {
        PoolConfiguration(
            name: poolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Pool" : poolName,
            volumeGallons: volumeGallons,
            poolType: poolType,
            surfaceType: surfaceType,
            testMethod: testMethod,
            liquidDropKitBrand: liquidDropKitBrand,
            isSaltwater: isSaltwater,
            hasCover: hasCover,
            petsRegularlySwim: petsRegularlySwim,
            usesRoboticCleaner: usesRoboticCleaner,
            enableNextPoolTestReminders: enableNextPoolTestReminders,
            enableTreatmentStepReminders: enableTreatmentStepReminders,
            chlorinePreference: chlorinePreference,
            lastNonSaltChlorinePreference: lastNonSaltChlorinePreference,
            pHIncreaserPreference: pHIncreaserPreference,
            pHDecreaserPreference: pHDecreaserPreference,
            alkalinityIncreaserPreference: alkalinityIncreaserPreference,
            calciumIncreaserPreference: calciumIncreaserPreference,
            stabilizerPreference: stabilizerPreference,
            location: location,
            latitude: latitude,
            longitude: longitude
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tell us about your pool")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(PoolColor.primaryText)

                            Text("This one-time setup helps Pool Side calculate accurate treatments and swim-readiness guidance.")
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.secondaryText)
                        }
                        .padding(.top, 12)

                        setupSection("Required") {
                            textRow("Pool Name", text: $poolName)
                            divider
                            volumeRow
                            divider
                            pickerRow("Surface", selection: $surfaceType, options: SurfaceType.allCases)
                            divider
                            pickerRow("Testing Method", selection: $testMethod, options: TestMethod.allCases)
                            if testMethod.usesBrandPicker {
                                divider
                                pickerRow("Test Kit", selection: $liquidDropKitBrand, options: LiquidDropKitBrand.options(for: testMethod))
                            }
                            divider
                            toggleRow("Salt-Chlorine System", isOn: $isSaltwater)
                                .onChange(of: isSaltwater) { _, enabled in
                                    updateSaltMode(enabled)
                                }
                        }

                        setupSection("Chemical Preferences") {
                            chlorinePreferenceRow
                            divider
                            pickerRow("pH Increaser", selection: $pHIncreaserPreference, options: PHIncreaserPreference.allCases)
                            divider
                            pickerRow("pH Decreaser", selection: $pHDecreaserPreference, options: PHDecreaserPreference.allCases)
                            divider
                            pickerRow("Alkalinity Increaser", selection: $alkalinityIncreaserPreference, options: AlkalinityIncreaserPreference.allCases)
                            divider
                            pickerRow("Calcium Increaser", selection: $calciumIncreaserPreference, options: CalciumIncreaserPreference.allCases)
                            divider
                            pickerRow("Stabilizer", selection: $stabilizerPreference, options: StabilizerPreference.allCases)
                        }

                        setupSection("Optional") {
                            locationRow
                            divider
                            toggleRow("Pool Cover", isOn: $hasCover)
                            divider
                            toggleRow("Pets regularly swim", isOn: $petsRegularlySwim)
                            divider
                            toggleRow("Robotic pool cleaner", isOn: $usesRoboticCleaner)
                        }

                        setupSection("Notifications") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Turn on reminders so Pool Side can nudge you when it’s time to test again or finish a treatment step. It helps keep the pool ready without having to remember the timing yourself.")
                                    .font(.caption)
                                    .foregroundStyle(helperTextColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                toggleRow("Next Pool Test Reminders", isOn: $enableNextPoolTestReminders)
                                    .onChange(of: enableNextPoolTestReminders) { _, enabled in
                                        requestNotificationPermissionIfNeeded(enabled)
                                    }
                                divider
                                toggleRow("Treatment Step Reminders", isOn: $enableTreatmentStepReminders)
                                    .onChange(of: enableTreatmentStepReminders) { _, enabled in
                                        requestNotificationPermissionIfNeeded(enabled)
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .dismissesKeyboardOnScroll()

                VStack {
                    Spacer()
                    Button(action: saveAndContinue) {
                        Text("Continue")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canContinue ? PoolColor.poolTeal : PoolColor.secondaryText.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .background(Color.white.opacity(0.94).ignoresSafeArea(edges: .bottom))
                    }
                    .disabled(!canContinue)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingVolumeHelp) {
                PoolVolumeHelpView(
                    poolType: $poolType,
                    surfaceType: $surfaceType,
                    volumeGallons: $volumeGallons
                )
            }
        }
        .onAppear(perform: loadDefaults)
        .onChange(of: locationService.resolvedLocationText) { _, newValue in
            guard !newValue.isEmpty else { return }
            location = newValue
            latitude = locationService.latitude
            longitude = locationService.longitude
        }
        .alert("Location Unavailable", isPresented: locationErrorBinding) {
            Button("OK", role: .cancel) {
                locationService.errorMessage = nil
            }
        } message: {
            Text(locationService.errorMessage ?? "")
        }
    }

    private var helperTextColor: Color {
        PoolColor.secondaryText.opacity(0.95)
    }

    private var volumeRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pool Volume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolColor.primaryText)
                Text("Required for accurate dosing")
                    .font(.caption)
                    .foregroundStyle(helperTextColor)
            }
            Spacer()
            TextField("15000", value: $volumeGallons, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(PoolColor.primaryText)
                .tint(PoolColor.poolTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 92)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PoolColor.divider, lineWidth: 1)
                )
            Button {
                showingVolumeHelp = true
            } label: {
                Image(systemName: "ruler")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PoolColor.poolTeal)
                    .frame(width: 32, height: 32)
                    .background(PoolColor.poolTeal.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("How to measure your pool")
        }
    }

    private var locationRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PoolColor.primaryText)
                Text("Zip code")
                    .font(.caption)
                    .foregroundStyle(helperTextColor)
            }
            Spacer()
            TextField("", text: $location)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(PoolColor.primaryText)
                .tint(PoolColor.poolTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 140)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PoolColor.divider, lineWidth: 1)
                )
            Button {
                locationService.requestWhenInUseLocation()
            } label: {
                Image(systemName: locationService.isLocating ? "location.circle" : "location.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PoolColor.poolTeal)
                    .frame(width: 32, height: 32)
                    .background(PoolColor.poolTeal.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("Use current location")
        }
    }

    private var chlorinePreferenceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Chlorine")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)

            Picker("Chlorine", selection: $chlorinePreference) {
                ForEach(ChlorinePreference.options(isSaltwater: isSaltwater)) { option in
                    Text(option.displayName)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(PoolColor.poolTeal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(PoolColor.divider)
            .frame(height: 1)
    }

    private func setupSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(PoolColor.primaryText)
            VStack(spacing: 12) {
                content()
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }

    private func textRow(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)
            Spacer()
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(PoolColor.primaryText)
                .tint(PoolColor.poolTeal)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: 190)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PoolColor.divider, lineWidth: 1)
                )
        }
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

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)
        }
        .tint(PoolColor.poolTeal)
    }

    private func pickerRow<Option: Identifiable & Hashable>(_ title: String, selection: Binding<Option>, options: [Option]) -> some View where Option.ID == String {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PoolColor.primaryText)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(displayName(for: option))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(PoolColor.poolTeal)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayName<Option>(for option: Option) -> String {
        switch option {
        case let value as PoolType: return value.displayName
        case let value as SurfaceType: return value.displayName
        case let value as TestMethod: return value.displayName
        case let value as LiquidDropKitBrand: return value.displayName
        case let value as PHIncreaserPreference: return value.displayName
        case let value as PHDecreaserPreference: return value.displayName
        case let value as AlkalinityIncreaserPreference: return value.displayName
        case let value as CalciumIncreaserPreference: return value.displayName
        case let value as StabilizerPreference: return value.displayName
        default: return String(describing: option)
        }
    }

    private func loadDefaults() {
        let config = viewModel.poolConfig
        poolName = config.name
        volumeGallons = config.volumeGallons
        poolType = config.poolType
        surfaceType = config.surfaceType
        testMethod = config.testMethod
        liquidDropKitBrand = config.liquidDropKitBrand
        isSaltwater = config.isSaltwater
        hasCover = config.hasCover
        petsRegularlySwim = config.petsRegularlySwim
        usesRoboticCleaner = config.usesRoboticCleaner
        if PoolConfiguration.isConfigured {
            enableNextPoolTestReminders = config.enableNextPoolTestReminders
            enableTreatmentStepReminders = config.enableTreatmentStepReminders
        } else {
            enableNextPoolTestReminders = false
            enableTreatmentStepReminders = false
        }
        chlorinePreference = config.chlorinePreference.isValidForSaltwater(config.isSaltwater)
            ? config.chlorinePreference
            : ChlorinePreference.options(isSaltwater: config.isSaltwater).first ?? .liquidChlorine10
        lastNonSaltChlorinePreference = config.lastNonSaltChlorinePreference
        pHIncreaserPreference = config.pHIncreaserPreference
        pHDecreaserPreference = config.pHDecreaserPreference
        alkalinityIncreaserPreference = config.alkalinityIncreaserPreference
        calciumIncreaserPreference = config.calciumIncreaserPreference
        stabilizerPreference = config.stabilizerPreference
        location = config.location
        latitude = config.latitude
        longitude = config.longitude
    }

    private func requestNotificationPermissionIfNeeded(_ enabled: Bool) {
        guard enabled else { return }
        Task {
            let granted = await NotificationService.shared.requestPermission()
            if !granted {
                enableNextPoolTestReminders = false
                enableTreatmentStepReminders = false
            }
        }
    }

    private func updateSaltMode(_ enabled: Bool) {
        var config = currentConfig
        config.setSaltwater(enabled)
        chlorinePreference = config.chlorinePreference
        lastNonSaltChlorinePreference = config.lastNonSaltChlorinePreference
    }

    private func saveAndContinue() {
        viewModel.saveConfig(currentConfig)
        onComplete()
    }
}

struct FirstTestEmptyDashboardView: View {
    let onAddFirstTest: () -> Void
    var isTransitioning: Bool = false
    var plusNamespace: Namespace.ID?

    private let buttonSize: CGFloat = 82

    var body: some View {
        ZStack {
            PoolColor.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                VStack(spacing: 22) {
                    Image("Test Data Hero")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        Text("Find out if your pool is swim ready")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(PoolColor.primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Start with a water test. Pool Side will tell you what to do next and when it’s ready to swim.")
                            .font(.body)
                            .foregroundStyle(PoolColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    addButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
    }

    @ViewBuilder
    private var addButton: some View {
        let button = Button(action: onAddFirstTest) {
            ZStack {
                Circle()
                    .fill(PoolColor.sunshine)
                    .frame(width: buttonSize, height: buttonSize)
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .shadow(color: PoolColor.sunshine.opacity(0.35), radius: 14, y: 8)
        }
        .disabled(isTransitioning)
        .accessibilityLabel("Add your first pool test")

        if let plusNamespace {
            button.matchedGeometryEffect(id: "firstUsePlus", in: plusNamespace)
        } else {
            button
        }
    }
}
