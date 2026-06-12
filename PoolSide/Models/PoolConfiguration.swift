import Foundation

/// Pool configuration stored in UserDefaults via AppStorage.
/// Not a SwiftData model — settings are single-instance, not queried.
struct PoolConfiguration: Codable {

    var name: String = "My Pool"
    var volumeGallons: Double = 15000
    var poolType: PoolType = .inground
    var surfaceType: SurfaceType = .plaster
    var isSaltwater: Bool = false
    var location: String = ""

    // MARK: - Persistence key
    static let defaultsKey = "poolConfiguration"

    static var current: PoolConfiguration {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: defaultsKey),
                let config = try? JSONDecoder().decode(PoolConfiguration.self, from: data)
            else { return PoolConfiguration() }
            return config
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Whether configuration has been saved at least once
    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: defaultsKey) != nil
    }

    /// Removes all saved configuration (sign out)
    static func clearCurrent() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
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
