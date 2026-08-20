import Foundation
import os

/// Pool configuration stored in UserDefaults via AppStorage.
/// Not a SwiftData model — settings are single-instance, not queried.
struct PoolConfiguration: Codable, Equatable {

    var name: String = "My Pool"
    var volumeGallons: Double = 15000
    var poolType: PoolType = .inground
    var surfaceType: SurfaceType = .plaster
    var testMethod: TestMethod = .testStrips
    var liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD
    var isSaltwater: Bool = false
    var hasCover: Bool = false
    var petsRegularlySwim: Bool = false
    var usesRoboticCleaner: Bool = false
    var enableNextPoolTestReminders: Bool = true
    var enableTreatmentStepReminders: Bool = true
    var chlorinePreference: ChlorinePreference = .calHypo
    var lastNonSaltChlorinePreference: ChlorinePreference = .liquidChlorine10
    var pHIncreaserPreference: PHIncreaserPreference = .sodaAsh
    var pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid
    var alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate
    var calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride
    var stabilizerPreference: StabilizerPreference = .granularCYA
    var location: String = ""
    var latitude: Double?
    var longitude: Double?

    init(
        name: String = "My Pool",
        volumeGallons: Double = 15000,
        poolType: PoolType = .inground,
        surfaceType: SurfaceType = .plaster,
        testMethod: TestMethod = .testStrips,
        liquidDropKitBrand: LiquidDropKitBrand = .taylorK2006FASDPD,
        isSaltwater: Bool = false,
        hasCover: Bool = false,
        petsRegularlySwim: Bool = false,
        usesRoboticCleaner: Bool = false,
        enableNextPoolTestReminders: Bool = true,
        enableTreatmentStepReminders: Bool = true,
        chlorinePreference: ChlorinePreference = .calHypo,
        lastNonSaltChlorinePreference: ChlorinePreference = .liquidChlorine10,
        pHIncreaserPreference: PHIncreaserPreference = .sodaAsh,
        pHDecreaserPreference: PHDecreaserPreference = .muriaticAcid,
        alkalinityIncreaserPreference: AlkalinityIncreaserPreference = .sodiumBicarbonate,
        calciumIncreaserPreference: CalciumIncreaserPreference = .calciumChloride,
        stabilizerPreference: StabilizerPreference = .granularCYA,
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.name = name
        self.volumeGallons = volumeGallons
        self.poolType = poolType
        self.surfaceType = surfaceType
        self.testMethod = testMethod
        self.liquidDropKitBrand = liquidDropKitBrand
        self.isSaltwater = isSaltwater
        self.hasCover = hasCover
        self.petsRegularlySwim = petsRegularlySwim
        self.usesRoboticCleaner = usesRoboticCleaner
        self.enableNextPoolTestReminders = enableNextPoolTestReminders
        self.enableTreatmentStepReminders = enableTreatmentStepReminders
        self.chlorinePreference = chlorinePreference
        self.lastNonSaltChlorinePreference = lastNonSaltChlorinePreference
        self.pHIncreaserPreference = pHIncreaserPreference
        self.pHDecreaserPreference = pHDecreaserPreference
        self.alkalinityIncreaserPreference = alkalinityIncreaserPreference
        self.calciumIncreaserPreference = calciumIncreaserPreference
        self.stabilizerPreference = stabilizerPreference
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = container.decodeLossy(String.self, forKey: .name, default: "My Pool")
        volumeGallons = container.decodeLossy(Double.self, forKey: .volumeGallons, default: 15000)
        poolType = container.decodeLossy(PoolType.self, forKey: .poolType, default: .inground)
        surfaceType = container.decodeLossy(SurfaceType.self, forKey: .surfaceType, default: .plaster)
        testMethod = container.decodeLossy(TestMethod.self, forKey: .testMethod, default: .testStrips)
        liquidDropKitBrand = container.decodeLossy(LiquidDropKitBrand.self, forKey: .liquidDropKitBrand, default: .taylorK2006FASDPD)
        isSaltwater = container.decodeLossy(Bool.self, forKey: .isSaltwater, default: false)
        hasCover = container.decodeLossy(Bool.self, forKey: .hasCover, default: false)
        petsRegularlySwim = container.decodeLossy(Bool.self, forKey: .petsRegularlySwim, default: false)
        usesRoboticCleaner = container.decodeLossy(Bool.self, forKey: .usesRoboticCleaner, default: false)
        enableNextPoolTestReminders = container.decodeLossy(Bool.self, forKey: .enableNextPoolTestReminders, default: true)
        enableTreatmentStepReminders = container.decodeLossy(Bool.self, forKey: .enableTreatmentStepReminders, default: true)
        chlorinePreference = container.decodeLossy(ChlorinePreference.self, forKey: .chlorinePreference, default: .calHypo)
        lastNonSaltChlorinePreference = container.decodeLossy(ChlorinePreference.self, forKey: .lastNonSaltChlorinePreference, default: chlorinePreference.isSaltGenerator ? .liquidChlorine10 : chlorinePreference)
        pHIncreaserPreference = container.decodeLossy(PHIncreaserPreference.self, forKey: .pHIncreaserPreference, default: .sodaAsh)
        pHDecreaserPreference = container.decodeLossy(PHDecreaserPreference.self, forKey: .pHDecreaserPreference, default: .muriaticAcid)
        alkalinityIncreaserPreference = container.decodeLossy(AlkalinityIncreaserPreference.self, forKey: .alkalinityIncreaserPreference, default: .sodiumBicarbonate)
        calciumIncreaserPreference = container.decodeLossy(CalciumIncreaserPreference.self, forKey: .calciumIncreaserPreference, default: .calciumChloride)
        stabilizerPreference = container.decodeLossy(StabilizerPreference.self, forKey: .stabilizerPreference, default: .granularCYA)
        location = container.decodeLossy(String.self, forKey: .location, default: "")
        latitude = container.decodeLossyIfPresent(Double.self, forKey: .latitude)
        longitude = container.decodeLossyIfPresent(Double.self, forKey: .longitude)
        normalizeChemicalPreferences()
    }

