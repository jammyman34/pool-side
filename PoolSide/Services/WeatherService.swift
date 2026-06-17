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

    /// Tracks the coordinate the latest result corresponds to so we can skip duplicate fetches.
    private var lastFetchedCoordinate: (latitude: Double, longitude: Double)?
    private var lastFetchedAt: Date?

    private let service = WeatherService.shared
    private let logger = Logger(subsystem: "com.poolside.app", category: "Weather")

    /// Returns `true` when the service has produced a usable forecast.
    var hasForecast: Bool {
        category != nil && highTemperatureFahrenheit != nil
    }

    func refresh(latitude: Double, longitude: Double) async {
        if shouldSkipRefresh(latitude: latitude, longitude: longitude) { return }

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

            category = PoolWeatherCategory.from(condition)
            highTemperatureFahrenheit = Int(highF.rounded())
            lastFetchedCoordinate = (latitude, longitude)
            lastFetchedAt = Date()
            logger.info("WeatherKit response: \(condition.rawValue, privacy: .public), high \(self.highTemperatureFahrenheit ?? -1)°F")
        } catch {
            logger.error("WeatherKit fetch failed: \(error.localizedDescription, privacy: .public) — \(String(describing: error), privacy: .public)")
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

        return sameLocation && stillFresh && hasForecast
    }
}
