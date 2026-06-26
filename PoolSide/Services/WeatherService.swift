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

/// Fetches the day's forecast and exposes a summary the dashboard can read.
@MainActor
@Observable
final class PoolWeatherService {

    /// Today's categorised condition. `nil` while loading or after a failure.
    var category: PoolWeatherCategory?

    /// Today's expected high temperature, in degrees Fahrenheit.
    var highTemperatureFahrenheit: Int?

    /// Current or nearest-hour temperature, in degrees Fahrenheit.
    var currentTemperatureFahrenheit: Int?

    /// Set when the most recent refresh failed. Cleared on a successful refresh.
    var lastErrorMessage: String?

    /// Marks when a refresh attempt finished — success or failure. Used by the UI to decide
    /// which toast to show after `refresh(...)` returns.
    private(set) var lastRefreshSucceeded: Bool = false

    /// Tracks the coordinate the latest successful result corresponds to so we can skip duplicate fetches.
    private var lastFetchedCoordinate: (latitude: Double, longitude: Double)?
    private var lastFetchedAt: Date?

    private let service = WeatherService.shared
    private let session: URLSession
    private let logger = Logger(subsystem: "com.poolside.app", category: "Weather")
    private let prefersNWSPrimary = true
    private let nwsUserAgent = "PoolSide/1.0 (justinmandell@gmail.com)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns `true` when the service has produced a usable forecast.
    var hasForecast: Bool {
        category != nil && currentTemperatureFahrenheit != nil && highTemperatureFahrenheit != nil
    }

    /// - Parameter force: When `true`, bypass the freshness/location cache and always refresh weather.
    func refresh(latitude: Double, longitude: Double, force: Bool = false) async {
        if !force, shouldSkipRefresh(latitude: latitude, longitude: longitude) {
            lastRefreshSucceeded = hasForecast
            return
        }

        if prefersNWSPrimary {
            do {
                let nwsForecast = try await fetchNWSForecast(latitude: latitude, longitude: longitude, force: force)
                apply(forecast: nwsForecast, latitude: latitude, longitude: longitude)
                logger.info("NWS response: \(nwsForecast.category.rawValue, privacy: .public), high \(nwsForecast.highTemperatureFahrenheit)°F")
                print("[Weather] NWS succeeded: \(nwsForecast.category.shortDescription), high \(nwsForecast.highTemperatureFahrenheit)°F")
                return
            } catch {
                let nwsDetail = Self.diagnosticDescription(for: error)
                logger.error("NWS primary fetch failed: \(nwsDetail, privacy: .public) — \(String(describing: error), privacy: .public)")
                print("[Weather] NWS primary failed: \(nwsDetail)")
                preserveExistingForecastOrFail()
                return
            }
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

            apply(
                forecast: NWSForecastSummary(
                    category: PoolWeatherCategory.from(condition),
                    currentTemperatureFahrenheit: Int(current.temperature.converted(to: .fahrenheit).value.rounded()),
                    highTemperatureFahrenheit: Int(highF.rounded())
                ),
                latitude: latitude,
                longitude: longitude
            )
            logger.info("WeatherKit response: \(condition.rawValue, privacy: .public), high \(self.highTemperatureFahrenheit ?? -1)°F")
        } catch {
            let weatherKitDetail = Self.diagnosticDescription(for: error)
            logger.error("WeatherKit fetch failed: \(weatherKitDetail, privacy: .public) — \(String(describing: error), privacy: .public)")
            print("[Weather] WeatherKit fetch failed: \(weatherKitDetail)")
            print("[Weather] Raw error: \(String(describing: error))")

            do {
                let nwsForecast = try await fetchNWSForecast(latitude: latitude, longitude: longitude, force: force)
                apply(forecast: nwsForecast, latitude: latitude, longitude: longitude)
                logger.info("NWS fallback response: \(nwsForecast.category.rawValue, privacy: .public), high \(nwsForecast.highTemperatureFahrenheit)°F")
                print("[Weather] NWS fallback succeeded: \(nwsForecast.category.shortDescription), high \(nwsForecast.highTemperatureFahrenheit)°F")
            } catch {
                let nwsDetail = Self.diagnosticDescription(for: error)
                preserveExistingForecastOrFail()
                logger.error("NWS fallback failed: \(nwsDetail, privacy: .public) — \(String(describing: error), privacy: .public)")
                print("[Weather] NWS fallback failed: \(nwsDetail)")
                print("[Weather] Raw NWS error: \(String(describing: error))")
            }
        }
    }

    private func apply(forecast: NWSForecastSummary, latitude: Double, longitude: Double) {
        category = forecast.category
        currentTemperatureFahrenheit = forecast.currentTemperatureFahrenheit
        highTemperatureFahrenheit = forecast.highTemperatureFahrenheit
        lastFetchedCoordinate = (latitude, longitude)
        lastFetchedAt = Date()
        lastErrorMessage = nil
        lastRefreshSucceeded = true
    }