    // MARK: - Persistence key
    static let defaultsKey = "poolConfiguration"
    static let hasCoverBackupKey = "poolConfiguration.hasCover.backup"
    static let usesRoboticCleanerBackupKey = "poolConfiguration.usesRoboticCleaner.backup"
    static let hasCoverExplicitChoiceKey = "poolConfiguration.hasCover.explicitChoice"
    static let usesRoboticCleanerExplicitChoiceKey = "poolConfiguration.usesRoboticCleaner.explicitChoice"

    /// The stored configuration when one is present AND decodable, otherwise `nil`. Callers that
    /// read-modify-write MUST use this (not `current`) so a missing/invalid load is never silently
    /// re-persisted as struct defaults (e.g. Cal-Hypo / Muriatic). `current` keeps its default-fallback
    /// behavior for read-only display, but distinguishing "no valid config" is what makes writers safe.
    static var persisted: PoolConfiguration? {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decodedConfig = try? JSONDecoder().decode(PoolConfiguration.self, from: data)
        else { return nil }
        return recoveredEquipmentSettings(in: decodedConfig)
    }

    static var current: PoolConfiguration {
        get { persisted ?? recoveredEquipmentSettings(in: PoolConfiguration()) }
        set {
            // TEMP DIAGNOSTIC — remove before App Store submission. Every write to the persisted
            // poolConfiguration funnels through this setter, so this is the single choke point that can
            // catch a stale/default full-struct write clobbering the user's saved preferences. See
            // `logConfigurationWrite(_:)` for what is captured and how to read it.
            logConfigurationWrite(newValue)

            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            if newValue.hasCover {
                UserDefaults.standard.set(true, forKey: hasCoverBackupKey)
            }
            if newValue.usesRoboticCleaner {
                UserDefaults.standard.set(true, forKey: usesRoboticCleanerBackupKey)
            }
        }
    }

