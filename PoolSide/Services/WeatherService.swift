import Foundation
import CoreLocation
import WeatherKit
import Observation
import os.log

/// Categorised weather condition mapped to the bundled hero artwork.
enum PoolWeatherCategory: String, Sendable {
    case sunny
    case partlySunny
    case partlyCloudy
    case cloudy
    case lightRain
    case rain
    case thunderstorm
    case snow

    /// Image asset name in `Assets.xcassets/Heros/`.
    var heroAssetName: String {
        switch self {
        case .sunny:        return "Sunny Hero"
        case .partlySunny:  return "Partly Sunny Hero"
        case .partlyCloudy: return "Partly Cloudy Hero"
        case .cloudy:       return "Cloudy Hero"
        case .lightRain:    return "Light Rain Hero"
        case .rain:         return "Rain Hero"
        case .thunderstorm: return "Thunderstorm Hero"
        case .snow:         return "Snow Hero"
        }
    }

    /// Short label shown in the greeting line.
    var shortDescription: String {
        switch self {
        case .sunny:        return "Sunny"
        case .partlySunny:  return "Partly Sunny"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy:       return "Cloudy"
        case .lightRain:    return "Light Rain"
        case .rain:         return "Rain"
        case .thunderstorm: return "Thunderstorms"
        case .snow:         return "Snow"
        }
    }

    static func from(_ condition: WeatherCondition) -> PoolWeatherCategory {
        switch condition {
        case .clear, .mostlyClear, .hot:
            return .sunny
        case .partlyCloudy:
            return .partlySunny
        case .mostlyCloudy:
            return .partlyCloudy
        case .cloudy, .foggy, .haze, .smoky, .breezy, .windy, .blowingDust:
            return .cloudy
        case .drizzle, .sunShowers, .freezingDrizzle, .freezingRain:
            return .lightRain
        case .rain, .heavyRain, .hail, .hurricane, .tropicalStorm:
            return .rain
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorm
        case .snow, .heavySnow, .flurries, .sunFlurries, .blizzard, .blowingSnow, .sleet, .wintryMix, .frigid:
            return .snow
        @unknown default:
            return .sunny
        }
    }
}

/// Fetches the day's forecast from WeatherKit and exposes a summary the dashboard can read.
@MainActor
@Observable
final class PoolWeatherService {

    /// Today's categorised condition. `nil` while loading or after a failure.
    var category: PoolWeatherCategory?

    /// Today's expected high temperature, in degrees Fahrenheit.
    var highTemperatureFahrenheit: Int?

    /// Set when the most recent refresh failed. Cleared on a successful refresh.
    var lastErrorMessage: String?

    /// Marks when a refresh attempt finished — success or failure. Used by the UI to decide
    /// which toast to show after `refresh(...)` returns.
    private(set) var lastRefreshSucceeded: Bool = false

    /// Tracks the coordinate the latest successful result corresponds to so we can skip duplicate fetches.
    private var lastFetchedCoordinate: (latitude: Double, longitude: Double)?
    private var lastFetchedAt: Date?

    private let service = WeatherService.shared
    private let logger = Logger(subsystem: "com.poolside.app", category: "Weather")

    /// Returns `true` when the service has produced a usable forecast.
    var hasForecast: Bool {
        category != nil && highTemperatureFahrenheit != nil
    }

    /// - Parameter force: When `true`, bypass the freshness/location cache and always hit WeatherKit.
    func refresh(latitude: Double, longitude: Double, force: Bool = false) async {
        if !force, shouldSkipRefresh(latitude: latitude, longitude: longitude) {
            lastRefreshSucceeded = hasForecast
            return
        }

        logger.info("Requesting WeatherKit forecast for \(latitude, privacy: .public), \(longitude, privacy: .public)")
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let (current, daily) = try await service.weather(
                for: location,
                including: .current, .daily
            )

            let today = daily.forecast.first
            let condition = today?.condition ?? current.condition
            let highMeasurement = today?.highTemperature ?? current.temperature
            let highF = highMeasurement.converted(to: .fahrenheit).value

            logger.debug("Parsed condition=\(condition.rawValue, privacy: .public), highF=\(highF, privacy: .public)")

            category = PoolWeatherCategory.from(condition)
            highTemperatureFahrenheit = Int(highF.rounded())
            lastFetchedCoordinate = (latitude, longitude)
            lastFetchedAt = Date()
            lastErrorMessage = nil
            lastRefreshSucceeded = true
            logger.info("WeatherKit response: \(condition.rawValue, privacy: .public), high \(self.highTemperatureFahrenheit ?? -1)°F")
        } catch {
            let detail = Self.diagnosticDescription(for: error)
            lastErrorMessage = detail
            lastRefreshSucceeded = false
            logger.error("WeatherKit fetch failed: \(detail, privacy: .public) — \(String(describing: error), privacy: .public)")
            print("[Weather] WeatherKit fetch failed: \(detail)")
            print("[Weather] Raw error: \(String(describing: error))")
        }
    }

    private func shouldSkipRefresh(latitude: Double, longitude: Double) -> Bool {
        guard
            let coord = lastFetchedCoordinate,
            let fetchedAt = lastFetchedAt
        else { return false }

        let sameLocation = abs(coord.latitude - latitude) < 0.01
            && abs(coord.longitude - longitude) < 0.01
        let stillFresh = Date().timeIntervalSince(fetchedAt) < 30 * 60

        let skip = sameLocation && stillFresh && hasForecast
        if skip {
            logger.debug("Skipping refresh — same location and fresh forecast")
            print("[Weather] Skipping refresh — cached forecast is fresh and location unchanged")
        }
        return skip
    }

    /// Builds a short, human-readable description of a WeatherKit error suitable for a toast.
    private static func diagnosticDescription(for error: Error) -> String {
        let ns = error as NSError

        // The WeatherKit daemon raises this when Apple's auth servers refuse to issue a JWT
        // for the app's bundle ID. The capability is enabled in the portal and the entitlement
        // is signed into the binary, but the WeatherKit service hasn't propagated the enablement yet.
        if ns.domain.contains("WDSJWTAuthenticatorServiceListener") {
            return "WeatherKit auth servers haven't provisioned this app yet. This can take several hours after enabling WeatherKit on the App ID — usually resolves on its own."
        }

        if let weatherError = error as? WeatherError {
            switch weatherError {
            case .permissionDenied:
                return "WeatherKit permission denied — bundle ID not yet provisioned. This can take several hours after enabling WeatherKit."
            case .unknown:
                return "WeatherKit returned an unknown error. Check Console for the underlying NSError."
            @unknown default:
                return "WeatherKit error: \(weatherError)"
            }
        }

        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }
}
