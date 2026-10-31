import SwiftUI
import WeatherKit

/// Detailed weather HUD overlay showing comprehensive weather data
struct DetailedWeatherHUD: View {
    let weather: WeatherDisplayData
    let currentTime: Date
    let backgroundColors: [Color]
    let attribution: WeatherAttribution?
    let onDismiss: () -> Void

    @State private var showingDataSources = false
    @FocusState private var focusedButton: HUDButton?

    private enum HUDButton: Hashable {
        case done
        case dataSources
        case dataSourcesDone
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(weather.locationName)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(currentTime.formatted(
                    .dateTime
                        .weekday(.wide)
                        .month(.wide)
                        .day()
                        .hour(.defaultDigits(amPM: .abbreviated))
                        .minute(.twoDigits)
                ))
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(30)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: backgroundColors),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            ScrollView {
                VStack(spacing: 24) {
                    // Done button at top for easy access when scrolling up
                    HStack {
                        Spacer()
                        Button("Done") {
                            onDismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .focused($focusedButton, equals: .done)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 24)

                    // Current conditions - large display
                    VStack(spacing: 12) {
                        Image(systemName: weather.weatherIcon)
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                            .shadow(radius: 10)

                        Text(weather.formattedTemperature)
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)

                        Text(weather.conditionDescription)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))

                        Text(weather.formattedFeelsLike)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 20)