    /// Whether configuration has been saved at least once
    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: defaultsKey) != nil
    }

    static func markEquipmentChoicesExplicit(_ config: PoolConfiguration) {
        UserDefaults.standard.set(true, forKey: hasCoverExplicitChoiceKey)
        UserDefaults.standard.set(true, forKey: usesRoboticCleanerExplicitChoiceKey)
        UserDefaults.standard.set(config.hasCover, forKey: hasCoverBackupKey)
        UserDefaults.standard.set(config.usesRoboticCleaner, forKey: usesRoboticCleanerBackupKey)
    }

    static func recoveredFromTestHistory(_ config: PoolConfiguration, tests: [PoolTest]) -> PoolConfiguration {
        var recovered = recoveredEquipmentSettings(in: config)
        if
            !recovered.hasCover,
            !UserDefaults.standard.bool(forKey: hasCoverExplicitChoiceKey),
            tests.contains(where: { $0.resolvedPoolConditions.coverOpenTime != .unknown }) {
            recovered.hasCover = true
        }
        if
            !recovered.usesRoboticCleaner,
            !UserDefaults.standard.bool(forKey: usesRoboticCleanerExplicitChoiceKey),
            tests.contains(where: { $0.resolvedPoolConditions.cleaningActivity.isRoboticCleanerEvidence }) {
            recovered.usesRoboticCleaner = true
        }
        return recovered
    }

    // MARK: - TEMP DIAGNOSTIC (remove before App Store submission)

    /// Traces every write to the persisted poolConfiguration so a stale/default overwrite of the user's
    /// saved preferences can be caught on the next reproduction. Logs via the unified logging system so it
    /// is retrievable from a physical device (Console.app or `log collect`) in any build configuration,
    /// not only when attached to Xcode.
    ///
    /// Reads with subsystem "PoolSide.ConfigDiagnostics", category "poolConfiguration". Flags the offending
    /// signature explicitly: a previously populated, non-default config being overwritten with struct
    /// defaults (Cal-Hypo / Muriatic / Test Strips).
    private static let diagnosticsLog = Logger(subsystem: "PoolSide.ConfigDiagnostics", category: "poolConfiguration")

    /// TEMP DIAGNOSTIC — remove before App Store submission. Rolling on-device history of the last
    /// ~20 configuration events (writes + clears), so an intermittent preference reset can be diagnosed
    /// later WITHOUT a live Console.app session. Stored under its own UserDefaults key — never the
    /// `poolConfiguration` key — and every access swallows errors so diagnostic storage can never affect
    /// real configuration behavior. Retrieve with `dumpDiagnosticHistory()` (see below).
    static let diagnosticHistoryKey = "poolConfiguration.diagnosticHistory.TEMP"
    private static let diagnosticHistoryCap = 20

    struct ConfigDiagnosticEvent: Codable, Equatable {
        enum EventType: String, Codable { case write, clear }
        let timestamp: Date
        let eventType: EventType
        let persistedExistedBefore: Bool
        let beforeChlorine: String?
        let afterChlorine: String?
        let beforePHDecreaser: String?
        let afterPHDecreaser: String?
        let beforeTestMethod: String?
        let afterTestMethod: String?
        let caller: String
    }

    /// The recorded diagnostic events, oldest first. Returns empty on any decode failure.
    static func diagnosticHistoryEntries() -> [ConfigDiagnosticEvent] {
        guard
            let data = UserDefaults.standard.data(forKey: diagnosticHistoryKey),
            let entries = try? JSONDecoder().decode([ConfigDiagnosticEvent].self, from: data)
        else { return [] }
        return entries
    }

    /// Clears the diagnostic history only. Does NOT touch the persisted configuration.
    static func clearDiagnosticHistory() {
        UserDefaults.standard.removeObject(forKey: diagnosticHistoryKey)
    }

    /// Appends one event to the capped rolling history. Fully isolated: any failure is swallowed so it
    /// can never influence the real configuration write/clear that is happening alongside it.
    private static func appendDiagnosticEvent(_ event: ConfigDiagnosticEvent) {
        var entries = diagnosticHistoryEntries()
        entries.append(event)
        if entries.count > diagnosticHistoryCap {
            entries.removeFirst(entries.count - diagnosticHistoryCap)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: diagnosticHistoryKey)
        }
    }

    private static func configFieldsDescription(_ config: PoolConfiguration) -> String {
        "\(config.chlorinePreference.rawValue) / \(config.pHDecreaserPreference.rawValue) / \(config.testMethod.rawValue)"
    }

    private static func isDefaultPreferenceTriple(_ config: PoolConfiguration) -> Bool {
        let defaults = PoolConfiguration()
        return config.chlorinePreference == defaults.chlorinePreference
            && config.pHDecreaserPreference == defaults.pHDecreaserPreference
            && config.testMethod == defaults.testMethod
    }

    private static func logConfigurationWrite(_ newValue: PoolConfiguration) {
        let existingData = UserDefaults.standard.data(forKey: defaultsKey)
        let persistedExistedBefore = existingData != nil
        let before = existingData.flatMap { try? JSONDecoder().decode(PoolConfiguration.self, from: $0) }

        let beforeDescription = before.map(configFieldsDescription) ?? "nil"
        let afterDescription = configFieldsDescription(newValue)
        let beforeWasNonDefault = before.map { !isDefaultPreferenceTriple($0) } ?? false
        let afterIsDefault = isDefaultPreferenceTriple(newValue)
        let suspectedReset = persistedExistedBefore && beforeWasNonDefault && afterIsDefault

        // Frames 0/1 are this function + the setter; the rest identify the actual caller/reason.
        let caller = Thread.callStackSymbols.dropFirst(2).prefix(10).joined(separator: " | ")

        appendDiagnosticEvent(ConfigDiagnosticEvent(
            timestamp: Date(),
            eventType: .write,
            persistedExistedBefore: persistedExistedBefore,
            beforeChlorine: before?.chlorinePreference.rawValue,
            afterChlorine: newValue.chlorinePreference.rawValue,
            beforePHDecreaser: before?.pHDecreaserPreference.rawValue,
            afterPHDecreaser: newValue.pHDecreaserPreference.rawValue,
            beforeTestMethod: before?.testMethod.rawValue,
            afterTestMethod: newValue.testMethod.rawValue,
            caller: caller
        ))

        if suspectedReset {
            diagnosticsLog.fault("""
            ⚠️ SUSPECTED PREFERENCE RESET — writing struct defaults over a populated config.
            persistedExistedBefore=\(persistedExistedBefore, privacy: .public) \
            before=\(beforeDescription, privacy: .public) after=\(afterDescription, privacy: .public)
            caller=\(caller, privacy: .public)
            """)
        } else {
            diagnosticsLog.notice("""
            [CONFIG-WRITE] persistedExistedBefore=\(persistedExistedBefore, privacy: .public) \
            before=\(beforeDescription, privacy: .public) after=\(afterDescription, privacy: .public)
            caller=\(caller, privacy: .public)
            """)
        }
    }

    /// TEMP DIAGNOSTIC — remove before App Store submission. Logs and records every configuration event
    /// history so it can be inspected later. Returns the entries so a connected DEBUG session (Xcode
    /// console / `RunCodeSnippet`) can read them directly; also re-emits them through the unified log so a
    /// later `log collect` retrieves them without a live capture. `#if DEBUG` only.
    #if DEBUG
    @discardableResult
    static func dumpDiagnosticHistory() -> [ConfigDiagnosticEvent] {
        let entries = diagnosticHistoryEntries()
        let formatter = ISO8601DateFormatter()
        diagnosticsLog.notice("[CONFIG-HISTORY] \(entries.count, privacy: .public) event(s) recorded (oldest first):")
        for (index, event) in entries.enumerated() {
            diagnosticsLog.notice("""
            [CONFIG-HISTORY \(index + 1, privacy: .public)/\(entries.count, privacy: .public)] \
            \(formatter.string(from: event.timestamp), privacy: .public) \(event.eventType.rawValue, privacy: .public) \
            existedBefore=\(event.persistedExistedBefore, privacy: .public) \
            chlorine=\(event.beforeChlorine ?? "nil", privacy: .public)->\(event.afterChlorine ?? "nil", privacy: .public) \
            pHDecreaser=\(event.beforePHDecreaser ?? "nil", privacy: .public)->\(event.afterPHDecreaser ?? "nil", privacy: .public) \
            testMethod=\(event.beforeTestMethod ?? "nil", privacy: .public)->\(event.afterTestMethod ?? "nil", privacy: .public) \
            caller=\(event.caller, privacy: .public)
            """)
        }
        return entries
    }
    #endif

    /// Removes all saved configuration (sign out)
    static func clearCurrent() {
        // TEMP DIAGNOSTIC — remove before App Store submission. Records any removal of the persisted config
        // so an unexpected clear (which would drop the user back to defaults/first-use) is visible.
        let existing = persisted
        let caller = Thread.callStackSymbols.dropFirst(1).prefix(10).joined(separator: " | ")
        diagnosticsLog.fault("""
        ⚠️ clearCurrent() called — removing persisted poolConfiguration.
        caller=\(caller, privacy: .public)
        """)
        appendDiagnosticEvent(ConfigDiagnosticEvent(
            timestamp: Date(),
            eventType: .clear,
            persistedExistedBefore: existing != nil,
            beforeChlorine: existing?.chlorinePreference.rawValue,
            afterChlorine: nil,
            beforePHDecreaser: existing?.pHDecreaserPreference.rawValue,
            afterPHDecreaser: nil,
            beforeTestMethod: existing?.testMethod.rawValue,
            afterTestMethod: nil,
            caller: caller
        ))
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: hasCoverBackupKey)
        UserDefaults.standard.removeObject(forKey: usesRoboticCleanerBackupKey)
        UserDefaults.standard.removeObject(forKey: hasCoverExplicitChoiceKey)
        UserDefaults.standard.removeObject(forKey: usesRoboticCleanerExplicitChoiceKey)
    }

    private static func recoveredEquipmentSettings(in config: PoolConfiguration) -> PoolConfiguration {
        var recovered = config
        if !recovered.hasCover && UserDefaults.standard.bool(forKey: hasCoverBackupKey) {
            recovered.hasCover = true
        }
        if !recovered.usesRoboticCleaner && UserDefaults.standard.bool(forKey: usesRoboticCleanerBackupKey) {
            recovered.usesRoboticCleaner = true
        }
        return recovered
    }

    mutating func setSaltwater(_ enabled: Bool) {
        if enabled {
            if !chlorinePreference.isSaltGenerator {
                lastNonSaltChlorinePreference = chlorinePreference
            }
            chlorinePreference = .saltGenerator
        } else {
            if !lastNonSaltChlorinePreference.isValidForSaltwater(false) {
                lastNonSaltChlorinePreference = .liquidChlorine10
            }
            if chlorinePreference.isSaltGenerator || !chlorinePreference.isValidForSaltwater(false) {
                chlorinePreference = lastNonSaltChlorinePreference
            }
        }
        isSaltwater = enabled
    }

    mutating func normalizeChemicalPreferences() {
        if chlorinePreference.isSaltGenerator && !isSaltwater {
            chlorinePreference = lastNonSaltChlorinePreference.isValidForSaltwater(false) ? lastNonSaltChlorinePreference : .liquidChlorine10
        }
        if isSaltwater && chlorinePreference == .tablets {
            lastNonSaltChlorinePreference = .tablets
            chlorinePreference = .saltGenerator
        }
        if !chlorinePreference.isSaltGenerator {
            lastNonSaltChlorinePreference = chlorinePreference
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossy<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue
    }

    func decodeLossyIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}

