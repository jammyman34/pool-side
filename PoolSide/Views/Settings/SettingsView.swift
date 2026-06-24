import SwiftUI
import CoreLocation
import Observation
import UIKit

struct SettingsView: View {

    @Environment(PoolViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    // Pool Settings
    @State private var poolName: String = ""
    @State private var volumeGallons: Double = 15000
    @State private var poolType: PoolType = .inground
    @State private var surfaceType: SurfaceType = .plaster
    @State private var testMethod: TestMethod = .testStrips
    @State private var liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD
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
    @State private var originalConfig: PoolConfiguration? = nil

    @State private var showLocationToast: Bool = false
    @State private var locationToastMessage: String = ""
    @State private var showingFeedback: Bool = false

    private var currentConfig: PoolConfiguration {
        PoolConfiguration(
            name: poolName.isEmpty ? "My Pool" : poolName,
            volumeGallons: volumeGallons,
            poolType: poolType,
            surfaceType: surfaceType,
            testMethod: testMethod,
            liquidDropKitBrand: liquidDropKitBrand,
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
    }

    private var hasUnsavedChanges: Bool {
        guard let originalConfig else { return false }
        return currentConfig != originalConfig
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Pool Settings section
                        sectionCard(header: "Pool Settings") {
                            VStack(spacing: 0) {
                                poolProfileRow
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

                        feedbackCard
                        versionFooter
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }

                if showLocationToast {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: locationService.isLocating ? "location.circle" : "checkmark.circle.fill")
                                .foregroundStyle(locationService.isLocating ? PoolColor.poolTeal : PoolColor.statusIdeal)
                            Text(locationToastMessage)
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.primaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        .padding(.top, 12)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showLocationToast)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(PoolColor.poolTeal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(hasUnsavedChanges ? PoolColor.poolTeal : PoolColor.secondaryText)
                    .disabled(!hasUnsavedChanges)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    .foregroundStyle(PoolColor.poolTeal)
                }
            }
            .sheet(isPresented: $showingVolumeHelp) {
                PoolVolumeHelpView(
                    poolType: $poolType,
                    surfaceType: $surfaceType,
                    volumeGallons: $volumeGallons
                )
            }
            .sheet(isPresented: $showingFeedback) {
                FeedbackSheet(recipientEmail: "justinmandell@gmail.com")
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
        .onChange(of: locationService.isLocating) { _, locating in
            if locating {
                locationToastMessage = "Requesting current location…"
                withAnimation { showLocationToast = true }
            } else if showLocationToast && locationService.errorMessage == nil && !locationService.resolvedLocationText.isEmpty {
                locationToastMessage = "Location updated"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation { showLocationToast = false }
                }
            }
        }
        .onChange(of: locationService.errorMessage) { _, newError in
            if let msg = newError, !msg.isEmpty {
                locationToastMessage = msg
                withAnimation { showLocationToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { showLocationToast = false }
                }
            }
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

    private var feedbackButton: some View {
        Button {
            showingFeedback = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.poolTeal)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Feedback")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.primaryText)
                    Text("Share issues, ideas, or chemistry recommendations.")
                        .font(.caption)
                        .foregroundStyle(PoolColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var feedbackCard: some View {
        feedbackButton
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var versionFooter: some View {
        Text("Version \(appVersion)")
            .font(.caption)
            .foregroundStyle(PoolColor.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    locationToastMessage = "Requesting current location…"
                    withAnimation { showLocationToast = true }
                    locationService.requestWhenInUseLocation()
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
            Text("Testing Method")
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)

            HStack {
                Picker("Testing Method", selection: $testMethod) {
                    ForEach(TestMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.menu)
                .tint(PoolColor.poolTeal)
                .labelsHidden()

                Spacer(minLength: 0)
            }

            if testMethod == .liquidDropKit {
                Text("Brand")
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                    .padding(.top, 4)

                HStack {
                    Picker("Liquid Drop Kit Brand", selection: $liquidDropKitBrand) {
                        ForEach(LiquidDropKitBrand.allCases) { brand in
                            HStack {
                                brand.icon
                                Text(brand.rawValue)
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

    private var poolProfileRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Pool")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)

                Spacer()

                Button {
                    showingVolumeHelp = true
                } label: {
                    Text(volumeGallons > 0 ? "Edit" : "Set Up")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(PoolColor.poolTeal)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                poolSummaryItem(label: "Type", value: poolType.displayName)
                poolSummaryItem(label: "Surface", value: surfaceType.displayName)
                poolSummaryItem(label: "Volume", value: "\(Int(volumeGallons).formatted()) gallons")
            }

            Text("Pool type, surface, and gallons are used for treatment amounts.")
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private func poolSummaryItem(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(PoolColor.secondaryText)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.primaryText)
                .multilineTextAlignment(.trailing)
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

    // MARK: - Actions

    private func loadCurrentConfig() {
        let config = viewModel.poolConfig
        poolName = config.name
        volumeGallons = config.volumeGallons
        poolType = config.poolType
        surfaceType = config.surfaceType
        testMethod = config.testMethod
        liquidDropKitBrand = config.liquidDropKitBrand
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
        originalConfig = currentConfig
    }

    private func save() {
        viewModel.saveConfig(currentConfig)
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

// MARK: - Feedback Sheet

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let recipientEmail: String

    @State private var name: String = ""
    @State private var contactEmail: String = ""
    @State private var message: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case email
        case message
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your feedback helps make Pool Side more accurate and useful.")
                                .font(.subheadline)
                                .foregroundStyle(PoolColor.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)

                            feedbackTextField(
                                title: "First name",
                                placeholder: "Optional",
                                text: $name,
                                field: .name
                            )
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)

                            feedbackTextField(
                                title: "Email",
                                placeholder: "Optional, but helpful if I need to reply",
                                text: $contactEmail,
                                field: .email
                            )
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            messageField
                        }
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 112)
                }
                .scrollDismissesKeyboard(.interactively)

                sendButton
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(focusedField != nil)
    }

    private func feedbackTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)

            TextField(placeholder, text: text)
                .font(.subheadline)
                .foregroundStyle(PoolColor.primaryText)
                .tint(PoolColor.poolTeal)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focusedField == field ? PoolColor.poolTeal.opacity(0.55) : PoolColor.divider, lineWidth: 1)
                )
        }
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Message")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                    .tint(PoolColor.poolTeal)
                    .focused($focusedField, equals: .message)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)

                if message.isEmpty {
                    Text("Tell me what happened or what would make the app better.")
                        .font(.subheadline)
                        .foregroundStyle(PoolColor.secondaryText.opacity(0.75))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focusedField == .message ? PoolColor.poolTeal.opacity(0.55) : PoolColor.divider, lineWidth: 1)
            )
        }
    }

    private var sendButton: some View {
        Button {
            sendFeedback()
        } label: {
            Text("Send Feedback")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSend ? PoolColor.poolTeal : PoolColor.secondaryText.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(!canSend)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipientEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Pool Side Feedback"),
            URLQueryItem(name: "body", value: emailBody)
        ]

        guard let url = components.url else { return }
        openURL(url)
        dismiss()
    }

    private var emailBody: String {
        """
        Name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))
        Contact email: \(contactEmail.trimmingCharacters(in: .whitespacesAndNewlines))

        Message:
        \(message.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}

// MARK: - Pool Volume Help Sheet

struct PoolVolumeHelpView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding private var savedPoolType: PoolType
    @Binding private var savedSurfaceType: SurfaceType
    @Binding private var savedVolumeGallons: Double

    @State private var poolType: PoolType
    @State private var surfaceType: SurfaceType
    @State private var selectedShape: PoolShape = .rectangular
    @State private var lengthFeet: Double = 0
    @State private var widthFeet: Double = 0
    @State private var diameterFeet: Double = 0
    @State private var largeDiameterFeet: Double = 0
    @State private var smallDiameterFeet: Double = 0
    @State private var overallLengthFeet: Double = 0
    @State private var shallowDepthFeet: Double = 0
    @State private var deepDepthFeet: Double = 0
    @State private var waterDepthFeet: Double = 0
    @State private var focusedFieldID: String?

    private var effectiveShape: PoolShape {
        poolType == .inground ? selectedShape : .circular
    }

    init(
        poolType: Binding<PoolType>,
        surfaceType: Binding<SurfaceType>,
        volumeGallons: Binding<Double>
    ) {
        _savedPoolType = poolType
        _savedSurfaceType = surfaceType
        _savedVolumeGallons = volumeGallons
        _poolType = State(initialValue: poolType.wrappedValue)
        _surfaceType = State(initialValue: surfaceType.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PoolColor.appBackground.ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            poolDetailsCard

                            if poolType == .inground {
                                shapePicker
                            } else {
                                fixedShapeCard
                            }

                            measurementCard
                            inputCard
                            resultCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 104)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: focusedFieldID) { _, newID in
                        guard let newID else { return }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }

                saveButton
            }
            .navigationTitle("Pool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("Close")
                    .foregroundStyle(PoolColor.poolTeal)
                }
            }
            .onAppear {
                configureInitialShape()
            }
            .onChange(of: poolType) { _, _ in
                configureInitialShape()
            }
        }
    }

    private var poolDetailsCard: some View {
        VStack(spacing: 0) {
            poolPickerRow(label: "Pool Type", selection: $poolType)
            Rectangle()
                .fill(PoolColor.divider)
                .frame(height: 1)
                .padding(.leading, 18)
            poolPickerRow(label: "Surface", selection: $surfaceType)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func poolPickerRow<T: CaseIterable & Identifiable & Hashable & CustomStringConvertible>(
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
        .padding(.vertical, 8)
    }

    private var shapePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pool Shape")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(PoolShape.allCases) { shape in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedShape = shape
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(shape.smallAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 32)
                                .accessibilityHidden(true)
                            Text(shape.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .fontWeight(.semibold)
                                .foregroundStyle(PoolColor.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedShape == shape ? PoolColor.poolTeal.opacity(0.1) : Color.white,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedShape == shape ? PoolColor.poolTeal : PoolColor.divider, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            selectedShapeDiagram
        }
    }

    private var fixedShapeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Circular Pool")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(PoolColor.primaryText)
                Text(poolType == .spa ? "Most spas and hot tubs are estimated from diameter and average water depth." : "Most above-ground pools use the round-pool volume formula.")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
            }

            selectedShapeDiagram
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var selectedShapeDiagram: some View {
        Image(effectiveShape.assetName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(PoolColor.divider, lineWidth: 1)
            }
            .accessibilityLabel("\(effectiveShape.displayName) pool measurement diagram")
    }

    private var measurementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to measure", systemImage: "ruler")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.poolTeal)

            ForEach(Array(effectiveShape.measurementSteps(for: poolType).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(PoolColor.poolTeal, in: Circle())
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(PoolColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Measurements")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(PoolColor.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.bottom, 8)

            ForEach(Array(measurementFields.enumerated()), id: \.element.id) { index, field in
                measurementRow(field)

                if index < measurementFields.count - 1 {
                    Rectangle()
                        .fill(PoolColor.divider)
                        .frame(height: 1)
                        .padding(.leading, 18)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var resultCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimated Volume")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
                Text(calculatedVolume.map { "\(Int($0.rounded()).formatted()) gallons" } ?? "Enter measurements")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(calculatedVolume == nil ? PoolColor.secondaryText : PoolColor.poolTeal)
                    .monospacedDigit()
            }

            Spacer()

            Image(systemName: calculatedVolume == nil ? "drop" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(calculatedVolume == nil ? PoolColor.secondaryText : PoolColor.statusIdeal)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var saveButton: some View {
        Button {
            savedPoolType = poolType
            savedSurfaceType = surfaceType
            if let calculatedVolume {
                savedVolumeGallons = calculatedVolume.rounded()
            }
            dismiss()
        } label: {
            Text("Save")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
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
    }

    private var measurementFields: [VolumeMeasurementField] {
        if poolType != .inground {
            return [.diameter, .waterDepth]
        }

        switch effectiveShape {
        case .rectangular, .oval:
            return [.width, .length, .shallowDepth, .deepDepth]
        case .oblongKidney:
            return [.largeDiameter, .smallDiameter, .overallLength, .shallowDepth, .deepDepth]
        case .circular:
            return [.diameter, .shallowDepth, .deepDepth]
        }
    }

    private var calculatedVolume: Double? {
        let averageDepth: Double
        if measurementFields.contains(.waterDepth) {
            guard waterDepthFeet > 0 else { return nil }
            averageDepth = waterDepthFeet
        } else {
            guard shallowDepthFeet > 0, deepDepthFeet > 0 else { return nil }
            averageDepth = (shallowDepthFeet + deepDepthFeet) / 2
        }

        let volume: Double
        switch effectiveShape {
        case .rectangular:
            guard lengthFeet > 0, widthFeet > 0 else { return nil }
            volume = lengthFeet * widthFeet * averageDepth * 7.48
        case .circular:
            guard diameterFeet > 0 else { return nil }
            volume = diameterFeet * diameterFeet * averageDepth * 5.9
        case .oval:
            guard lengthFeet > 0, widthFeet > 0 else { return nil }
            volume = lengthFeet * widthFeet * averageDepth * 5.9
        case .oblongKidney:
            guard largeDiameterFeet > 0, smallDiameterFeet > 0, overallLengthFeet > 0 else { return nil }
            volume = 0.45 * (largeDiameterFeet + smallDiameterFeet) * overallLengthFeet * averageDepth * 7.48
        }

        guard volume.isFinite, volume >= 100 else { return nil }
        return min(volume, 200_000)
    }

    private func measurementRow(_ field: VolumeMeasurementField) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.title(for: effectiveShape))
                    .font(.subheadline)
                    .foregroundStyle(PoolColor.primaryText)
                Text(field.helpText(for: effectiveShape, poolType: poolType))
                    .font(.caption2)
                    .foregroundStyle(PoolColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                SelectAllDecimalTextField(
                    value: binding(for: field),
                    onBeginEditing: { focusedFieldID = field.id }
                )
                .frame(width: 72)
                Text("ft")
                    .font(.caption)
                    .foregroundStyle(PoolColor.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PoolColor.appBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.vertical, 10)
        .id(field.id)
    }

    private func binding(for field: VolumeMeasurementField) -> Binding<Double> {
        switch field {
        case .length:
            return $lengthFeet
        case .width:
            return $widthFeet
        case .diameter:
            return $diameterFeet
        case .largeDiameter:
            return $largeDiameterFeet
        case .smallDiameter:
            return $smallDiameterFeet
        case .overallLength:
            return $overallLengthFeet
        case .shallowDepth:
            return $shallowDepthFeet
        case .deepDepth:
            return $deepDepthFeet
        case .waterDepth:
            return $waterDepthFeet
        }
    }

    private func configureInitialShape() {
        selectedShape = poolType == .inground ? .rectangular : .circular
    }
}

private enum PoolShape: String, CaseIterable, Identifiable {
    case rectangular
    case circular
    case oval
    case oblongKidney

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangular: return "Rectangular"
        case .circular: return "Circular"
        case .oval: return "Oval"
        case .oblongKidney: return "Oblong / Kidney"
        }
    }

    var assetName: String {
        switch self {
        case .rectangular: return "Rectangular Pool"
        case .circular: return "Circular Pool"
        case .oval: return "Oval Pool"
        case .oblongKidney: return "Oblong-Kidney Pool"
        }
    }

    var smallAssetName: String {
        switch self {
        case .rectangular: return "Rectangular Pool Small"
        case .circular: return "Circular Pool Small"
        case .oval: return "Oval Pool Small"
        case .oblongKidney: return "Oblong-Kidney Pool Small"
        }
    }

    func measurementSteps(for poolType: PoolType) -> [String] {
        if poolType != .inground {
            return [
                "Measure the inside diameter across the water from wall to wall.",
                "Measure actual water depth, not the height of the pool wall.",
                "Use feet for both measurements. For example, 30 inches is 2.5 feet."
            ]
        }

        switch self {
        case .rectangular:
            return [
                "Measure width (A) and length (B) using the labels shown on the diagram.",
                "Measure shallow and deep water depth at the depth indicator points shown on the diagram.",
                "Use actual water depth from the waterline to the pool floor."
            ]
        case .circular:
            return [
                "Measure diameter (A) across the widest point of the water.",
                "Measure shallow and deep water depth if the pool floor slopes.",
                "If the depth is uniform, enter the same number for shallow and deep."
            ]
        case .oval:
            return [
                "Measure width (A) and length (B) using the labels shown on the diagram.",
                "Measure shallow and deep water depth at the depth indicator points shown on the diagram.",
                "Use actual water depth from the waterline to the pool floor."
            ]
        case .oblongKidney:
            return [
                "Measure large diameter (A) and small diameter (B), treating the pool like two connected circles.",
                "Measure length (C) across the full pool from end to end.",
                "Measure shallow and deep water depth at the depth indicator points shown on the diagram."
            ]
        }
    }
}

private enum VolumeMeasurementField: String, Identifiable {
    case length
    case width
    case diameter
    case largeDiameter
    case smallDiameter
    case overallLength
    case shallowDepth
    case deepDepth
    case waterDepth

    var id: String { rawValue }

    func title(for shape: PoolShape) -> String {
        switch self {
        case .length: return shape == .oval || shape == .rectangular ? "Length (B)" : "Length"
        case .width: return shape == .oval || shape == .rectangular ? "Width (A)" : "Width"
        case .diameter: return "Diameter (A)"
        case .largeDiameter: return "Large Diameter (A)"
        case .smallDiameter: return "Small Diameter (B)"
        case .overallLength: return "Length (C)"
        case .shallowDepth: return "Shallow End Depth"
        case .deepDepth: return "Deep End Depth"
        case .waterDepth: return "Water Depth"
        }
    }

    func helpText(for shape: PoolShape, poolType: PoolType) -> String {
        switch self {
        case .length:
            return shape == .oblongKidney ? "Longest overall inside measurement." : "Inside water length, wall to wall."
        case .width:
            return shape == .oblongKidney ? "Widest overall inside measurement." : "Inside water width at the widest point."
        case .diameter:
            return "Inside water width across the center."
        case .largeDiameter:
            return "Inside diameter of the larger rounded end."
        case .smallDiameter:
            return "Inside diameter of the smaller rounded end."
        case .overallLength:
            return "Full inside length across both rounded ends."
        case .shallowDepth:
            return "Measure from waterline to floor at the shallow depth indicator."
        case .deepDepth:
            return "Measure from waterline to floor at the deep depth indicator."
        case .waterDepth:
            return poolType == .spa ? "Average water depth inside the spa." : "Actual water depth, not wall height."
        }
    }
}

private struct SelectAllDecimalTextField: UIViewRepresentable {
    @Binding var value: Double
    var onBeginEditing: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = UIColor(PoolColor.primaryText)
        textField.clearButtonMode = .never
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onBeginEditing = onBeginEditing

        let formattedText = Self.format(value)
        if uiView.text != formattedText, !uiView.isFirstResponder {
            uiView.text = formattedText
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onBeginEditing: onBeginEditing)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : String(format: "%.2f", value).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var value: Double
        var onBeginEditing: (() -> Void)?

        init(value: Binding<Double>, onBeginEditing: (() -> Void)?) {
            _value = value
            self.onBeginEditing = onBeginEditing
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            let current = textField.text ?? ""
            if current.isEmpty || Double(current) == 0 {
                textField.text = ""
                if value != 0 { value = 0 }
            } else {
                DispatchQueue.main.async {
                    textField.selectAll(nil)
                }
            }
            onBeginEditing?()
        }

        @objc func textDidChange(_ textField: UITextField) {
            let text = textField.text ?? ""
            value = Double(text) ?? 0
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
        print("[Location] Request when-in-use — current auth: \(manager.authorizationStatus.rawValue)")
        errorMessage = nil
        isLocating = true

        switch manager.authorizationStatus {
        case .notDetermined:
            print("[Location] Requesting authorization")
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            print("[Location] Authorized — requesting one-time location")
            manager.requestLocation()
        case .denied, .restricted:
            print("[Location] Authorization denied/restricted")
            isLocating = false
            errorMessage = "Location access is off for Pool Side. You can still type your location manually."
        @unknown default:
            print("[Location] Unknown authorization state")
            isLocating = false
            errorMessage = "Location is unavailable right now."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("[Location] Authorization changed: \(manager.authorizationStatus.rawValue)")
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("[Location] Now authorized — requesting location")
            manager.requestLocation()
        case .denied, .restricted:
            print("[Location] Now denied/restricted")
            isLocating = false
            errorMessage = "Location access is off for Pool Side. You can still type your location manually."
        case .notDetermined:
            break
        @unknown default:
            isLocating = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("[Location] didUpdateLocations count=\(locations.count)")
        guard let location = locations.last else {
            isLocating = false
            return
        }

        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        print(String(format: "[Location] Coordinates resolved: %.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))

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
                    print("[Location] Reverse geocoded: \(resolved)")
                } else {
                    service.resolvedLocationText = String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
                    if error != nil {
                        service.errorMessage = "Could not name this location, so coordinates were saved instead."
                    }
                    print("[Location] Reverse geocode failed — using coordinates")
                }

                service.isLocating = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] didFailWithError: \(error.localizedDescription)")
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
    PoolVolumeHelpView(
        poolType: .constant(.inground),
        surfaceType: .constant(.plaster),
        volumeGallons: .constant(15_000)
    )
}
