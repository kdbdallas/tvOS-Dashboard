import SwiftUI

/// Displays current weather information with support for two locations
struct WeatherView: View {
    @ObservedObject var weatherService: WeatherService
    @Binding var showingDetailedWeather: Bool
    @State private var currentTime = Date()
    @State private var showingLocation2 = false
    @State private var timerResetTrigger = UUID()
    @State private var isAnimating = false

    var body: some View {
        Button(action: {
            if displayedWeather != nil {
                // Update currentWeather to match what's being displayed
                weatherService.currentWeather = displayedWeather
                showingDetailedWeather = true
            }
        }) {
            ZStack {
                if weatherService.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if let error = weatherService.errorMessage {
                    errorView(message: error)
                } else if let weather = displayedWeather {
                    // Background gradient based on conditions
                    LinearGradient(
                        gradient: Gradient(colors: backgroundColors),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        weatherContent(weather: weather)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Text("Loading weather...")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .disabled(weatherService.currentWeather == nil)
        .onMoveCommand { direction in
            handleMove(direction: direction)
        }
        .task {
            // Update the clock every 60 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                currentTime = Date()
            }
        }
        .task(id: timerResetTrigger) {
            // Switch between locations every 15 minutes if two are configured
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                if weatherService.weatherLocation2 != nil {
                    performFlip(direction: .down)
                }
            }
        }
    }

    private func handleMove(direction: MoveCommandDirection) {
        // Don't handle swipes when detail HUD is showing
        guard !showingDetailedWeather else { return }
        // Only handle up/down swipes if we have two locations configured
        guard weatherService.weatherLocation2 != nil else { return }

        // Only respond to up and down directions
        switch direction {
        case .up:
            performFlip(direction: .up)
            timerResetTrigger = UUID()
        case .down:
            performFlip(direction: .down)
            timerResetTrigger = UUID()
        default:
            break
        }
    }

    private func performFlip(direction: FlipDirection) {
        // Prevent multiple rapid toggles
        guard !isAnimating else {
            return
        }

        isAnimating = true
        showingLocation2.toggle()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            isAnimating = false
        }
    }

    enum FlipDirection {
        case up, down
    }

    /// Returns the weather data that should currently be displayed
    private var displayedWeather: WeatherDisplayData? {
        if showingLocation2, let weather2 = weatherService.weatherLocation2 {
            return weather2
        }
        return weatherService.weatherLocation1
    }

    private func weatherContent(weather: WeatherDisplayData) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Top swipe indicator (only visible when two locations configured)
                if weatherService.weatherLocation2 != nil {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                }

                HStack(spacing: 12) {
                    // Weather icon
                    Image(systemName: weather.weatherIcon)
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .shadow(radius: 5)

                    VStack(alignment: .leading, spacing: 4) {
                        // Location
                        Text(weather.locationName)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        // Temperature
                        Text(weather.formattedTemperature)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        // Condition
                        Text(weather.conditionDescription)
                            .font(.system(size: 40, weight: .regular))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        // Local Time (updated every minute via currentTime state)
                        Text(currentTime.formatted(
                            .dateTime
                                .weekday(.abbreviated)
                                .hour(.defaultDigits(amPM: .abbreviated))
                                .minute(.twoDigits)
                        ))
                        .foregroundColor(.white)

                        // High/Low
                        Text(weather.formattedHighLow)
                            .font(.body)
                            .foregroundColor(.white)

                        // Feels like
                        Text(weather.formattedFeelsLike)
                            .font(.body)
                            .foregroundColor(.white)

                        // Humidity
                        Text(weather.formattedHumidity)
                            .font(.body)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, weatherService.weatherLocation2 != nil ? 8 : 20)

                // Bottom swipe indicator (only visible when two locations configured)
                if weatherService.weatherLocation2 != nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                }
            }

            // Clickable indicator icon in top-right corner of entire weather view
            Image(systemName: "arrow.up.forward.square")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    var backgroundColors: [Color] {
        guard let weather = weatherService.currentWeather else {
            return [Color.blue.opacity(0.7), Color.blue.opacity(0.5)]
        }

        // Colors based on weather condition symbol
        let symbol = weather.conditionSymbol.lowercased()

        if symbol.contains("sun") || symbol.contains("clear") {
            return [Color.orange.opacity(0.8), Color.yellow.opacity(0.6)]
        } else if symbol.contains("cloud") {
            return [Color.gray.opacity(0.7), Color.blue.opacity(0.5)]
        } else if symbol.contains("rain") || symbol.contains("drizzle") {
            return [Color.blue.opacity(0.8), Color.gray.opacity(0.6)]
        } else if symbol.contains("snow") {
            return [Color.white.opacity(0.8), Color.blue.opacity(0.4)]
        } else if symbol.contains("wind") {
            return [Color.teal.opacity(0.7), Color.gray.opacity(0.5)]
        } else if symbol.contains("fog") || symbol.contains("haze") {
            return [Color.gray.opacity(0.6), Color.gray.opacity(0.4)]
        } else if symbol.contains("thunder") || symbol.contains("storm") {
            return [Color.purple.opacity(0.7), Color.gray.opacity(0.6)]
        } else {
            return [Color.blue.opacity(0.7), Color.cyan.opacity(0.5)]
        }
    }
}

#Preview {
    WeatherView(weatherService: WeatherService(), showingDetailedWeather: .constant(false))
        .frame(height: 200)
        .padding()
}
