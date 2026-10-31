import SwiftUI
import Photos

/// Onboarding view shown on first launch to configure app settings
struct OnboardingView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var weatherService: WeatherService
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var calendarManager: CalendarManager

    @State private var currentStep = 0
    @State private var zipCodeInput1: String = ""
    @State private var zipCodeInput2: String = ""
    @State private var selectedAlbum: PhotoAlbum?
    @State private var isValidatingZip = false
    @State private var zipCodeError: String?
    @State private var editingZipCode1 = false
    @State private var editingZipCode2 = false
    @State private var tempZipInput = ""

    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)

                    Text("Welcome to KDB Dashboard")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Let's set up your personalized dashboard")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 40)

                // Step indicator
                HStack(spacing: 20) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step <= currentStep ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }

                // Content based on current step
                if currentStep == 0 {
                    photoAlbumStep
                        .frame(height: 600)
                } else if currentStep == 1 {
                    weatherLocationStep
                } else {
                    calendarSetupStep
                }

                Spacer()
            }
        }
    }

    private var photoAlbumStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Step 1: Choose Your Photo Album")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                if photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited {
                    if photoService.availableAlbums.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Loading albums...")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    } else {
                        albumButtons

                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAlbum == nil)
                        .padding(.top, 40)
                    }
                } else {
                    photoAuthorizationPrompt
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 20)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: 1000)
    }

    private var albumButtons: some View {
        VStack(spacing: 12) {
            ForEach(photoService.availableAlbums) { album in
                let isSelected = selectedAlbum?.id == album.id

                Button(action: {
                    selectedAlbum = album
                }) {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("\(album.assetCount) photos")
                                .font(.body)
                        }

                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
    }

    private var photoAuthorizationPrompt: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Photo Library Access Required")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("KDB Dashboard needs access to your photo library to display your photos")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 20) {
                Button("Grant Access") {
                    Task {
                        await photoService.requestAuthorization()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Next") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAlbum == nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var weatherLocationStep: some View {
        VStack(spacing: 32) {
            Text("Step 2: Set Your Weather Location(s)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Enter 1 or 2 zip codes. If you enter 2, the display will alternate every 15 minutes.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Location 1 (Required)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Button(action: {
                        tempZipInput = zipCodeInput1
                        editingZipCode1 = true
                    }) {
                        OnboardingZipCodeButtonContent(
                            zipCode: zipCodeInput1,
                            backgroundColor: Color.white.opacity(0.15)
                        )
                    }
                    .buttonStyle(OnboardingZipCodeButtonStyle())
                }

                VStack(spacing: 8) {
                    Text("Location 2 (Optional)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Button(action: {
                        tempZipInput = zipCodeInput2
                        editingZipCode2 = true
                    }) {
                        OnboardingZipCodeButtonContent(
                            zipCode: zipCodeInput2,
                            backgroundColor: Color.white.opacity(0.1)
                        )
                    }
                    .buttonStyle(OnboardingZipCodeButtonStyle())
                }

                if let error = zipCodeError {
                    Text(error)
                        .font(.body)
                        .foregroundColor(.red)
                }

                if isValidatingZip {
                    HStack {
                        ProgressView()
                        Text("Validating zip code(s)...")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            // Navigation buttons inside content
            HStack(spacing: 30) {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)

                Button("Next") {
                    validateAndProceed()
                }
                .buttonStyle(.borderedProminent)
                .disabled(zipCodeInput1.count != 5 || isValidatingZip)
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: 1000)
        .padding(.horizontal, 60)
        .alert("Enter Zip Code for Location 1", isPresented: $editingZipCode1) {
            TextField("Zip Code", text: $tempZipInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                tempZipInput = ""
            }
            Button("OK") {
                if tempZipInput.count <= 5 {
                    zipCodeInput1 = tempZipInput
                }
                tempZipInput = ""
            }
        } message: {
            Text("Enter 5-digit zip code")
        }
        .alert("Enter Zip Code for Location 2", isPresented: $editingZipCode2) {
            TextField("Zip Code", text: $tempZipInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                tempZipInput = ""
            }
            Button("OK") {
                if tempZipInput.count <= 5 {
                    zipCodeInput2 = tempZipInput
                }
                tempZipInput = ""
            }
        } message: {
            Text("Enter 5-digit zip code (optional)")
        }
    }

    private var calendarSetupStep: some View {
        CalendarView(
            calendarManager: calendarManager,
            showingSettings: .constant(false),
            isOnboarding: true,
            onOnboardingComplete: {
                completeOnboarding()
            }
        )
    }

    private var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case 0:
            return selectedAlbum != nil
        case 1:
            return zipCodeInput1.count == 5 && !isValidatingZip && zipCodeError == nil
        case 2:
            return !calendarManager.needsSetup
        default:
            return false
        }
    }

    private func validateAndProceed() {
        guard let album = selectedAlbum else { return }

        isValidatingZip = true
        zipCodeError = nil

        Task {
            do {
                // Validate zip code 1
                _ = try await weatherService.geocodeZipCode(zipCodeInput1)

                // Validate zip code 2 if provided
                if zipCodeInput2.count == 5 {
                    _ = try await weatherService.geocodeZipCode(zipCodeInput2)
                }

                // Save settings (except hasCompletedOnboarding)
                settingsManager.selectedAlbumName = album.name
                settingsManager.weatherZipCode = zipCodeInput1
                settingsManager.weatherZipCode2 = zipCodeInput2.count == 5 ? zipCodeInput2 : nil

                // Load initial data
                await photoService.loadPhotos()

                // Clear and refresh weather (periodic updates will fetch)
                weatherService.clearLocationCache()

                isValidatingZip = false

                // Move to calendar setup step
                withAnimation {
                    currentStep = 2
                }
            } catch {
                isValidatingZip = false
                zipCodeError = "Invalid zip code(s). Please try again."
            }
        }
    }

    private func completeOnboarding() {
        // Mark onboarding as complete and dismiss
        settingsManager.hasCompletedOnboarding = true
        dismiss()
    }
}

// Custom button style for onboarding zip code input
struct OnboardingZipCodeButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.onboardingZipCodeButtonFocused, isFocused)
    }
}

// Custom environment key for onboarding
private struct OnboardingZipCodeButtonFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var onboardingZipCodeButtonFocused: Bool {
        get { self[OnboardingZipCodeButtonFocusedKey.self] }
        set { self[OnboardingZipCodeButtonFocusedKey.self] = newValue }
    }
}

// Content view for onboarding zip code buttons
struct OnboardingZipCodeButtonContent: View {
    let zipCode: String
    let backgroundColor: Color
    @Environment(\.onboardingZipCodeButtonFocused) var isFocused

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                if zipCode.isEmpty {
                    Text("Enter Zip Code")
                        .font(.title2)
                } else {
                    Text(zipCode)
                        .font(.largeTitle)
                }
            }
            .foregroundColor(isFocused ? .blue : .white)
            Spacer()
        }
        .padding(24)
        .background(backgroundColor)
        .cornerRadius(16)
        .frame(minWidth: 600, maxWidth: 700)
    }
}

#Preview {
    OnboardingView(
        photoService: PhotoService(),
        weatherService: WeatherService(),
        settingsManager: SettingsManager.shared,
        calendarManager: CalendarManager()
    )
}