// MARK: - Supporting Enums

enum PoolType: String, CaseIterable, Codable, Identifiable {
    case inground    = "inground"
    case aboveGround = "above_ground"
    case spa         = "spa"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inground:    return "In-Ground"
        case .aboveGround: return "Above-Ground"
        case .spa:         return "Spa / Hot Tub"
        }
    }
}

enum SurfaceType: String, CaseIterable, Codable, Identifiable {
    case plaster   = "plaster"
    case vinyl     = "vinyl"
    case fiberglass = "fiberglass"
    case pebble    = "pebble"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plaster:    return "Plaster / Gunite"
        case .vinyl:      return "Vinyl Liner"
        case .fiberglass: return "Fiberglass"
        case .pebble:     return "Pebble / Aggregate"
        }
    }

    /// Recommended calcium hardness range varies by surface
    var calciumHardnessRange: ClosedRange<Double> {
        switch self {
        case .plaster, .pebble: return 200...400
        case .vinyl:             return 150...250
        case .fiberglass:        return 150...250
        }
    }
}

enum TestMethod: String, CaseIterable, Codable, Identifiable {
    case testStrips = "test_strips"
    case liquidDropKit = "liquid_drop_kit"
    case digitalTester = "digital_tester"
    case poolStore = "pool_store"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .testStrips: return "Test Strips"
        case .liquidDropKit: return "Liquid Drop Test Kit"
        case .digitalTester: return "Digital Meter / Photometer"
        case .poolStore: return "Pool Store Test"
        }
    }

    var systemImageName: String {
        switch self {
        case .testStrips:
            return "testtube.2"
        case .liquidDropKit:
            return "drop.fill"
        case .digitalTester:
            return "wave.3.forward"
        case .poolStore:
            return "building.2"
        }
    }

    var confidenceNote: String? {
        switch self {
        case .testStrips:
            return "Test strips can vary based on lighting, timing, and color matching. Borderline readings are treated as estimates, so confirm them before adding optional chemicals."
        case .liquidDropKit:
            return "Liquid drop tests are usually more consistent than strips, but clean tubes and exact drop counts still matter."
        case .digitalTester:
            return "Digital meters and photometers are generally consistent when calibrated, cleaned, and stored correctly."
        case .poolStore:
            return "Pool store tests are useful reference points, but the app still compares them against your treatment history before recommending more chemicals."
        }
    }

    var shouldSuppressOptionalTreatments: Bool {
        self == .testStrips
    }

    var usesBrandPicker: Bool {
        self == .liquidDropKit || self == .digitalTester
    }
}

