import SwiftUI
import Photos

/// Settings view for configuring photo album and weather location
struct SettingsView: View {
    @ObservedObject var photoService: PhotoService
    @ObservedObject var weatherService: WeatherService
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var calendarManager: CalendarManager

    @State private var zipCodeInput1: String = ""
    @State private var zipCodeInput2: String = ""
    @State private var showingAlbumPicker = false
    @State private var isSaving = false
    @State private var showingZipCodeInput = false
    @State private var editingZipCode1 = false
    @State private var editingZipCode2 = false
    @State private var tempZipInput = ""
    @State private var showingICloudAuth = false
    @FocusState private var focusedField: FocusField?

    enum FocusField {
        case doneButton
    }

    @Environment(\.dismiss) private var dismiss

    /// Whether a calendar sign-in overlay is covering the settings
    private var isOverlayShowing: Bool {
        showingICloudAuth
        || calendarManager.googleService.isWaitingForAuthorization
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                HStack {
                    Spacer()
                    Text("Settings")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 40)

                ScrollView {
                    VStack(spacing: 40) {
                        // Done button at top for easy access
                        HStack {
                            Spacer()
                            Button("Done") {
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .focused($focusedField, equals: .doneButton)
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 60)

                        // Calendar Accounts Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Calendar Accounts")
                                .font(.title2)
                                .foregroundColor(.white)
                            calendarAccountsContent
                        }
                        .padding(.horizontal, 60)

                        Divider()
                            .background(Color.white.opacity(0.3))
                            .padding(.horizontal, 60)

                        // Photo Album Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Photo Album")
                                .font(.title2)
                                .foregroundColor(.white)

                            if photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited {
                                if photoService.availableAlbums.isEmpty {
                                    HStack {
                                        ProgressView()
                                        Text("Loading albums...")
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                } else {
                                    albumSelectionContent
                                }
                            } else {
                                photoAuthorizationPrompt
                            }
                        }
                        .padding(.horizontal, 60)

                        Divider()
                            .background(Color.white.opacity(0.3))
                            .padding(.horizontal, 60)

                        // Weather Location Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Weather Location")
                                .font(.title2)
                                .foregroundColor(.white)
                            weatherLocationContent
                        }
                        .padding(.horizontal, 60)
                    }
                    .padding(.bottom, 100)
                }
            }
            .disabled(isOverlayShowing)

            // Google device-code auth overlay
            if calendarManager.googleService.isWaitingForAuthorization,
               let deviceCode = calendarManager.googleService.deviceCode {
                Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 1.0)
                    .ignoresSafeArea()
                GoogleSignInView(googleService: calendarManager.googleService, deviceCode: deviceCode)
            }

            // iCloud sign-in overlay
            if showingICloudAuth {
                Color(.sRGB, red: 0.08, green: 0.08, blue: 0.12, opacity: 1.0)
                    .ignoresSafeArea()
                ICloudSignInView(
                    icloudService: calendarManager.icloudService,
                    onDismiss: { showingICloudAuth = false }
                )
            }
        }
        .onAppear {
            // Start with empty text fields - current zips are shown below
            zipCodeInput1 = ""
            zipCodeInput2 = ""

            // Set initial focus to Done button
            focusedField = .doneButton

            // Fetch albums if authorized
            if (photoService.authorizationStatus == .authorized || photoService.authorizationStatus == .limited) && photoService.availableAlbums.isEmpty {
                Task {
                    await photoService.fetchAvailableAlbums()
                }
            }
        }
    }

    private var calendarAccountsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Google Calendar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Calendar")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    if calendarManager.googleService.isAuthenticated {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                if calendarManager.googleService.isAuthenticated {
                    Button("Disconnect") {
                        calendarManager.googleService.signOut()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        Task {
                            await calendarManager.googleService.startDeviceAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)

            // iCloud Calendar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Calendar")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    if calendarManager.icloudService.isAuthenticated {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Not connected")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                Spacer()

                if calendarManager.icloudService.isAuthenticated {
                    Button("Disconnect") {
                        calendarManager.icloudService.signOut()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Connect") {
                        showingICloudAuth = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var albumSelectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedAlbum = settingsManager.selectedAlbumName {
                HStack {
                    VStack(alignment: .leading) {
                        Text(selectedAlbum)
                            .font(.body)
                            .foregroundColor(.white)
                        if let album = photoService.availableAlbums.first(where: { $0.name == selectedAlbum }) {
                            Text("\(album.assetCount) photos")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                    Button("Change") {
                        showingAlbumPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                // Photo rotation interval picker
                PhotoIntervalPicker(
                    selectedInterval: settingsManager.photoRotationInterval,
                    onSelect: { interval in
                        settingsManager.photoRotationInterval = interval
                        photoService.restartRotation()
                    }
                )
            } else {
                Button("Select Album") {
                    showingAlbumPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showingAlbumPicker) {
            albumPickerSheet
        }
    }

    private var photoIntervalOptions: [(label: String, seconds: TimeInterval)] {
        [
            ("1 min", 60),
            ("3 min", 180),
            ("5 min", 300),
            ("10 min", 600),
            ("15 min", 900),
            ("30 min", 1800)
        ]
    }

    private var albumPickerSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                HStack {
                    Spacer()
                    Text("Select Album")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 40)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(photoService.availableAlbums) { album in
                            Button(action: {
                                selectAlbum(album)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(album.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text("\(album.assetCount) photos")
                                            .font(.caption)
                                    }
                                    Spacer()
                                    if settingsManager.selectedAlbumName == album.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(20)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 100)
                }

                // Cancel button
                Button("Cancel") {
                    showingAlbumPicker = false
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 40)
            }
        }
    }

    private var photoAuthorizationPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo library access is required to select an album")
                .font(.body)
                .foregroundColor(.secondary)

            Button("Grant Access") {
                Task {
                    await photoService.requestAuthorization()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var weatherLocationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter 1 or 2 zip codes. If you enter 2, the display will alternate every 15 minutes.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            // Location 1
            VStack(alignment: .leading, spacing: 8) {
                Text("Location 1")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let currentZip = settingsManager.weatherZipCode {
                            Text(currentZip)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        } else {
                            Text("Not set")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    Button("Change") {
                        showingZipCodeInput = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }

            // Location 2
            VStack(alignment: .leading, spacing: 8) {
                Text("Location 2 (Optional)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let currentZip = settingsManager.weatherZipCode2 {
                            Text(currentZip)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        } else {
                            Text("Not set")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    Spacer()
                    if settingsManager.weatherZipCode2 != nil {
                        Button("Change") {
                            showingZipCodeInput = true
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Add") {
                            showingZipCodeInput = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
            }

            if isSaving {
                HStack {
                    ProgressView()
                    Text("Validating zip code(s)...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .sheet(isPresented: $showingZipCodeInput) {
            zipCodeEditSheet
        }
    }

    private var zipCodeEditSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Header
                HStack {
                    Spacer()
                    Text("Edit Weather Locations")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 40)

                VStack(spacing: 24) {
                    // Location 1
                    VStack(spacing: 8) {
                        Text("Location 1")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Button(action: {
                            tempZipInput = zipCodeInput1
                            editingZipCode1 = true
                        }) {
                            ZipCodeButtonContent(
                                zipCode: zipCodeInput1,
                                backgroundColor: Color.white.opacity(0.15)
                            )
                        }
                        .buttonStyle(ZipCodeButtonStyle())
                    }

                    // Location 2
                    VStack(spacing: 8) {
                        Text("Location 2 (Optional)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

                        Button(action: {
                            tempZipInput = zipCodeInput2
                            editingZipCode2 = true
                        }) {
                            ZipCodeButtonContent(
                                zipCode: zipCodeInput2,
                                backgroundColor: Color.white.opacity(0.1)
                            )
                        }
                        .buttonStyle(ZipCodeButtonStyle())
                    }
                }
                .padding(.horizontal, 60)

                Spacer()

                // Buttons
                HStack(spacing: 30) {
                    Button("Cancel") {
                        showingZipCodeInput = false
                        zipCodeInput1 = ""
                        zipCodeInput2 = ""
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        saveZipCodes()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(zipCodeInput1.count != 5 && zipCodeInput2.count != 5)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Pre-fill with current values
            zipCodeInput1 = settingsManager.weatherZipCode ?? ""
            zipCodeInput2 = settingsManager.weatherZipCode2 ?? ""
        }
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

    private func selectAlbum(_ album: PhotoAlbum) {
        settingsManager.selectedAlbumName = album.name
        showingAlbumPicker = false

        // Reload photos with new album
        Task {
            await photoService.loadPhotos()
        }
    }

    private func saveZipCodes() {
        // At least one zip code must be provided and valid
        guard zipCodeInput1.count == 5 || zipCodeInput2.count == 5 else { return }

        isSaving = true

        Task {
            do {
                // Validate zip code 1 if provided
                if zipCodeInput1.count == 5 {
                    _ = try await weatherService.geocodeZipCode(zipCodeInput1)
                }

                // Validate zip code 2 if provided
                if zipCodeInput2.count == 5 {
                    _ = try await weatherService.geocodeZipCode(zipCodeInput2)
                }

                // If successful, save them
                settingsManager.weatherZipCode = zipCodeInput1.count == 5 ? zipCodeInput1 : settingsManager.weatherZipCode
                settingsManager.weatherZipCode2 = zipCodeInput2.count == 5 ? zipCodeInput2 : nil

                weatherService.clearLocationCache()

                // Fetch weather for new locations
                await weatherService.fetchWeather()

                isSaving = false
                showingZipCodeInput = false
                zipCodeInput1 = ""
                zipCodeInput2 = ""
            } catch {
                isSaving = false
                // Show error (in a real app, you'd show an alert)
                print("Invalid zip code(s): \(error.localizedDescription)")
            }
        }
    }
}

// Custom button style for zip code input that changes text color on focus
struct ZipCodeButtonStyle: ButtonStyle {
    @Environment(\.isFocused) var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.zipCodeButtonFocused, isFocused)
    }
}

// Custom environment key for passing focus state to content
private struct ZipCodeButtonFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var zipCodeButtonFocused: Bool {
        get { self[ZipCodeButtonFocusedKey.self] }
        set { self[ZipCodeButtonFocusedKey.self] = newValue }
    }
}

// Content view that responds to focus state
struct ZipCodeButtonContent: View {
    let zipCode: String
    let backgroundColor: Color
    @Environment(\.zipCodeButtonFocused) var isFocused

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
        .frame(minWidth: 500, maxWidth: 600)
    }
}

// Photo interval picker component with proper focus management
struct PhotoIntervalPicker: View {
    let selectedInterval: TimeInterval
    let onSelect: (TimeInterval) -> Void

    @State private var internalSelectedIndex: Int = 1 // Default to 3 min
    @FocusState private var isFocused: Bool

    private let options: [(label: String, seconds: TimeInterval)] = [
        ("1 min", 60),
        ("3 min", 180),
        ("5 min", 300),
        ("10 min", 600),
        ("15 min", 900),
        ("30 min", 1800)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo Change Interval")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Button(action: {
                // Select the currently highlighted option on button press
                onSelect(options[internalSelectedIndex].seconds)
            }) {
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Text(option.label)
                            .font(.caption)
                            .fontWeight(selectedInterval == option.seconds ? .semibold : .regular)
                            .foregroundColor(textColor(for: index))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(backgroundColor(for: index))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        isFocused && internalSelectedIndex == index ? Color.white : Color.clear,
                                        lineWidth: 3
                                    )
                                    .padding(2)
                            )
                    }
                }
                .cornerRadius(8)
            }
            .buttonStyle(IntervalPickerButtonStyle())
            .focused($isFocused)
            .onMoveCommand { direction in
                guard isFocused else { return }

                switch direction {
                case .left:
                    if internalSelectedIndex > 0 {
                        internalSelectedIndex -= 1
                        onSelect(options[internalSelectedIndex].seconds)
                    }
                case .right:
                    if internalSelectedIndex < options.count - 1 {
                        internalSelectedIndex += 1
                        onSelect(options[internalSelectedIndex].seconds)
                    }
                default:
                    break
                }
            }
        }
        .onAppear {
            // Set initial index based on selected interval
            if let index = options.firstIndex(where: { $0.seconds == selectedInterval }) {
                internalSelectedIndex = index
            }
        }
    }

    private func textColor(for index: Int) -> Color {
        let isSelected = selectedInterval == options[index].seconds
        let isHighlighted = isFocused && internalSelectedIndex == index

        if isHighlighted {
            return isSelected ? .white : .black
        } else {
            return .white
        }
    }

    private func backgroundColor(for index: Int) -> Color {
        let isSelected = selectedInterval == options[index].seconds
        let isHighlighted = isFocused && internalSelectedIndex == index

        if isHighlighted {
            return isSelected ? Color.blue : Color.white
        } else {
            return isSelected ? Color.blue : Color.white.opacity(0.1)
        }
    }
}

// Custom button style that prevents the default focus effect
struct IntervalPickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

#Preview {
    SettingsView(
        photoService: PhotoService(),
        weatherService: WeatherService(),
        settingsManager: SettingsManager.shared,
        calendarManager: CalendarManager()
    )
}
