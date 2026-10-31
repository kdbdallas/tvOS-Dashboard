import Foundation

/// Represents a single day in the forecast
struct DailyForecastData: Identifiable {
    let id = UUID()
    let date: Date
    let highTemperature: Double
    let lowTemperature: Double
    let conditionSymbol: String
    let conditionDescription: String
    let precipitationChance: Double

    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    var formattedHigh: String {
        String(format: "%.0f°", highTemperature)
    }

    var formattedLow: String {
        String(format: "%.0f°", lowTemperature)
    }

    var formattedPrecipChance: String {
        String(format: "%.0f%%", precipitationChance * 100)
    }
}

/// Represents current weather data for display
struct WeatherDisplayData {
    let temperature: Double
    let temperatureUnit: String
    let conditionDescription: String
    let conditionSymbol: String
    let highTemperature: Double
    let lowTemperature: Double
    let humidity: Double
    let feelsLike: Double
    let locationName: String

    // Extended weather data
    let pressure: Double?
    let pressureTrend: String?
    let visibility: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let windGust: Double?
    let uvIndex: Int?
    let cloudCover: Double?
    let dewPoint: Double?
    let precipitationChance: Double?
    let precipitationAmount: Double?

    // Forecast data
    let dailyForecast: [DailyForecastData]

    var formattedTemperature: String {
        String(format: "%.0f°%@", temperature, temperatureUnit)
    }

    var formattedHighLow: String {
        String(format: "H: %.0f° L: %.0f°", highTemperature, lowTemperature)
    }

    var formattedFeelsLike: String {
        String(format: "Feels like %.0f°", feelsLike)
    }

    var formattedHumidity: String {
        String(format: "Humidity: %.0f%%", humidity * 100)
    }

    var formattedPressure: String? {
        guard let pressure = pressure else { return nil }
        let inHg = pressure * 0.02953  // Convert millibars to inches of mercury
        return String(format: "%.2f inHg", inHg)
    }

    var formattedVisibility: String? {
        guard let visibility = visibility else { return nil }
        let miles = visibility / 1609.34  // Convert meters to miles
        return String(format: "%.1f mi", miles)
    }

    var formattedWindSpeed: String? {
        guard let windSpeed = windSpeed else { return nil }
        let mph = windSpeed * 2.237  // Convert m/s to mph
        return String(format: "%.0f mph", mph)
    }

    var formattedWindGust: String? {
        guard let windGust = windGust else { return nil }
        let mph = windGust * 2.237  // Convert m/s to mph
        return String(format: "%.0f mph", mph)
    }

    var formattedWindDirection: String? {
        guard let degrees = windDirection else { return nil }
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }

    var formattedDewPoint: String? {
        guard let dewPoint = dewPoint else { return nil }
        return String(format: "%.0f°F", dewPoint)
    }

    var formattedCloudCover: String? {
        guard let cloudCover = cloudCover else { return nil }
        return String(format: "%.0f%%", cloudCover * 100)
    }

    var formattedPrecipitationChance: String? {
        guard let chance = precipitationChance else { return nil }
        return String(format: "%.0f%%", chance * 100)
    }

    var formattedPrecipitationAmount: String? {
        guard let amount = precipitationAmount else { return nil }
        let inches = amount / 25.4  // Convert mm to inches
        return String(format: "%.2f in", inches)
    }

    // SF Symbol name for the weather condition
    var weatherIcon: String {
        conditionSymbol
    }

    static var placeholder: WeatherDisplayData {
        WeatherDisplayData(
            temperature: 72,
            temperatureUnit: "F",
            conditionDescription: "Sunny",
            conditionSymbol: "sun.max.fill",
            highTemperature: 85,
            lowTemperature: 65,
            humidity: 0.35,
            feelsLike: 74,
            locationName: "Peoria, AZ",
            pressure: 1013.25,
            pressureTrend: "rising",
            visibility: 16093,
            windSpeed: 5.0,
            windDirection: 180,
            windGust: 8.0,
            uvIndex: 7,
            cloudCover: 0.2,
            dewPoint: 55,
            precipitationChance: 0.1,
            precipitationAmount: 0.0,
            dailyForecast: []
        )
    }
}