enum LiquidDropKitBrand: String, CaseIterable, Codable, Identifiable {
    case taylorK2006FASDPD = "Taylor K-2006 FAS-DPD"
    case taylorK2005 = "Taylor K-2005"
    case hachColorQ = "Hach ColorQ"
    case jblProColorimeter = "JBL Pro Colorimeter"
    case hannaChecker = "Hanna Checker"
    case poolLab = "PoolLab"
    case otherLiquidDropKit = "other_liquid_drop_kit"
    case otherDigitalMeter = "other_digital_meter"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .taylorK2006FASDPD:
            return "Taylor K-2006 / K-2006-SALT"
        case .taylorK2005:
            return "Taylor K-2005"
        case .hachColorQ:
            return "Hach ColorQ"
        case .jblProColorimeter:
            return "JBL Pro Colorimeter"
        case .hannaChecker:
            return "Hanna Checker"
        case .poolLab:
            return "PoolLab"
        case .otherLiquidDropKit, .otherDigitalMeter:
            return "Other"
        }
    }

    static func options(for testMethod: TestMethod) -> [LiquidDropKitBrand] {
        switch testMethod {
        case .liquidDropKit:
            return [.taylorK2006FASDPD, .taylorK2005, .otherLiquidDropKit]
        case .digitalTester:
            return [.hachColorQ, .hannaChecker, .poolLab, .otherDigitalMeter]
        default:
            return []
        }
    }

    static func defaultBrand(for testMethod: TestMethod) -> LiquidDropKitBrand {
        switch testMethod {
        case .digitalTester:
            return .hachColorQ
        default:
            return .taylorK2006FASDPD
        }
    }

    func isAvailable(for testMethod: TestMethod) -> Bool {
        Self.options(for: testMethod).contains(self)
    }
}