    private func preserveExistingForecastOrFail() {
        if hasForecast {
            lastErrorMessage = nil
            lastRefreshSucceeded = true
            print("[Weather] Keeping existing forecast after refresh failure")
        } else {
            lastErrorMessage = "Weather update failed. Please try again."
            lastRefreshSucceeded = false
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

    private func fetchNWSForecast(latitude: Double, longitude: Double, force: Bool) async throws -> NWSForecastSummary {
        let coordinatePath = "\(String(format: "%.4f", latitude)),\(String(format: "%.4f", longitude))"
        guard let pointsURL = URL(string: "https://api.weather.gov/points/\(coordinatePath)") else {
            throw NWSError.invalidURL
        }

        print("[Weather] Requesting NWS points metadata for \(coordinatePath)")
        var pointsRequest = nwsRequest(url: pointsURL, force: force)
        pointsRequest.setValue(nwsUserAgent, forHTTPHeaderField: "User-Agent")
        pointsRequest.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let points: NWSPointsResponse = try await decodeNWSResponse(NWSPointsResponse.self, from: pointsRequest)

        guard let forecastURL = URL(string: points.properties.forecast) else {
            throw NWSError.invalidForecastURL
        }

        print("[Weather] Requesting NWS daily forecast: \(forecastURL.absoluteString)")
        var forecastRequest = nwsRequest(url: forecastURL, force: force)
        forecastRequest.setValue(nwsUserAgent, forHTTPHeaderField: "User-Agent")
        forecastRequest.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let forecast: NWSForecastResponse = try await decodeNWSResponse(NWSForecastResponse.self, from: forecastRequest)
        guard let period = forecast.properties.periods.first(where: \.isDaytime) ?? forecast.properties.periods.first else {
            throw NWSError.emptyForecast
        }

        let current = try await fetchNWSCurrentConditions(from: points.properties.forecastHourly, force: force)

        return NWSForecastSummary(
            category: current.category,
            currentTemperatureFahrenheit: current.temperatureFahrenheit,
            highTemperatureFahrenheit: period.temperature
        )
    }

    private func fetchNWSCurrentConditions(from hourlyForecast: String, force: Bool) async throws -> NWSCurrentConditions {
        guard let hourlyURL = URL(string: hourlyForecast) else {
            throw NWSError.invalidForecastURL
        }

        print("[Weather] Requesting NWS hourly forecast: \(hourlyURL.absoluteString)")
        var request = nwsRequest(url: hourlyURL, force: force)
        request.setValue(nwsUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let forecast: NWSForecastResponse = try await decodeNWSResponse(NWSForecastResponse.self, from: request)
        guard let currentPeriod = forecast.properties.periods.first else {
            throw NWSError.emptyForecast
        }

        print("[Weather] NWS current period: temp=\(currentPeriod.temperature)°F, forecast=\(currentPeriod.shortForecast)")
        return NWSCurrentConditions(
            temperatureFahrenheit: currentPeriod.temperature,
            category: PoolWeatherCategory.fromNWSForecast(currentPeriod.shortForecast)
        )
    }

    private func nwsRequest(url: URL, force: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        if force {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        return request
    }

    private func decodeNWSResponse<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NWSError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if httpResponse.statusCode == 404 {
                throw NWSError.unsupportedLocation
            }
            throw NWSError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(T.self, from: data)
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

private struct NWSForecastSummary {
    let category: PoolWeatherCategory
    let currentTemperatureFahrenheit: Int
    let highTemperatureFahrenheit: Int
}

private struct NWSCurrentConditions {
    let temperatureFahrenheit: Int
    let category: PoolWeatherCategory
}

private struct NWSPointsResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let forecast: String
        let forecastHourly: String
    }
}

private struct NWSForecastResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let periods: [Period]
    }

    struct Period: Decodable {
        let isDaytime: Bool
        let temperature: Int
        let shortForecast: String
    }
}

private enum NWSError: LocalizedError {
    case invalidURL
    case invalidForecastURL
    case invalidResponse
    case unsupportedLocation
    case httpStatus(Int)
    case emptyForecast

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "NWS fallback could not build a valid points URL."
        case .invalidForecastURL:
            return "NWS fallback returned an invalid forecast URL."
        case .invalidResponse:
            return "NWS fallback returned an invalid response."
        case .unsupportedLocation:
            return "NWS fallback only supports US locations."
        case .httpStatus(let statusCode):
            return "NWS fallback returned HTTP \(statusCode)."
        case .emptyForecast:
            return "NWS fallback returned no forecast periods."
        }
    }
}

private extension PoolWeatherCategory {
    static func fromNWSForecast(_ shortForecast: String) -> PoolWeatherCategory {
        let text = shortForecast.lowercased()

        if text.contains("thunder") || text.contains("t-storm") || text.contains("storm") {
            return .thunderstorm
        }

        if text.contains("snow") || text.contains("sleet") || text.contains("wintry") || text.contains("ice") {
            return .snow
        }

        if text.contains("rain") || text.contains("showers") {
            if text.contains("slight") || text.contains("chance") || text.contains("drizzle") {
                return .lightRain
            }
            return .rain
        }

        if text.contains("overcast") || text.contains("cloudy") {
            if text.contains("partly") {
                return .partlySunny
            }
            if text.contains("mostly") {
                return .partlyCloudy
            }
            return .cloudy
        }

        if text.contains("fog") || text.contains("haze") || text.contains("smoke") {
            return .cloudy
        }

        if text.contains("sunny") || text.contains("clear") {
            if text.contains("partly") {
                return .partlySunny
            }
            if text.contains("mostly") {
                return .sunny
            }
            return .sunny
        }

        return .sunny
    }
}
