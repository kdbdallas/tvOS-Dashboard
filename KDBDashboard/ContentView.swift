import SwiftUI

/// Main content view with split layout:
/// - Left 60%: Calendar (Google + iCloud merged)
/// - Right 40%: Photo (75% top) + Weather (25% bottom)
struct ContentView: View {
    @StateObject private var calendarManager = CalendarManager()
    @StateObject private var photoService = PhotoService()
    @StateObject private var weatherService = WeatherService()
    @StateObject private var settingsManager = SettingsManager.shared

    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var showingWeatherDetail = false
    @State private var currentTime = Date()
    @FocusState private var weatherViewFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack(spacing: 20) {
                    // Left side - Calendar (60% width)
                    CalendarView(
                        calendarManager: calendarManager,
                        showingSettings: $showingSettings
                    )
                    .frame(width: geometry.size.width * 0.60 - 30)

                    // Right side - Photo + Weather (40% width)
                    VStack(spacing: 20) {
                        // Photo (75% of right side height)
                        PhotoView(photoService: photoService)
                            .frame(height: (geometry.size.height - 20) * 0.75)

                        // Weather (25% of right side height)
                        WeatherView(weatherService: weatherService, showingDetailedWeather: $showingWeatherDetail)
                            .frame(height: (geometry.size.height - 20) * 0.25 - 20)
                            .focused($weatherViewFocused)
                    }
                    .frame(width: geometry.size.width * 0.40 - 30)
                }
                .padding(20)
                // Keep focus inside the weather HUD while it's showing
                .disabled(showingWeatherDetail)

                // Weather detail HUD overlay
                if showingWeatherDetail, let weather = weatherService.currentWeather {
                    ZStack {
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showingWeatherDetail = false
                            }

                        DetailedWeatherHUD(
                            weather: weather,
                            currentTime: currentTime,
                            backgroundColors: weatherBackgroundColors(for: weather),
                            attribution: weatherService.attribution,
                            onDismiss: {
                                showingWeatherDetail = false
                                // Wait for the weather view to be re-enabled before focusing it
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    weatherViewFocused = true
                                }
                            }
                        )
                        .frame(maxWidth: 900, maxHeight: 1000)
                    }
                }
            }
        }
        .background(Color.black)
        .task {
            // Update the clock every 60 seconds for weather HUD
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                currentTime = Date()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                photoService: photoService,
                weatherService: weatherService,
                settingsManager: settingsManager,
                calendarManager: calendarManager
            )
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                photoService: photoService,
                weatherService: weatherService,
                settingsManager: settingsManager,
                calendarManager: calendarManager
            )
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true

            // Check if onboarding is needed
            if !settingsManager.hasCompletedOnboarding {
                showingOnboarding = true
            } else {
                startServices()
            }
        }
        .onChange(of: settingsManager.hasCompletedOnboarding) { _, completed in
            if completed {
                startServices()
            }
        }
    }

    private func startServices() {
        // Start weather updates
        weatherService.startPeriodicUpdates()

        // Start photo rotation
        photoService.startRotation()

        // Start calendar updates
        calendarManager.startPeriodicUpdates()
    }

    private func weatherBackgroundColors(for weather: WeatherDisplayData) -> [Color] {
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
    ContentView()
}