/// Sample-volume options for the Taylor K-2006 FAS-DPD chlorine titration.
/// 25 mL: 1 drop = 0.2 ppm. 10 mL: 1 drop = 0.5 ppm.
enum TaylorSampleSize: String, CaseIterable, Codable, Identifiable {
    case twentyFiveMl = "25mL"
    case tenMl = "10mL"

    var id: String { rawValue }

    var displayLabel: String { rawValue }

    var ppmPerDrop: Double {
        switch self {
        case .twentyFiveMl: return 0.2
        case .tenMl: return 0.5
        }
    }
}

enum ChlorinePreference: String, CaseIterable, Codable, Identifiable {
    case saltGenerator = "salt_generator"
    case tablets = "tablets"
    case calHypo = "cal_hypo"
    case liquidChlorine10 = "liquid_chlorine_10"
    case liquidChlorine12_5 = "liquid_chlorine_12_5"
    case dichlor = "dichlor"

    var id: String { rawValue }
    var productID: ChemicalProductID { ChemicalProductID(rawValue: rawValue) ?? .calHypoGranules }

    var displayName: String {
        switch self {
        case .saltGenerator: return "Salt Chlorine Generator"
        case .tablets: return "Chlorine Tablets (Trichlor)"
        case .calHypo: return "Cal-Hypo Granules"
        case .liquidChlorine10: return "Liquid Chlorine 10%"
        case .liquidChlorine12_5: return "Liquid Chlorine 12.5%"
        case .dichlor: return "Dichlor Granules"
        }
    }

