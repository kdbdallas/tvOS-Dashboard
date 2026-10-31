import Foundation
import WeatherKit
import CoreLocation

/// Service for fetching weather data using WeatherKit
/// Requires WeatherKit entitlement in the app's capabilities
@MainActor
class WeatherService: ObservableObject {
    @Published var currentWeather: WeatherDisplayData?
    @Published var weatherLocation1: WeatherDisplayData?
    @Published var weatherLocation2: WeatherDisplayData?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Apple Weather trademark and legal attribution, required wherever WeatherKit data is shown
    @Published var attribution: WeatherAttribution?

    private let weatherService = WeatherKit.WeatherService.shared
    private let geocoder = CLGeocoder()
    private let settingsManager = SettingsManager.shared

    private var cachedLocation1: CLLocation?
    private var cachedLocationName1: String?
    private var cachedLocation2: CLLocation?
    private var cachedLocationName2: String?
    private var periodicUpdateTask: Task<Void, Never>?

    /// Geocodes a zip code to get location coordinates and city name
    func geocodeZipCode(_ zipCode: String) async throws -> (location: CLLocation, cityName: String) {
        let placemarks = try await geocoder.geocodeAddressString(zipCode)

        guard let placemark = placemarks.first,
              let location = placemark.location else {
            throw NSError(domain: "WeatherService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to find location for zip code"])
        }

        // Build location name from placemark
        var locationName = ""
        if let city = placemark.locality {
            locationName = city
        }
        if let state = placemark.administrativeArea {
            locationName += locationName.isEmpty ? state : ", \(state)"
        }

        if locationName.isEmpty {
            locationName = zipCode
        }

        return (location, locationName)
    }

    /// Fetches weather data for a specific zip code and returns (WeatherDisplayData, location, locationName) tuple
    private func fetchWeatherData(forZipCode zipCode: String, cachedLocation: CLLocation?, cachedLocationName: String?) async throws -> (weather: WeatherDisplayData, location: CLLocation, locationName: String) {
        // Geocode the zip code if we don't have a cached location
        let (location, locationName): (CLLocation, String)
        if let cached = cachedLocation, let cachedName = cachedLocationName {
            location = cached
            locationName = cachedName
        } else {
            let geocoded = try await geocodeZipCode(zipCode)
            location = geocoded.location
            locationName = geocoded.cityName
        }

        let weather = try await weatherService.weather(for: location)

            let current = weather.currentWeather
            let todayForecast = weather.dailyForecast.first
            let hourlyForecast = weather.hourlyForecast.first

            // Get next 5 days forecast (skip today, get days 1-5)
            let fiveDayForecast = Array(weather.dailyForecast.forecast.dropFirst().prefix(5)).map { day in
                DailyForecastData(
                    date: day.date,
                    highTemperature: day.highTemperature.converted(to: .fahrenheit).value,
                    lowTemperature: day.lowTemperature.converted(to: .fahrenheit).value,
                    conditionSymbol: day.symbolName,
                    conditionDescription: day.condition.description,
                    precipitationChance: day.precipitationChance
                )
            }

            let weatherData = WeatherDisplayData(
                temperature: current.temperature.converted(to: .fahrenheit).value,
                temperatureUnit: "F",
                conditionDescription: current.condition.description,
                conditionSymbol: current.symbolName,
                highTemperature: todayForecast?.highTemperature.converted(to: .fahrenheit).value ?? current.temperature.converted(to: .fahrenheit).value,
                lowTemperature: todayForecast?.lowTemperature.converted(to: .fahrenheit).value ?? current.temperature.converted(to: .fahrenheit).value,
                humidity: current.humidity,
                feelsLike: current.apparentTemperature.converted(to: .fahrenheit).value,
                locationName: locationName,
                pressure: current.pressure.converted(to: .millibars).value,
                pressureTrend: current.pressureTrend.rawValue,
                visibility: current.visibility.converted(to: .meters).value,
                windSpeed: current.wind.speed.converted(to: .metersPerSecond).value,
                windDirection: current.wind.direction.converted(to: .degrees).value,
                windGust: current.wind.gust?.converted(to: .metersPerSecond).value,
                uvIndex: current.uvIndex.value,
                cloudCover: current.cloudCover,
                dewPoint: current.dewPoint.converted(to: .fahrenheit).value,
                precipitationChance: hourlyForecast?.precipitationChance,
                precipitationAmount: hourlyForecast?.precipitationAmount.converted(to: .millimeters).value,
                dailyForecast: fiveDayForecast
            )

            return (weatherData, location, locationName)
    }

    /// Fetches current weather for all configured zip codes
    func fetchWeather() async {
        isLoading = true
        errorMessage = nil

        // Check if at least one zip code is configured
        guard let zipCode1 = settingsManager.weatherZipCode, !zipCode1.isEmpty else {
            errorMessage = "No zip code configured. Please set a zip code in settings."
            isLoading = false
            currentWeather = nil
            weatherLocation1 = nil
            weatherLocation2 = nil
            return
        }

        do {
            // Fetch weather for location 1
            let result1 = try await fetchWeatherData(
                forZipCode: zipCode1,
                cachedLocation: cachedLocation1,
                cachedLocationName: cachedLocationName1
            )
            weatherLocation1 = result1.weather
            currentWeather = result1.weather
            cachedLocation1 = result1.location
            cachedLocationName1 = result1.locationName

            // Fetch weather for location 2 if configured
            if let zipCode2 = settingsManager.weatherZipCode2, !zipCode2.isEmpty {
                let result2 = try await fetchWeatherData(
                    forZipCode: zipCode2,
                    cachedLocation: cachedLocation2,
                    cachedLocationName: cachedLocationName2
                )
                weatherLocation2 = result2.weather
                cachedLocation2 = result2.location
                cachedLocationName2 = result2.locationName
            } else {
                weatherLocation2 = nil
            }

            if attribution == nil {
                attribution = try? await weatherService.attribution
            }

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Unable to fetch weather: \(error.localizedDescription)"
            currentWeather = nil
            weatherLocation1 = nil
            weatherLocation2 = nil
        }
    }

    /// Clears cached locations (useful when zip codes change)
    func clearLocationCache() {
        cachedLocation1 = nil
        cachedLocationName1 = nil
        cachedLocation2 = nil
        cachedLocationName2 = nil
    }

    /// Starts periodic weather updates every 30 minutes
    func startPeriodicUpdates() {
        // Cancel existing task if any
        periodicUpdateTask?.cancel()

        periodicUpdateTask = Task {
            await fetchWeather()

            // Update every 30 minutes
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                if !Task.isCancelled {
                    await fetchWeather()
                }
            }
        }
    }
}
