import Foundation

/// Manages user settings stored in UserDefaults
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var selectedAlbumName: String? {
        didSet {
            UserDefaults.standard.set(selectedAlbumName, forKey: Keys.selectedAlbumName)
        }
    }

    @Published var weatherZipCode: String? {
        didSet {
            UserDefaults.standard.set(weatherZipCode, forKey: Keys.weatherZipCode)
        }
    }

    @Published var weatherZipCode2: String? {
        didSet {
            UserDefaults.standard.set(weatherZipCode2, forKey: Keys.weatherZipCode2)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var photoRotationInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(photoRotationInterval, forKey: Keys.photoRotationInterval)
        }
    }

    private enum Keys {
        static let selectedAlbumName = "selectedAlbumName"
        static let weatherZipCode = "weatherZipCode"
        static let weatherZipCode2 = "weatherZipCode2"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let photoRotationInterval = "photoRotationInterval"
    }

    private init() {
        // Load saved settings
        selectedAlbumName = UserDefaults.standard.string(forKey: Keys.selectedAlbumName)
        weatherZipCode = UserDefaults.standard.string(forKey: Keys.weatherZipCode)
        weatherZipCode2 = UserDefaults.standard.string(forKey: Keys.weatherZipCode2)
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Keys.hasCompletedOnboarding)

        // Default to 3 minutes if not set
        let savedInterval = UserDefaults.standard.double(forKey: Keys.photoRotationInterval)
        photoRotationInterval = savedInterval > 0 ? savedInterval : (60.0 * 3.0)
    }

    func clearAllSettings() {
        selectedAlbumName = nil
        weatherZipCode = nil
        weatherZipCode2 = nil
        hasCompletedOnboarding = false
        photoRotationInterval = 60.0 * 3.0 // Reset to default 3 minutes
    }
}
