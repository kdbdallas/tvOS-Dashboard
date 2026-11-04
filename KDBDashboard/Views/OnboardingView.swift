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
    @FocusState private var albumStepFocus: AlbumStepFocus?

    private enum AlbumStepFocus: Hashable {
        case album(String)
        case index(String)
        case next
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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
                        .frame(height: 750)
                } else if currentStep == 1 {
                    weatherLocationStep
                } else {
                    calendarSetupStep
                }

                Spacer()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have granted photo access in Settings while we were backgrounded
            if phase == .active {
                Task { await photoService.refreshAuthorizationStatus() }
            }
        }
    }

    private var photoAlbumStep: some View {
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
                    Spacer()
                } else {
                    // Only the album list scrolls; Next stays pinned below it so it's always visible
                    ScrollViewReader { proxy in
                        HStack(spacing: 0) {
                            ScrollView {
                                albumButtons
                                    .padding(.vertical, 20)
                            }
                            .focusSection()

                            if albumIndexSections.count > 1 {
                                albumIndexStrip
                                    .focusSection()
                            }
                        }
                        .onChange(of: albumStepFocus) { _, focus in
                            // Moving up/down the index jumps the list to that letter's first album
                            if case .index(let key) = focus, let id = firstAlbumID(forIndexKey: key) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    }

                    // Full-width focus section so pressing down from anywhere in the list reaches Next
                    HStack {
                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedAlbum == nil)
                        .focused($albumStepFocus, equals: .next)
                        .onMoveCommand { direction in
                            // Return to the selected album rather than wherever the focus engine lands
                            if direction == .up, let id = selectedAlbum?.id {
                                albumStepFocus = .album(id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .focusSection()
                }
            } else {
                ScrollView {
                    photoAuthorizationPrompt
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: 1000)
    }

    private var albumButtons: some View {
        VStack(spacing: 12) {
            ForEach(photoService.availableAlbums) { album in
                let isSelected = selectedAlbum?.id == album.id

                Button(action: {
                    selectedAlbum = album
                    // Next is disabled until an album is selected, so wait a run loop
                    // for it to become enabled before moving focus to it
                    DispatchQueue.main.async {
                        albumStepFocus = .next
                    }
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
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .focused($albumStepFocus, equals: .album(album.id))
                .id(album.id)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Album index strip

    /// Index keys in list order, one per group of albums sharing a first letter ("#" for non-letters)
    private var albumIndexSections: [String] {
        var seen = Set<String>()
        return photoService.availableAlbums
            .map { Self.indexKey(for: $0.name) }
            .filter { seen.insert($0).inserted }
    }

    private func firstAlbumID(forIndexKey key: String) -> String? {
        photoService.availableAlbums.first { Self.indexKey(for: $0.name) == key }?.id
    }

    private static func indexKey(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "#" }
        let folded = String(first)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        return folded.first?.isLetter == true ? folded : "#"
    }

    /// The index key of the album currently focused in the list, used to highlight its letter
    private var focusedAlbumIndexKey: String? {
        guard case .album(let id) = albumStepFocus,
              let album = photoService.availableAlbums.first(where: { $0.id == id }) else { return nil }
        return Self.indexKey(for: album.name)
    }

    private var albumIndexStrip: some View {
        VStack(spacing: 2) {
            ForEach(albumIndexSections, id: \.self) { key in
                Button {
                    focusFirstAlbum(forIndexKey: key)
                } label: {
                    Text(key)
                }
                .buttonStyle(IndexLetterButtonStyle(isCurrentSection: focusedAlbumIndexKey == key))
                .focused($albumStepFocus, equals: .index(key))
                .onMoveCommand { direction in
                    // Leaving the strip lands on the letter's first album, not the geometrically nearest one
                    if direction == .left {
                        focusFirstAlbum(forIndexKey: key)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    private func focusFirstAlbum(forIndexKey key: String) {
        if let id = firstAlbumID(forIndexKey: key) {
            albumStepFocus = .album(id)
        }
    }

    private var photoAuthorizationPrompt: some View {
        // Once access is denied the system will never show the prompt again, so
        // requestAuthorization() returns immediately and we must send the user to Settings
        let isDenied = photoService.authorizationStatus == .denied
        let isRestricted = photoService.authorizationStatus == .restricted

        return VStack(spacing: 40) {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Photo Library Access Required")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(
                    isDenied
                        ? "Photo access was turned off. To show your photos, open Settings, choose Photos, and allow access for KDB Dashboard."
                        : isRestricted
                            ? "Photo access is restricted on this Apple TV, possibly by Screen Time or a device profile."
                            : "KDB Dashboard needs access to your photo library to display your photos"
                )
                .font(.callout)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if isDenied || isRestricted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") {
                    Task {
                        await photoService.requestAuthorization()
                    }
                }
                .buttonStyle(.borderedProminent)
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

/// Compact focus style for the album A–Z index; the system lift effect is too large for single letters
private struct IndexLetterButtonStyle: ButtonStyle {
    let isCurrentSection: Bool

    func makeBody(configuration: Configuration) -> some View {
        IndexLetterLabel(configuration: configuration, isCurrentSection: isCurrentSection)
    }

    private struct IndexLetterLabel: View {
        let configuration: ButtonStyleConfiguration
        let isCurrentSection: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.system(size: 22, weight: .semibold))
                .minimumScaleFactor(0.6)
                .foregroundColor(isFocused ? .black : (isCurrentSection ? .blue : .white.opacity(0.6)))
                .frame(width: 44, height: 30)
                .background(Circle().fill(isFocused ? Color.white : Color.clear))
                .scaleEffect(isFocused ? 1.3 : (configuration.isPressed ? 0.9 : 1))
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
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