    var isSaltGenerator: Bool { self == .saltGenerator }
    var isSaltCompatibleManualProduct: Bool {
        switch self {
        case .saltGenerator, .tablets:
            return false
        case .calHypo, .liquidChlorine10, .liquidChlorine12_5, .dichlor:
            return true
        }
    }

    static func options(isSaltwater: Bool) -> [ChlorinePreference] {
        isSaltwater
            ? [.saltGenerator, .liquidChlorine10, .liquidChlorine12_5, .calHypo, .dichlor]
            : [.liquidChlorine10, .liquidChlorine12_5, .tablets, .calHypo, .dichlor]
    }

    func isValidForSaltwater(_ isSaltwater: Bool) -> Bool {
        Self.options(isSaltwater: isSaltwater).contains(self)
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "salt_generator", "Salt Chlorine Generator":
            self = .saltGenerator
        case "tablets", "Chlorine Tablets", "Chlorine Tablets (Trichlor)":
            self = .tablets
        case "cal_hypo", "Chlorine Granules", "Cal-Hypo Granules":
            self = .calHypo
        case "liquid_chlorine_10", "Liquid Chlorine 10%":
            self = .liquidChlorine10
        case "liquid_chlorine_12_5", "Liquid Chlorine 12.5%":
            self = .liquidChlorine12_5
        case "dichlor", "Dichlor Granules":
            self = .dichlor
        default:
            self = .calHypo
        }
    }
}

enum PHIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case sodaAsh = "soda_ash"
    case borax = "borax"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sodaAsh: return "Soda Ash (Sodium Carbonate)"
        case .borax: return "Borax"
        }
    }

    var productID: ChemicalProductID { self == .sodaAsh ? .sodaAsh : .borax }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "soda_ash", "pH Increaser / Soda Ash", "Soda Ash (Sodium Carbonate)":
            self = .sodaAsh
        case "borax", "Borax":
            self = .borax
        default:
            self = .sodaAsh
        }
    }
}

enum PHDecreaserPreference: String, CaseIterable, Codable, Identifiable {
    case muriaticAcid = "muriatic_acid"
    case lowFumeMuriaticAcid = "low_fume_muriatic_acid"
    case dryAcid = "dry_acid"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .muriaticAcid: return "Muriatic Acid (31.45%)"
        case .lowFumeMuriaticAcid: return "Low-Fume Muriatic Acid (20%)"
        case .dryAcid: return "Dry Acid (Sodium Bisulfate)"
        }
    }

    var productID: ChemicalProductID {
        switch self {
        case .muriaticAcid: return .muriaticAcid31
        case .lowFumeMuriaticAcid: return .muriaticAcid20
        case .dryAcid: return .dryAcid
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "muriatic_acid", "pH Decreaser / Muriatic Acid", "Muriatic Acid (31.45%)":
            self = .muriaticAcid
        case "low_fume_muriatic_acid", "Low-Fume Muriatic Acid (20%)":
            self = .lowFumeMuriaticAcid
        case "dry_acid", "pH Decreaser / Dry Acid", "Dry Acid (Sodium Bisulfate)":
            self = .dryAcid
        default:
            self = .muriaticAcid
        }
    }
}

enum AlkalinityIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case sodiumBicarbonate = "sodium_bicarbonate"

    var id: String { rawValue }
    var displayName: String { "Baking Soda (Sodium Bicarbonate)" }
    var productID: ChemicalProductID { .bakingSoda }
}

enum CalciumIncreaserPreference: String, CaseIterable, Codable, Identifiable {
    case calciumChloride = "calcium_chloride"

    var id: String { rawValue }
    var displayName: String { "Calcium Chloride" }
    var productID: ChemicalProductID { .calciumChloride }
}

enum StabilizerPreference: String, CaseIterable, Codable, Identifiable {
    case granularCYA = "granular_cya"
    case liquidConditioner = "liquid_conditioner"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .granularCYA: return "Cyanuric Acid (Granular)"
        case .liquidConditioner: return "Liquid Stabilizer"
        }
    }

    var productID: ChemicalProductID { self == .granularCYA ? .granularCYA : .liquidStabilizer }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "granular_cya", "Pool Stabilizer Granules", "Cyanuric Acid (Granular)":
            self = .granularCYA
        case "liquid_conditioner", "Liquid Pool Stabilizer", "Liquid Stabilizer":
            self = .liquidConditioner
        default:
            self = .granularCYA
        }
    }
}