                    // Today's high/low
                    HStack(spacing: 40) {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.up")
                                .font(.title3)
                                .foregroundColor(.red)
                            Text(String(format: "%.0f°", weather.highTemperature))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("High")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        VStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text(String(format: "%.0f°", weather.lowTemperature))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("Low")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 30)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)

                    // 5-Day Forecast
                    if !weather.dailyForecast.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("5-Day Forecast")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)

                            VStack(spacing: 8) {
                                ForEach(weather.dailyForecast) { day in
                                    forecastDayButton(day: day)
                                }
                            }
                        }
                    }

                    // Detailed conditions grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        detailCardButton(
                            icon: "humidity.fill",
                            title: "Humidity",
                            value: weather.formattedHumidity,
                            color: .cyan
                        )

                        if let uvIndex = weather.uvIndex {
                            detailCardButton(
                                icon: "sun.max.fill",
                                title: "UV Index",
                                value: "\(uvIndex)",
                                color: uvIndexColor(uvIndex)
                            )
                        }

                        if let windSpeed = weather.formattedWindSpeed,
                           let windDirection = weather.formattedWindDirection {
                            detailCardButton(
                                icon: "wind",
                                title: "Wind",
                                value: "\(windDirection) \(windSpeed)",
                                color: .teal
                            )
                        }

                        if let windGust = weather.formattedWindGust {
                            detailCardButton(
                                icon: "wind.snow",
                                title: "Wind Gust",
                                value: windGust,
                                color: .teal
                            )
                        }

                        if let pressure = weather.formattedPressure {
                            detailCardButton(
                                icon: "gauge.high",
                                title: "Pressure",
                                value: pressure,
                                color: .orange
                            )
                        }

                        if let visibility = weather.formattedVisibility {
                            detailCardButton(
                                icon: "eye.fill",
                                title: "Visibility",
                                value: visibility,
                                color: .purple
                            )
                        }

                        if let dewPoint = weather.formattedDewPoint {
                            detailCardButton(
                                icon: "drop.fill",
                                title: "Dew Point",
                                value: dewPoint,
                                color: .blue
                            )
                        }

                        if let cloudCover = weather.formattedCloudCover {
                            detailCardButton(
                                icon: "cloud.fill",
                                title: "Cloud Cover",
                                value: cloudCover,
                                color: .gray
                            )
                        }

                        if let precipChance = weather.formattedPrecipitationChance {
                            detailCardButton(
                                icon: "cloud.rain.fill",
                                title: "Precip. Chance",
                                value: precipChance,
                                color: .blue
                            )
                        }

                        if let precipAmount = weather.formattedPrecipitationAmount {
                            detailCardButton(
                                icon: "cloud.heavyrain.fill",
                                title: "Precip. Amount",
                                value: precipAmount,
                                color: .blue
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: backgroundColors.map { $0.opacity(0.6) }),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Apple Weather attribution (fixed at bottom so it's always visible)
            if let attribution {
                attributionFooter(attribution)
            }
        }
        .disabled(showingDataSources)
        .background(Color.black)
        .cornerRadius(20)
        .overlay {
            if showingDataSources, let attribution {
                dataSourcesView(attribution)
            }
        }
        .shadow(radius: 30)
        .onAppear {
            focus(.done)
        }
        .onChange(of: showingDataSources) { _, showing in
            focus(showing ? .dataSourcesDone : .dataSources)
        }
        .onPlayPauseCommand {
            onDismiss()
        }
        .onExitCommand {
            onDismiss()
        }
    }

    /// Moves focus once the view hierarchy has updated. With nothing focused,
    /// the remote's Back button exits the app instead of closing this HUD.
    private func focus(_ button: HUDButton) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedButton = button
        }
    }

    // MARK: - Apple Weather Attribution

    private func attributionFooter(_ attribution: WeatherAttribution) -> some View {
        HStack {
            AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Text(attribution.serviceName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(height: 20)

            Spacer()

            Button(action: {
                showingDataSources = true
            }) {
                Text("Data Sources")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
            }
            .buttonStyle(.weatherCard)
            .focused($focusedButton, equals: .dataSources)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// Full-HUD page listing WeatherKit's legal data sources
    private func dataSourcesView(_ attribution: WeatherAttribution) -> some View {
        var sections = attributionSections(attribution.legalAttributionText)
        // The text starts with its own title ("WeatherKit - Data Sources")
        let title = sections.first?.items.isEmpty == true ? sections.removeFirst().heading : "Data Sources"

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Button("Done") {
                    showingDataSources = false
                }
                .buttonStyle(.borderedProminent)
                .focused($focusedButton, equals: .dataSourcesDone)
            }
            .padding(30)

            // Each section is focusable so the remote can scroll through them
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sections) { section in
                        Button(action: {}) {
                            VStack(alignment: .leading, spacing: 6) {
                                if section.items.isEmpty {
                                    Text(section.heading)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                } else {
                                    Text(section.heading)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)

                                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                                        Text(item)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.weatherCard)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
        .background(Color(.sRGB, red: 0.1, green: 0.1, blue: 0.15, opacity: 1.0))
        .cornerRadius(20)
        .onExitCommand {
            showingDataSources = false
        }
    }

    private struct AttributionSection: Identifiable {
        let id: Int
        let heading: String
        var items: [String]
    }

    /// Groups the legal text into headings, each followed by its "•" bullet lines
    private func attributionSections(_ text: String) -> [AttributionSection] {
        var sections: [AttributionSection] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("•"), !sections.isEmpty {
                let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(AttributionSection(id: sections.count, heading: trimmed, items: []))
            }
        }
        return sections
    }

    private func detailCardButton(icon: String, title: String, value: String, color: Color) -> some View {
        Button(action: {}) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .textCase(.uppercase)

                Text(value)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.weatherCard)
    }

    private func forecastDayButton(day: DailyForecastData) -> some View {
        Button(action: {}) {
            HStack(spacing: 16) {
                // Day name
                Text(day.dayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(width: 60, alignment: .leading)

                // Weather icon
                Image(systemName: day.conditionSymbol)
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 40)

                // Precipitation chance
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.caption)
                        .foregroundColor(.cyan)
                    Text(day.formattedPrecipChance)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minWidth: 50, alignment: .leading)

                Spacer()

                // High/Low temps
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                        Text(day.formattedHigh)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .foregroundColor(.blue.opacity(0.8))
                        Text(day.formattedLow)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.weatherCard)
    }

    private func uvIndexColor(_ index: Int) -> Color {
        switch index {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
}

// Custom button style for weather detail cards with focus feedback
struct CardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.05 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(isFocused ? 0.8 : 0), lineWidth: 3)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    static var weatherCard: CardButtonStyle {
        CardButtonStyle()
    }
}