enum ChemicalProductID: String, Codable, CaseIterable, Identifiable {
    case saltGenerator = "salt_generator"
    case liquidChlorine10 = "liquid_chlorine_10"
    case liquidChlorine12_5 = "liquid_chlorine_12_5"
    case trichlorTablets = "tablets"
    case calHypoGranules = "cal_hypo"
    case dichlorGranules = "dichlor"
    case sodaAsh = "soda_ash"
    case borax = "borax"
    case muriaticAcid31 = "muriatic_acid"
    case muriaticAcid20 = "low_fume_muriatic_acid"
    case dryAcid = "dry_acid"
    case bakingSoda = "sodium_bicarbonate"
    case calciumChloride = "calcium_chloride"
    case granularCYA = "granular_cya"
    case liquidStabilizer = "liquid_conditioner"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .saltGenerator: return "Salt Chlorine Generator"
        case .liquidChlorine10: return "Liquid Chlorine 10%"
        case .liquidChlorine12_5: return "Liquid Chlorine 12.5%"
        case .trichlorTablets: return "Chlorine Tablets (Trichlor)"
        case .calHypoGranules: return "Cal-Hypo Granules"
        case .dichlorGranules: return "Dichlor Granules"
        case .sodaAsh: return "Soda Ash (Sodium Carbonate)"
        case .borax: return "Borax"
        case .muriaticAcid31: return "Muriatic Acid (31.45%)"
        case .muriaticAcid20: return "Low-Fume Muriatic Acid (20%)"
        case .dryAcid: return "Dry Acid (Sodium Bisulfate)"
        case .bakingSoda: return "Baking Soda (Sodium Bicarbonate)"
        case .calciumChloride: return "Calcium Chloride"
        case .granularCYA: return "Cyanuric Acid (Granular)"
        case .liquidStabilizer: return "Liquid Stabilizer"
        }
    }

    var concentrationLabel: String {
        switch self {
        case .liquidChlorine10: return "10% sodium hypochlorite"
        case .liquidChlorine12_5: return "12.5% sodium hypochlorite"
        case .trichlorTablets: return "trichlor stabilized chlorine"
        case .calHypoGranules: return "calcium hypochlorite"
        case .dichlorGranules: return "dichlor stabilized chlorine"
        case .muriaticAcid31: return "31.45% hydrochloric acid"
        case .muriaticAcid20: return "20% hydrochloric acid"
        case .dryAcid: return "sodium bisulfate"
        case .saltGenerator: return "chlorine production source"
        default: return displayName
        }
    }

    var doseUnitKind: String {
        switch self {
        case .saltGenerator:
            return "generator adjustment"
        case .liquidChlorine10, .liquidChlorine12_5, .muriaticAcid31, .muriaticAcid20, .liquidStabilizer:
            return "liquid volume"
        case .trichlorTablets:
            return "tablet or label dose"
        case .calHypoGranules, .dichlorGranules, .sodaAsh, .borax, .dryAcid, .bakingSoda, .calciumChloride, .granularCYA:
            return "weight"
        }
    }

    var chemistryEffects: [String] {
        switch self {
        case .saltGenerator:
            return ["raises FC by generation", "no manual dose"]
        case .liquidChlorine10, .liquidChlorine12_5:
            return ["raises FC", "does not raise CYA", "does not meaningfully raise CH"]
        case .trichlorTablets:
            return ["raises FC", "raises CYA", "acidic effect"]
        case .calHypoGranules:
            return ["raises FC", "raises calcium hardness", "does not raise CYA"]
        case .dichlorGranules:
            return ["raises FC", "raises CYA"]
        case .sodaAsh:
            return ["raises pH", "raises TA"]
        case .borax:
            return ["raises pH", "smaller TA effect than soda ash"]
        case .muriaticAcid31, .muriaticAcid20:
            return ["lowers pH", "lowers TA"]
        case .dryAcid:
            return ["lowers pH", "lowers TA", "adds sulfate over time"]
        case .bakingSoda:
            return ["raises TA", "small pH effect"]
        case .calciumChloride:
            return ["raises calcium hardness"]
        case .granularCYA, .liquidStabilizer:
            return ["raises CYA"]
        }
    }
}
